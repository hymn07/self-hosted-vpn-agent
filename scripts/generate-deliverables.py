#!/usr/bin/env python3
"""Generate the private deployment handoff from live Hiddify state."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from deployment_config import ConfigError, load_config, resolve_users


def url(domain: str, *parts: object) -> str:
    clean_parts = [str(part).strip("/") for part in parts if str(part).strip("/")]
    return f"https://{domain}/" + "/".join(clean_parts) + "/"


def write_restricted(path: Path, content: str) -> None:
    path.write_text(content.rstrip() + "\n", encoding="utf-8")
    os.chmod(path, 0o600)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("config")
    parser.add_argument("output_dir")
    parser.add_argument("--hiddify-root", default="/opt/hiddify-manager")
    parser.add_argument(
        "--validated",
        action="store_true",
        help="仅在 health-check 与 verify-subscription 均零失败后使用",
    )
    args = parser.parse_args()
    try:
        cfg = load_config(args.config)
        requested_users = resolve_users(cfg)
    except ConfigError as exc:
        parser.error(str(exc))

    current_path = Path(args.hiddify_root) / "current.json"
    current = json.loads(current_path.read_text(encoding="utf-8"))
    server_ip = cfg["server"]["ip"]
    domain_cfg = cfg["domain"]
    domain = (
        domain_cfg["custom_domain"]
        if domain_cfg["mode"] == "custom"
        else f"{server_ip}.sslip.io"
    )

    panel_dir = Path(args.hiddify_root) / "hiddify-panel"
    if not panel_dir.is_dir():
        parser.error(f"找不到 HiddifyPanel 目录: {panel_dir}")
    os.chdir(panel_dir)
    import hiddifypanel

    app = hiddifypanel.create_app()
    accounts: list[dict[str, object]] = []
    with app.app_context():
        from hiddifypanel.models import ConfigEnum, User, hconfig

        client_path = str(hconfig(ConfigEnum.proxy_path_client)).strip("/")
        for spec in requested_users:
            user = User.query.filter(User.name == spec["name"]).first()
            if not user:
                raise RuntimeError(f"配置账户不存在于面板: {spec['name']}")
            accounts.append(
                {
                    **spec,
                    "clash": url(domain, client_path, user.uuid, "clashmeta"),
                    "auto": url(domain, client_path, user.uuid, "auto"),
                }
            )

    admin_url = url(domain, current["admin_path"])
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    secret_lines = [
        "# 部署访问资料",
        "",
        "> 本文件含管理路径和用户订阅凭据，只能保存在 `.local/`，不得公开。",
        "",
        f"- 管理面板：{admin_url}",
        "",
        "## 用户订阅",
        "",
    ]
    for account in accounts:
        secret_lines.extend(
            [
                f"### {account['name']}",
                "",
                f"- Mihomo / Clash：{account['clash']}",
                f"- Shadowrocket / 通用：{account['auto']}",
                "",
            ]
        )
    write_restricted(output_dir / "SECRETS.md", "\n".join(secret_lines))

    guide_lines = [
        "# VPN 使用说明",
        "",
        "> 这份文件包含实际订阅链接，请妥善保管，不要提交到 Git。",
        "",
        "## 管理后台",
        "",
        f"- 地址：{admin_url}",
        "- 用途：查看流量、增加或停用账户、调整配额。",
        "",
        "## 账户链接",
        "",
    ]
    for account in accounts:
        guide_lines.extend(
            [
                f"### {account['name']}（{account['quota_gb']:g}GB，{account['reset_mode']}）",
                "",
                f"- Mihomo / Clash：{account['clash']}",
                f"- Shadowrocket / 通用：{account['auto']}",
                "",
            ]
        )
    guide_lines.extend(
        [
            "## 导入方法",
            "",
            "- Windows / macOS：在 Clash Verge Rev 的订阅页粘贴 Mihomo / Clash 链接并启用系统代理。",
            "- Android：在 Mihomo 系客户端新增 URL 配置并粘贴 Mihomo / Clash 链接。",
            "- iPhone：在 Shadowrocket 新增 Subscribe，粘贴通用链接并更新订阅。",
            "",
            "## 故障处理",
            "",
            "- 如果此前可用，后来面板、订阅和全部节点同时超时，不要直接重装或更换 IP。",
            "- 让 Agent 先运行仓库的 `diagnose-resources.sh` 做只读诊断，再根据证据决定恢复动作。",
            "",
            "## 安全提醒",
            "",
            "- 订阅链接就是账户凭据，只发给对应使用者。",
            "- 管理后台地址和密码不要公开。",
            "- 每月检查 Lightsail 流量与账单；发现异常立即停用对应账户。",
        ]
    )
    write_restricted(output_dir / "USER_GUIDE.md", "\n".join(guide_lines))

    report_lines = [
        "# Deployment Report",
        "",
        "- Provider: AWS Lightsail",
        f"- Region: {cfg['instance']['region']}",
        f"- Plan: {cfg['instance']['plan_label']}",
        f"- Expected monthly cost: USD {cfg['instance']['monthly_cost_usd']:g}",
        f"- Hiddify: {cfg['hiddify']['version']}",
        f"- Domain mode: {cfg['domain']['mode']}",
        f"- Reality: {'enabled' if cfg['protocols']['reality'] else 'disabled'}",
        f"- Hysteria2: {'enabled' if cfg['protocols']['hysteria2'] else 'disabled'}",
        f"- Swap: {cfg['security']['swap_size_gb']:g} GB",
        f"- Ubuntu automatic security updates: "
        f"{'enabled' if cfg['security']['enable_auto_updates'] else 'disabled'}",
        f"- Accounts: {len(accounts)}",
        f"- Health check: {'PASS' if args.validated else 'PENDING'}",
        f"- Subscription verification: {'PASS' if args.validated else 'PENDING'}",
        "",
        "## Accounts",
        "",
        "| Name | Quota | Reset | Validity |",
        "|---|---:|---|---:|",
    ]
    for account in accounts:
        report_lines.append(
            f"| {account['name']} | {account['quota_gb']:g}GB | "
            f"{account['reset_mode']} | {account['validity_days']} days |"
        )
    report_lines.extend(
        [
            "",
            "- PASS 只表示生成前两项仓库验证脚本均为零失败。",
            "- 后台地址和订阅链接：见同目录 `SECRETS.md`。",
        ]
    )
    write_restricted(output_dir / "DEPLOYMENT_REPORT.md", "\n".join(report_lines))
    print(f"交付文件已生成到 {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
