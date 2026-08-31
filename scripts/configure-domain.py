#!/usr/bin/env python3
"""Ensure the configured public domain exists as a direct Hiddify domain."""

from __future__ import annotations

import argparse
import ipaddress
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

    domain_cfg = cfg["domain"]
    domain_name = (
        domain_cfg["custom_domain"]
        if domain_cfg["mode"] == "custom"
        else f"{cfg['server']['ip']}.sslip.io"
    )

    panel_dir = Path(args.hiddify_root) / "hiddify-panel"
    if not panel_dir.is_dir():
        parser.error(f"找不到 HiddifyPanel 目录: {panel_dir}")
    os.chdir(panel_dir)
    import hiddifypanel

    app = hiddifypanel.create_app()
    with app.app_context():
        from hiddifypanel.database import db
        from hiddifypanel.models.domain import Domain, DomainType

        desired = Domain.query.filter(Domain.domain == domain_name).first()
        if not desired:
            # 自有域名或换 IP 时优先复用安装器创建的 sslip.io 记录，保留其端口索引。
            desired = (
                Domain.query.filter(Domain.domain.like("%.sslip.io"))
                .order_by(Domain.id)
                .first()
            )
        if desired:
            desired.domain = domain_name
            desired.mode = DomainType.direct
            desired.alias = cfg["branding"]["node_prefix"]
            desired.cdn_ip = ""
            desired.grpc = False
            desired.servernames = ""
            desired.resolve_ip = False
            desired.extra_params = "{}"
        else:
            desired = Domain.add_or_update(
                commit=False,
                domain=domain_name,
                mode=DomainType.direct,
                alias=cfg["branding"]["node_prefix"],
                cdn_ip="",
                grpc=False,
                servernames="",
                resolve_ip=False,
                extra_params="{}",
                show_domains=[],
            )

        # Hiddify 默认还可能保留一个裸 IP direct domain；换 IP 时同步更新。
        for domain in Domain.query.filter(Domain.mode == DomainType.direct).all():
            try:
                ipaddress.ip_address(domain.domain)
            except (TypeError, ValueError):
                continue
            domain.domain = cfg["server"]["ip"]
            domain.alias = cfg["branding"]["node_prefix"]
        db.session.commit()
    print(f"域名配置完成: {domain_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
