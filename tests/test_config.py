from __future__ import annotations

import copy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from deployment_config import ConfigError, load_config, resolve_users  # noqa: E402


class DeploymentConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.base = yaml.safe_load(
            (ROOT / "config" / "deployment.example.yaml").read_text(encoding="utf-8")
        )

    def load(self, data: dict) -> dict:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "deployment.yaml"
            path.write_text(yaml.safe_dump(data, allow_unicode=True), encoding="utf-8")
            return load_config(path)

    def test_default_proposal_is_valid(self) -> None:
        cfg = self.load(self.base)
        users = resolve_users(cfg)
        self.assertEqual([u["name"] for u in users], ["user1", "user2", "user3"])
        self.assertEqual([u["quota_gb"] for u in users], [500.0, 500.0, 500.0])

    def test_any_account_can_override_defaults(self) -> None:
        data = copy.deepcopy(self.base)
        data["users"]["accounts"] = [
            {"name": "team-a", "quota_gb": 200, "validity_days": 365},
            {"name": "team-b", "reset_mode": "weekly"},
        ]
        users = resolve_users(self.load(data))
        self.assertEqual(users[0]["quota_gb"], 200.0)
        self.assertEqual(users[0]["validity_days"], 365)
        self.assertEqual(users[1]["reset_mode"], "weekly")

    def test_quota_guard_uses_selected_plan_and_reserve(self) -> None:
        data = copy.deepcopy(self.base)
        data["users"]["accounts"] = [
            {"name": "a", "quota_gb": 1000},
            {"name": "b", "quota_gb": 1000},
        ]
        with self.assertRaisesRegex(ConfigError, "套餐上限"):
            self.load(data)

    def test_names_are_unique_case_insensitively(self) -> None:
        data = copy.deepcopy(self.base)
        data["users"]["accounts"] = [{"name": "Alice"}, {"name": "alice"}]
        with self.assertRaisesRegex(ConfigError, "name 必须唯一"):
            self.load(data)

    def test_at_least_one_account_is_required(self) -> None:
        data = copy.deepcopy(self.base)
        data["users"]["accounts"] = []
        with self.assertRaisesRegex(ConfigError, "至少需要 1 个账户"):
            self.load(data)

    def test_custom_domain_requires_a_name(self) -> None:
        data = copy.deepcopy(self.base)
        data["domain"]["mode"] = "custom"
        with self.assertRaisesRegex(ConfigError, "custom_domain"):
            self.load(data)

    def test_custom_domain_rejects_a_url(self) -> None:
        data = copy.deepcopy(self.base)
        data["domain"] = {
            "mode": "custom",
            "custom_domain": "https://vpn.example.com/path",
        }
        with self.assertRaisesRegex(ConfigError, "纯域名"):
            self.load(data)

    def test_unverified_hiddify_version_is_rejected(self) -> None:
        data = copy.deepcopy(self.base)
        data["hiddify"]["version"] = "latest"
        with self.assertRaisesRegex(ConfigError, "未经过验证"):
            self.load(data)

    def test_control_characters_are_rejected(self) -> None:
        data = copy.deepcopy(self.base)
        data["branding"]["profile_title"] = "bad\r\nheader"
        with self.assertRaisesRegex(ConfigError, "换行"):
            self.load(data)

    def test_server_copy_removes_local_key_path(self) -> None:
        data = copy.deepcopy(self.base)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            key = root / "server.pem"
            key.write_text("test-only", encoding="utf-8")
            data["server"]["ip"] = "127.0.0.1"
            data["server"]["ssh_key_path"] = str(key)
            source = root / "deployment.yaml"
            output = root / "server.yaml"
            source.write_text(
                yaml.safe_dump(data, allow_unicode=True), encoding="utf-8"
            )
            subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts" / "deployment_config.py"),
                    "server-copy",
                    str(source),
                    str(output),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            server_cfg = yaml.safe_load(output.read_text(encoding="utf-8"))
            self.assertEqual(server_cfg["server"]["ssh_key_path"], "")
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)


if __name__ == "__main__":
    unittest.main()
