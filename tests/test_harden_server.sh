#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"

cat >"$FAKE_BIN/id" <<'SH'
#!/bin/bash
if [ "${1:-}" = "-u" ]; then
  echo 0
else
  /usr/bin/id "$@"
fi
SH

cat >"$FAKE_BIN/fallocate" <<'SH'
#!/bin/bash
: >"${@: -1}"
SH

cat >"$FAKE_BIN/stat" <<'SH'
#!/bin/bash
if [ "${1:-}" = "-c" ]; then
  echo 2147483648
else
  /usr/bin/stat "$@"
fi
SH

cat >"$FAKE_BIN/mkswap" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$FAKE_BIN/swapon" <<'SH'
#!/bin/bash
if [[ "${1:-}" == --show=* ]]; then
  if [ -f "$TEST_SWAPON_STATE" ]; then
    echo "$VPN_SWAP_FILE"
  fi
else
  touch "$TEST_SWAPON_STATE"
fi
SH

cat >"$FAKE_BIN/systemctl" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$FAKE_BIN/apt-get" <<'SH'
#!/bin/bash
touch "$TEST_APT_MARKER"
SH

cat >"$FAKE_BIN/dpkg-reconfigure" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$FAKE_BIN"/*

CONFIG_FILE="$TEST_DIR/deployment.yaml"
cp "$ROOT/config/deployment.example.yaml" "$CONFIG_FILE"
python3 - "$CONFIG_FILE" <<'PY'
import sys

import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as stream:
    config = yaml.safe_load(stream)
config["security"]["disable_password_ssh"] = False
config["security"]["enable_auto_updates"] = False
with open(path, "w", encoding="utf-8") as stream:
    yaml.safe_dump(config, stream, allow_unicode=True, sort_keys=False)
PY

export PATH="$FAKE_BIN:$PATH"
export HIDDIFY_PYTHON="$(command -v python3)"
export VPN_SWAP_FILE="$TEST_DIR/swapfile"
export VPN_FSTAB_FILE="$TEST_DIR/fstab"
export VPN_APT_POLICY_FILE="$TEST_DIR/apt-policy"
export TEST_SWAPON_STATE="$TEST_DIR/swapon-state"
export TEST_APT_MARKER="$TEST_DIR/apt-ran"
touch "$VPN_FSTAB_FILE"

bash "$ROOT/scripts/harden-server.sh" "$CONFIG_FILE" >/dev/null
bash "$ROOT/scripts/harden-server.sh" "$CONFIG_FILE" >/dev/null

[ -f "$VPN_SWAP_FILE" ]
[ "$(grep -Fxc "$VPN_SWAP_FILE none swap sw 0 0" "$VPN_FSTAB_FILE")" -eq 1 ]
grep -Fq 'APT::Periodic::Enable "0";' "$VPN_APT_POLICY_FILE"
[ ! -e "$TEST_APT_MARKER" ]

python3 - "$CONFIG_FILE" <<'PY'
import sys

import yaml

path = sys.argv[1]
with open(path, encoding="utf-8") as stream:
    config = yaml.safe_load(stream)
config["security"]["enable_auto_updates"] = True
with open(path, "w", encoding="utf-8") as stream:
    yaml.safe_dump(config, stream, allow_unicode=True, sort_keys=False)
PY

bash "$ROOT/scripts/harden-server.sh" "$CONFIG_FILE" >/dev/null
[ ! -e "$VPN_APT_POLICY_FILE" ]
[ -e "$TEST_APT_MARKER" ]

echo "服务器资源加固沙盒测试通过"
