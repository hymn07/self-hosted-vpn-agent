#!/usr/bin/env python3
"""Apply the protocol selection from deployment.yaml inside Hiddify's venv."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

from deployment_config import ConfigError, load_config


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("config")
    parser.add_argument("--hiddify-root", default="/opt/hiddify-manager")
    args = parser.parse_args()
    try:
        cfg = load_config(args.config)
    except ConfigError as exc:
        parser.error(str(exc))

    panel_dir = Path(args.hiddify_root) / "hiddify-panel"
    if not panel_dir.is_dir():
        parser.error(f"找不到 HiddifyPanel 目录: {panel_dir}")
    os.chdir(panel_dir)
    import hiddifypanel

    app = hiddifypanel.create_app()
    with app.app_context():
        from hiddifypanel.models import ConfigEnum, set_hconfig

        set_hconfig(ConfigEnum.reality_enable, cfg["protocols"]["reality"])
        set_hconfig(ConfigEnum.hysteria_enable, cfg["protocols"]["hysteria2"])
        set_hconfig(ConfigEnum.branding_title, cfg["branding"]["profile_title"])
        for key in (
            "tuic_enable",
            "wireguard_enable",
            "vmess_enable",
            "naive_enable",
            "dnstt_enable",
            "ssh_server_enable",
            "shadowsocks2022_enable",
            "ssfaketls_enable",
            "shadowtls_enable",
            "ssr_enable",
            "trojan_enable",
            "telegram_enable",
            "xtls_enable",
            "h2_enable",
            "kcp_enable",
            "v2ray_enable",
            "mieru_enable",
            "xhttp_enable",
            "httpupgrade_enable",
            "ws_enable",
            "tcp_enable",
            "quic_enable",
            "grpc_enable",
            "vless_enable",
            "http_proxy_enable",
            "domain_fronting_http_enable",
            "domain_fronting_tls_enable",
        ):
            set_hconfig(ConfigEnum[key], False)
        set_hconfig(ConfigEnum.country, "UN")
    print("协议配置已写入；下一步重启面板并运行 apply_configs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
