from __future__ import annotations

import sys
import unittest
from pathlib import Path


TESTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS_DIR))

from scan_secrets import find_content_issues, find_path_issues  # noqa: E402


class SecretScanTests(unittest.TestCase):
    def labels(self, text: str) -> set[str]:
        return {label for label, _ in find_content_issues(text)}

    def test_detects_uuid_and_public_ip(self) -> None:
        public_ip = "8.8." + "8.8"
        user_uuid = "15b12345-3bca-" + "4dc4-be9c-68e553cb376c"
        labels = self.labels(f"server={public_ip} user={user_uuid}")
        self.assertIn("public IPv4 address", labels)
        self.assertIn("canonical UUID", labels)

    def test_allows_placeholders_and_non_public_addresses(self) -> None:
        self.assertEqual(
            self.labels("https://<DOMAIN>/<CLIENT_PATH>/<UUID>/ 127.0.0.1"), set()
        )

    def test_detects_credential_like_url_but_allows_repository_url(self) -> None:
        self.assertIn(
            "URL with credential-like path",
            self.labels(
                "https://vpn.example.net/" + "uTdIxxxxBnhSN0CcprWA97Yz" + "/auto/"
            ),
        )
        self.assertEqual(
            self.labels("https://github.com/hymn07/self-hosted-vpn-agent"), set()
        )

    def test_rejects_sensitive_tracked_paths(self) -> None:
        self.assertIn("tracked .local file", find_path_issues(".local/SECRETS.md"))
        self.assertIn("tracked key file", find_path_issues("keys/server.pem"))


if __name__ == "__main__":
    unittest.main()
