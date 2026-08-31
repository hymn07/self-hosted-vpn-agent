#!/usr/bin/env python3
"""Idempotently create or update configured Hiddify users by account name."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
from uuid import uuid4

from deployment_config import ConfigError, load_config, resolve_users


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("config")
    parser.add_argument("--hiddify-root", default="/opt/hiddify-manager")
    args = parser.parse_args()
    try:
        cfg = load_config(args.config)
        requested_users = resolve_users(cfg)
    except ConfigError as exc:
        parser.error(str(exc))

    panel_dir = Path(args.hiddify_root) / "hiddify-panel"
    if not panel_dir.is_dir():
        parser.error(f"找不到 HiddifyPanel 目录: {panel_dir}")
    os.chdir(panel_dir)
    import hiddifypanel

    app = hiddifypanel.create_app()
    created = 0
    updated = 0
    deleted_default = 0
    with app.app_context():
        from hiddifypanel.database import db
        from hiddifypanel.models import User

        for spec in requested_users:
            existing = User.query.filter(User.name == spec["name"]).first()
            user_uuid = existing.uuid if existing else str(uuid4())
            user = User.add_or_update(
                commit=False,
                old_uuid=user_uuid,
                uuid=user_uuid,
                name=spec["name"],
                usage_limit_GB=spec["quota_gb"],
                package_days=spec["validity_days"],
                mode=spec["reset_mode"],
                enable=True,
            )
            user.password = ""
            if existing:
                updated += 1
            else:
                created += 1

        if cfg["security"]["delete_default_user"]:
            for default_user in User.query.filter(User.name == "default").all():
                db.session.delete(default_user)
                deleted_default += 1
        db.session.commit()

    print(
        f"账户配置完成: {created} created / {updated} updated / "
        f"{deleted_default} default removed"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
