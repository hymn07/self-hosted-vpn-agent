#!/usr/bin/env python3
"""Validate and read the deployment configuration.

This is the single parser used by local checks and server-side deployment scripts.
It intentionally prints no secrets in the human-readable summary.
"""

from __future__ import annotations

import argparse
import copy
import ipaddress
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

import yaml


SUPPORTED_VERSION = "12.3.3"
RESET_MODES = {"monthly", "weekly", "daily", "no_reset"}
DOMAIN_LABEL = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")


class ConfigError(ValueError):
    pass


def require_mapping(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ConfigError(f"{path} 必须是 mapping")
    return value


def require_string(value: Any, path: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise ConfigError(f"{path} 必须是字符串")
    if not allow_empty and not value.strip():
        raise ConfigError(f"{path} 不能为空")
    if any(char in value for char in ("\r", "\n", "\t")):
        raise ConfigError(f"{path} 不能包含换行或制表符")
    return value.strip()


def require_number(value: Any, path: str, *, minimum: float = 0) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ConfigError(f"{path} 必须是数字")
    if not math.isfinite(float(value)) or float(value) < minimum:
        raise ConfigError(f"{path} 必须 >= {minimum}")
    return float(value)


def load_config(path: str | Path, *, runtime: bool = False) -> dict[str, Any]:
    config_path = Path(path)
    try:
        raw = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ConfigError(f"配置文件不存在: {config_path}") from exc
    except yaml.YAMLError as exc:
        raise ConfigError(f"YAML 无法解析: {exc}") from exc

    cfg = require_mapping(raw, "root")
    if cfg.get("provider") != "aws_lightsail":
        raise ConfigError("provider 当前只支持 aws_lightsail")

    server = require_mapping(cfg.get("server"), "server")
    server_ip = require_string(server.get("ip", ""), "server.ip", allow_empty=True)
    require_string(server.get("ssh_user"), "server.ssh_user")
    key_path = require_string(
        server.get("ssh_key_path", ""), "server.ssh_key_path", allow_empty=True
    )
    if server_ip:
        try:
            ipaddress.ip_address(server_ip)
        except ValueError as exc:
            raise ConfigError("server.ip 不是有效 IP 地址") from exc
    if runtime:
        if not server_ip:
            raise ConfigError("运行部署前必须填写 server.ip")
        if not key_path:
            raise ConfigError("运行部署前必须填写 server.ssh_key_path")
        if not Path(key_path).expanduser().is_file():
            raise ConfigError("server.ssh_key_path 指向的文件不存在")

    instance = require_mapping(cfg.get("instance"), "instance")
    require_string(instance.get("region"), "instance.region")
    require_string(instance.get("name"), "instance.name")
    require_string(instance.get("plan_label"), "instance.plan_label")
    require_number(instance.get("memory_gb"), "instance.memory_gb", minimum=1)
    transfer_gb = require_number(
        instance.get("monthly_transfer_gb"), "instance.monthly_transfer_gb", minimum=1
    )
    require_number(
        instance.get("monthly_cost_usd"), "instance.monthly_cost_usd", minimum=0
    )

    hiddify = require_mapping(cfg.get("hiddify"), "hiddify")
    version = require_string(hiddify.get("version"), "hiddify.version")
    if version != SUPPORTED_VERSION:
        raise ConfigError(
            f"hiddify.version={version} 未经过验证；当前只支持 {SUPPORTED_VERSION}"
        )

    protocols = require_mapping(cfg.get("protocols"), "protocols")
    for key in ("reality", "hysteria2"):
        if not isinstance(protocols.get(key), bool):
            raise ConfigError(f"protocols.{key} 必须是 true/false")
    if not any(protocols[key] for key in ("reality", "hysteria2")):
        raise ConfigError("Reality 与 Hysteria2 不能同时关闭")

    domain = require_mapping(cfg.get("domain"), "domain")
    mode = require_string(domain.get("mode"), "domain.mode")
    if mode not in {"sslip", "custom"}:
        raise ConfigError("domain.mode 只能是 sslip 或 custom")
    custom_domain = require_string(
        domain.get("custom_domain", ""), "domain.custom_domain", allow_empty=True
    )
    if mode == "custom" and not custom_domain:
        raise ConfigError("domain.mode=custom 时必须填写 domain.custom_domain")
    if custom_domain:
        normalized_domain = custom_domain.rstrip(".")
        labels = normalized_domain.split(".")
        if (
            normalized_domain != custom_domain
            or len(normalized_domain) > 253
            or len(labels) < 2
            or any(not DOMAIN_LABEL.fullmatch(label) for label in labels)
        ):
            raise ConfigError("domain.custom_domain 必须是纯域名，不含协议、端口或路径")

    branding = require_mapping(cfg.get("branding"), "branding")
    node_prefix = require_string(branding.get("node_prefix"), "branding.node_prefix")
    if len(node_prefix) > 32:
        raise ConfigError("branding.node_prefix 最长 32 个字符")
    profile_title = require_string(
        branding.get("profile_title", ""), "branding.profile_title", allow_empty=True
    )
    if len(profile_title) > 80:
        raise ConfigError("branding.profile_title 最长 80 个字符")
    security = require_mapping(cfg.get("security"), "security")
    for key in ("disable_password_ssh", "enable_auto_updates", "delete_default_user"):
        if not isinstance(security.get(key), bool):
            raise ConfigError(f"security.{key} 必须是 true/false")
    reserve = require_number(
        security.get("quota_reserve_ratio"), "security.quota_reserve_ratio", minimum=0
    )
    if reserve >= 1:
        raise ConfigError("security.quota_reserve_ratio 必须小于 1")

    resolved = resolve_users(cfg)
    names = [user["name"].casefold() for user in resolved]
    if len(names) != len(set(names)):
        raise ConfigError("users.accounts 中的 name 必须唯一")
    total_quota = sum(float(user["quota_gb"]) for user in resolved)
    safe_quota = transfer_gb * (1 - reserve)
    if total_quota > safe_quota:
        raise ConfigError(
            f"用户配额合计 {total_quota:g}GB 超过预留余量后的套餐上限 {safe_quota:g}GB"
        )

    cost_control = require_mapping(cfg.get("cost_control"), "cost_control")
    require_number(cost_control.get("budget_usd"), "cost_control.budget_usd", minimum=1)
    return cfg


def resolve_users(cfg: dict[str, Any]) -> list[dict[str, Any]]:
    users = require_mapping(cfg.get("users"), "users")
    defaults = require_mapping(users.get("defaults"), "users.defaults")
    default_quota = require_number(
        defaults.get("quota_gb"), "users.defaults.quota_gb", minimum=0.01
    )
    default_mode = require_string(
        defaults.get("reset_mode"), "users.defaults.reset_mode"
    )
    if default_mode not in RESET_MODES:
        raise ConfigError(
            f"users.defaults.reset_mode 必须是 {sorted(RESET_MODES)} 之一"
        )
    default_days = require_number(
        defaults.get("validity_days"), "users.defaults.validity_days", minimum=1
    )
    if not float(default_days).is_integer():
        raise ConfigError("users.defaults.validity_days 必须是整数")

    accounts = users.get("accounts")
    if not isinstance(accounts, list):
        raise ConfigError("users.accounts 必须是列表")
    if not accounts:
        raise ConfigError("users.accounts 至少需要 1 个账户")

    resolved: list[dict[str, Any]] = []
    for index, account_raw in enumerate(accounts):
        account = require_mapping(account_raw, f"users.accounts[{index}]")
        name = require_string(account.get("name"), f"users.accounts[{index}].name")
        quota = require_number(
            account.get("quota_gb", default_quota),
            f"users.accounts[{index}].quota_gb",
            minimum=0.01,
        )
        reset_mode = require_string(
            account.get("reset_mode", default_mode),
            f"users.accounts[{index}].reset_mode",
        )
        if reset_mode not in RESET_MODES:
            raise ConfigError(
                f"users.accounts[{index}].reset_mode 必须是 {sorted(RESET_MODES)} 之一"
            )
        days = require_number(
            account.get("validity_days", default_days),
            f"users.accounts[{index}].validity_days",
            minimum=1,
        )
        if not float(days).is_integer():
            raise ConfigError(f"users.accounts[{index}].validity_days 必须是整数")
        resolved.append(
            {
                "name": name,
                "quota_gb": quota,
                "reset_mode": reset_mode,
                "validity_days": int(days),
            }
        )
    return resolved


def get_path(cfg: dict[str, Any], dotted_path: str) -> Any:
    value: Any = cfg
    for part in dotted_path.split("."):
        if not isinstance(value, dict) or part not in value:
            raise ConfigError(f"配置项不存在: {dotted_path}")
        value = value[part]
    return value


def print_summary(cfg: dict[str, Any]) -> None:
    users = resolve_users(cfg)
    transfer = cfg["instance"]["monthly_transfer_gb"]
    total_quota = sum(float(user["quota_gb"]) for user in users)
    domain = cfg["domain"]
    domain_label = (
        "免费 sslip.io" if domain["mode"] == "sslip" else domain["custom_domain"]
    )
    protocol_names = [name for name, enabled in cfg["protocols"].items() if enabled]
    print("默认/已确认部署方案")
    print(f"- 区域: {cfg['instance']['region']}")
    print(
        f"- 套餐: {cfg['instance']['plan_label']} / ${cfg['instance']['monthly_cost_usd']:g}每月 / "
        f"{transfer:g}GB 流量"
    )
    print(f"- 账户: {len(users)} 个，配额合计 {total_quota:g}GB")
    for user in users:
        print(
            f"  - {user['name']}: {user['quota_gb']:g}GB / {user['reset_mode']} / "
            f"{user['validity_days']} 天"
        )
    print(f"- 协议: {', '.join(protocol_names)}")
    print(f"- 域名: {domain_label}")
    print(f"- 节点前缀: {cfg['branding']['node_prefix']}")
    print(f"- 订阅名称: {cfg['branding']['profile_title'] or '使用账户名'}")
    print(f"- Static IP: {'已填写' if cfg['server']['ip'] else '待填写'}")
    print(f"- SSH 私钥路径: {'已填写' if cfg['server']['ssh_key_path'] else '待填写'}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("validate", "summary", "resolved-users"):
        item = sub.add_parser(command)
        item.add_argument("config")
        item.add_argument("--runtime", action="store_true")
    get_parser = sub.add_parser("get")
    get_parser.add_argument("config")
    get_parser.add_argument("path")
    get_parser.add_argument("--runtime", action="store_true")
    server_copy = sub.add_parser("server-copy")
    server_copy.add_argument("config")
    server_copy.add_argument("output")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "server-copy":
            cfg = load_config(args.config, runtime=True)
            server_cfg = copy.deepcopy(cfg)
            server_cfg["server"]["ssh_key_path"] = ""
            output = Path(args.output)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(
                yaml.safe_dump(server_cfg, allow_unicode=True, sort_keys=False),
                encoding="utf-8",
            )
            output.chmod(0o600)
            print(f"服务器配置已写入: {output}")
            return 0
        cfg = load_config(args.config, runtime=args.runtime)
        if args.command == "validate":
            print("配置有效")
        elif args.command == "summary":
            print_summary(cfg)
        elif args.command == "resolved-users":
            print(json.dumps(resolve_users(cfg), ensure_ascii=False, indent=2))
        elif args.command == "get":
            value = get_path(cfg, args.path)
            if isinstance(value, bool):
                print("true" if value else "false")
            elif isinstance(value, (dict, list)):
                print(json.dumps(value, ensure_ascii=False))
            else:
                print(value)
        return 0
    except ConfigError as exc:
        print(f"配置错误: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
