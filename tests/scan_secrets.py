#!/usr/bin/env python3
"""Scan tracked files and reachable Git history for deployment secrets."""

from __future__ import annotations

import ipaddress
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
TEXT_PATTERNS = (
    (
        "private key material",
        re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    ),
    ("AWS access key", re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b")),
    (
        "GitHub token",
        re.compile(r"\b(?:ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"),
    ),
    ("OpenAI API key", re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b")),
    ("Slack token", re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{20,}\b")),
    (
        "canonical UUID",
        re.compile(
            r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-"
            r"[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\b"
        ),
    ),
    ("local macOS path", re.compile(r"/" + r"Users/[^\s/'\"]+")),
    (
        "assigned API credential",
        re.compile(
            r"(?i)\b(?:api[_-]?key|access[_-]?token|secret[_-]?key)\s*[:=]\s*"
            r"[\"']?[A-Za-z0-9_./+=-]{16,}"
        ),
    ),
)
IPV4_PATTERN = re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
URL_PATTERN = re.compile(r"https?://[^\s<>\"'`)\]]+")
RANDOM_PATH_SEGMENT = re.compile(r"[A-Za-z0-9_-]{20,}")
SAFE_URL_HOSTS = {
    "github.com",
    "githubusercontent.com",
    "creativecommons.org",
    "example.com",
    "www.example.com",
    "i.hiddify.com",
}


def run_git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args], cwd=ROOT)


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def find_path_issues(path: str) -> list[str]:
    normalized = path.replace("\\", "/")
    parts = Path(normalized).parts
    issues: list[str] = []
    if parts and parts[0] == ".local":
        issues.append("tracked .local file")
    if normalized.endswith((".pem", ".key")):
        issues.append("tracked key file")
    if Path(normalized).name in {"current.json", "SECRETS.md"}:
        issues.append("tracked deployment credential file")
    return issues


def find_content_issues(text: str) -> list[tuple[str, int]]:
    issues: list[tuple[str, int]] = []
    for label, pattern in TEXT_PATTERNS:
        for match in pattern.finditer(text):
            issues.append((label, line_number(text, match.start())))

    for match in IPV4_PATTERN.finditer(text):
        try:
            address = ipaddress.ip_address(match.group())
        except ValueError:
            continue
        if address.is_global:
            issues.append(("public IPv4 address", line_number(text, match.start())))

    for match in URL_PATTERN.finditer(text):
        parsed = urlsplit(match.group().rstrip(".,;:"))
        host = (parsed.hostname or "").lower()
        if host in SAFE_URL_HOSTS or host.endswith(".example.com"):
            continue
        if any(RANDOM_PATH_SEGMENT.fullmatch(part) for part in parsed.path.split("/")):
            issues.append(
                ("URL with credential-like path", line_number(text, match.start()))
            )
    return issues


def tracked_worktree_sources() -> list[tuple[str, str, bytes]]:
    sources: list[tuple[str, str, bytes]] = []
    for raw_path in run_git("ls-files", "-z").split(b"\0"):
        if not raw_path:
            continue
        path = raw_path.decode("utf-8", errors="surrogateescape")
        disk_path = ROOT / path
        if disk_path.is_file():
            sources.append(("worktree", path, disk_path.read_bytes()))
        try:
            index_data = run_git("show", f":{path}")
        except subprocess.CalledProcessError:
            continue
        sources.append(("index", path, index_data))
    return sources


def reachable_history_sources() -> list[tuple[str, str, bytes]]:
    sources: list[tuple[str, str, bytes]] = []
    for raw_line in run_git("rev-list", "--objects", "--all").splitlines():
        fields = raw_line.decode("utf-8", errors="surrogateescape").split(" ", 1)
        object_id = fields[0]
        path = fields[1] if len(fields) == 2 else ""
        if run_git("cat-file", "-t", object_id).strip() != b"blob":
            continue
        sources.append(
            (f"history {object_id[:12]}", path, run_git("cat-file", "-p", object_id))
        )
    return sources


def main() -> int:
    findings: set[tuple[str, str, str, int]] = set()
    sources = tracked_worktree_sources() + reachable_history_sources()
    for source, path, data in sources:
        for issue in find_path_issues(path):
            findings.add((source, path, issue, 0))
        if b"\0" in data:
            continue
        text = data.decode("utf-8", errors="replace")
        for issue, line in find_content_issues(text):
            findings.add((source, path, issue, line))

    if findings:
        for source, path, issue, line in sorted(findings):
            location = f"{path}:{line}" if line else path
            print(f"[FAIL] {source} {location}: possible {issue}", file=sys.stderr)
        return 1
    print("敏感信息扫描通过（工作树、索引与可达 Git 历史）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
