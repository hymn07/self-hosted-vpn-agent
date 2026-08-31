#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="${PATCH_TEST_PYTHON:-}"
UPSTREAM_DIR="${1:-}"
TEMP_DIR=""
OWNS_UPSTREAM=false

if [ -z "$PYTHON_BIN" ]; then
  for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1 &&
      "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))'; then
      PYTHON_BIN="$candidate"
      break
    fi
  done
fi
if [ -z "$PYTHON_BIN" ] || ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "补丁兼容测试需要 Python 3.10 或更高版本" >&2
  exit 1
fi
if ! "$PYTHON_BIN" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))'; then
  echo "补丁兼容测试需要 Python 3.10 或更高版本: $PYTHON_BIN" >&2
  exit 1
fi

cleanup() {
  if [ -n "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT

if [ -n "$UPSTREAM_DIR" ]; then
  SOURCE_DIR="$UPSTREAM_DIR"
  TEMP_DIR="$(mktemp -d)"
  UPSTREAM_DIR="$TEMP_DIR/HiddifyPanel"
  cp -R "$SOURCE_DIR" "$UPSTREAM_DIR"
  OWNS_UPSTREAM=true
else
  TEMP_DIR="$(mktemp -d)"
  UPSTREAM_DIR="$TEMP_DIR/HiddifyPanel"
  git clone --quiet --depth 1 --branch v12.3.3 \
    https://github.com/hiddify/HiddifyPanel.git "$UPSTREAM_DIR"
  OWNS_UPSTREAM=true
fi

EXPECTED_SHA="cf2e60de038c7d658d2bf4b2d84c7b433e3c918d"
ACTUAL_SHA="$(git -C "$UPSTREAM_DIR" rev-parse HEAD)"
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "上游 SHA 不匹配: $ACTUAL_SHA" >&2
  exit 1
fi

"$PYTHON_BIN" - "$ROOT/scripts/configure-protocols.py" \
  "$UPSTREAM_DIR/hiddifypanel/models/config_enum.py" <<'PY'
import ast
import re
import sys
from pathlib import Path

script = ast.parse(Path(sys.argv[1]).read_text(encoding="utf-8"))
required = set()
for node in ast.walk(script):
    if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
        if node.value.id == "ConfigEnum":
            required.add(node.attr)
    if isinstance(node, ast.For) and isinstance(node.target, ast.Name):
        if node.target.id == "key" and isinstance(node.iter, (ast.Tuple, ast.List)):
            required.update(
                item.value
                for item in node.iter.elts
                if isinstance(item, ast.Constant) and isinstance(item.value, str)
            )

enum_source = Path(sys.argv[2]).read_text(encoding="utf-8")
available = set(re.findall(r"^    ([a-zA-Z0-9_]+)\s*=", enum_source, re.MULTILINE))
missing = sorted(required - available)
if missing:
    raise SystemExit(f"configure-protocols.py 引用了不存在的 ConfigEnum: {missing}")
PY

for patch_file in "$ROOT"/patches/*.patch; do
  patch -d "$UPSTREAM_DIR" -p1 --dry-run <"$patch_file"
done

if [ "$OWNS_UPSTREAM" = "true" ]; then
  for patch_file in "$ROOT"/patches/*.patch; do
    patch --quiet -d "$UPSTREAM_DIR" -p1 <"$patch_file"
  done
  "$PYTHON_BIN" -m py_compile \
    "$UPSTREAM_DIR/hiddifypanel/models/admin.py" \
    "$UPSTREAM_DIR/hiddifypanel/hutils/proxy/shared.py" \
    "$UPSTREAM_DIR/hiddifypanel/hutils/proxy/clash.py" \
    "$UPSTREAM_DIR/hiddifypanel/panel/user/user.py"
fi

echo "全部 patch 可应用到 HiddifyPanel v12.3.3"
