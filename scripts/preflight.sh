#!/bin/bash
# Agent 本机前置检查。用法: bash scripts/preflight.sh [.local/deployment.yaml]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/../.local/deployment.yaml}"
CONFIG_TOOL="$SCRIPT_DIR/deployment_config.py"
PYTHON_BIN="${LOCAL_PYTHON:-python3}"
PASS=0
FAIL=0

check() {
  if [ "$2" -eq 0 ]; then
    echo "[PASS] $1"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $1"
    FAIL=$((FAIL + 1))
  fi
}

"$PYTHON_BIN" "$CONFIG_TOOL" validate "$CONFIG_FILE" --runtime || exit 1
PEM="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" server.ssh_key_path --runtime)"
IP="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" server.ip --runtime)"
SSH_USER="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" server.ssh_user --runtime)"
DOMAIN_MODE="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" domain.mode --runtime)"
KNOWN_HOSTS_FILE="$(dirname "$CONFIG_FILE")/known_hosts"
mkdir -p "$(dirname "$KNOWN_HOSTS_FILE")"
touch "$KNOWN_HOSTS_FILE"
chmod 600 "$KNOWN_HOSTS_FILE"

ssh_opts=(
  -i "$PEM"
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
  -o "UserKnownHostsFile=$KNOWN_HOSTS_FILE"
)

echo "=== 部署前置检查 ==="

if [ "$DOMAIN_MODE" = "custom" ]; then
  CUSTOM_DOMAIN="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" domain.custom_domain --runtime)"
  if "$PYTHON_BIN" - "$CUSTOM_DOMAIN" "$IP" <<'PY' >/dev/null 2>&1
import socket
import sys

resolved = {item[4][0] for item in socket.getaddrinfo(sys.argv[1], 443, type=socket.SOCK_STREAM)}
raise SystemExit(0 if sys.argv[2] in resolved else 1)
PY
  then
    check "自有域名已解析到 Static IP" 0
  else
    check "自有域名尚未解析到 Static IP" 1
  fi
fi

key_mode="$(stat -f '%Lp' "$PEM" 2>/dev/null || stat -c '%a' "$PEM" 2>/dev/null || true)"
case "$key_mode" in
  400|600) check "SSH 私钥权限 $key_mode" 0 ;;
  *) check "SSH 私钥权限应为 400 或 600（当前 ${key_mode:-未知}）" 1 ;;
esac

if nc -z -w 5 "$IP" 22 >/dev/null 2>&1; then
  check "TCP 22 可达" 0
else
  check "TCP 22 不可达（检查实例状态和 Lightsail 防火墙）" 1
fi

for port in 80 443; do
  result="$(LC_ALL=C nc -zv -w 5 "$IP" "$port" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    check "TCP $port 可达" 0
  elif echo "$result" | grep -qi "refused"; then
    check "TCP $port 已放行但尚无服务（正常）" 0
  else
    check "TCP $port 无响应（检查 Lightsail 防火墙）" 1
  fi
done

if ssh "${ssh_opts[@]}" "$SSH_USER@$IP" 'sudo -n true && echo ok' 2>/dev/null | grep -q '^ok$'; then
  check "SSH 登录与免密 sudo" 0
else
  check "SSH 登录失败（检查用户、私钥和 known_hosts）" 1
fi

spec="$(ssh "${ssh_opts[@]}" "$SSH_USER@$IP" '
  mem=$(free -m | awk "/^Mem:/{print \$2}")
  disk=$(df -m / | awk "NR==2{print \$4}")
  os=$(sed -n "s/^PRETTY_NAME=//p" /etc/os-release | tr -d "\"")
  printf "%s\t%s\t%s\n" "$mem" "$disk" "$os"
' 2>/dev/null)"
if [ -z "$spec" ]; then
  check "服务器规格读取" 1
else
  IFS=$'\t' read -r mem disk os <<< "$spec"
  case "$os" in
    *"Ubuntu 22.04"*) check "系统: $os" 0 ;;
    *) check "系统: $os（当前只验证 Ubuntu 22.04）" 1 ;;
  esac
  if [ "${mem:-0}" -ge 900 ]; then
    check "内存 ${mem}MB" 0
  else
    check "内存不足 1GB" 1
  fi
  if [ "${disk:-0}" -ge 10000 ]; then
    check "可用磁盘 ${disk}MB" 0
  else
    check "可用磁盘不足 10GB" 1
  fi
fi

echo "=== 结果: $PASS PASS / $FAIL FAIL ==="
if [ "$FAIL" -eq 0 ]; then
  echo "前置检查通过"
else
  echo "存在失败项，部署暂停"
fi
exit "$FAIL"
