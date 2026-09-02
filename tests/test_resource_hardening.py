from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ResourceHardeningTests(unittest.TestCase):
    def test_resource_guard_does_not_force_cache_drop_or_service_restart(self) -> None:
        hardener = (ROOT / "scripts" / "harden-server.sh").read_text(encoding="utf-8")
        self.assertNotIn("drop_caches", hardener)
        self.assertNotIn("systemctl restart hiddify-panel", hardener)
        self.assertFalse((ROOT / "scripts" / "memory-watchdog.sh").exists())

    def test_swap_is_configured_before_package_updates(self) -> None:
        hardener = (ROOT / "scripts" / "harden-server.sh").read_text(encoding="utf-8")
        self.assertLess(
            hardener.index('swapon "$SWAP_FILE"'), hardener.index("apt-get update")
        )
        self.assertIn("99-self-hosted-vpn-agent-periodic", hardener)
        self.assertNotIn(">/etc/apt/apt.conf.d/20auto-upgrades", hardener)

    def test_resource_diagnostics_are_read_only(self) -> None:
        diagnostic = (ROOT / "scripts" / "diagnose-resources.sh").read_text(
            encoding="utf-8"
        )
        for mutating_command in (
            "systemctl restart",
            "systemctl stop",
            "systemctl disable",
            "kill -",
            "drop_caches",
            "swapon /",
            "mkswap",
            "apt-get",
        ):
            with self.subTest(command=mutating_command):
                self.assertNotIn(mutating_command, diagnostic)

    def test_health_check_rejects_legacy_restart_watchdog(self) -> None:
        health_check = (ROOT / "scripts" / "health-check.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("/usr/local/bin/memory-watchdog.sh", health_check)
        self.assertIn("旧内存看门狗", health_check)


if __name__ == "__main__":
    unittest.main()
