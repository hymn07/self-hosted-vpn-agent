#!/bin/bash
# 在服务器执行。用法: sudo bash scripts/health-check.sh [deployment.yaml]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${1:-/opt/vpn-deploy/deployment.yaml}"
CONFIG_TOOL="$SCRIPT_DIR/deployment_config.py"
HIDDIFY_ROOT="${HIDDIFY_ROOT:-/opt/hiddify-manager}"
PYTHON_BIN="${HIDDIFY_PYTHON:-$HIDDIFY_ROOT/.venv313/bin/python}"
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

"$PYTHON_BIN" "$CONFIG_TOOL" validate "$CONFIG_FILE" >/dev/null || exit 1
SERVER_IP="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" server.ip)"
DOMAIN_MODE="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" domain.mode)"
EXPECT_REALITY="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" protocols.reality)"
EXPECT_HYSTERIA2="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" protocols.hysteria2)"
if [ "$DOMAIN_MODE" = "custom" ]; then
  DOMAIN="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" domain.custom_domain)"
else
  DOMAIN="$SERVER_IP.sslip.io"
fi

echo "=== Hiddify 健康检查 ==="

for service in hiddify-panel hiddify-haproxy hiddify-nginx hiddify-redis; do
  systemctl is-active --quiet "$service" 2>/dev/null
  check "$service" $?
done
if [ "$EXPECT_REALITY" = "true" ]; then
  systemctl is-active --quiet hiddify-xray 2>/dev/null
  check "hiddify-xray" $?
fi
if [ "$EXPECT_HYSTERIA2" = "true" ]; then
  systemctl is-active --quiet hiddify-singbox 2>/dev/null
  check "hiddify-singbox" $?
fi

if ss -tln | grep -qE '(^|[[:space:]])[^[:space:]]*:443[[:space:]]'; then
  check "TCP 443 监听" 0
else
  check "TCP 443 监听" 1
fi
if ss -tln | grep -qE '(^|[[:space:]])[^[:space:]]*:80[[:space:]]'; then
  check "TCP 80 监听" 0
else
  check "TCP 80 监听" 1
fi
if ss -tln | grep -qE '127\.0\.0\.1:9000[[:space:]]'; then
  check "面板仅本地监听 9000" 0
else
  check "面板仅本地监听 9000" 1
fi
if [ "$EXPECT_HYSTERIA2" = "true" ]; then
  if ss -uln | grep -qE '[:.](3595[0-9])[[:space:]]'; then
    check "Hysteria2 UDP 3595x 监听" 0
  else
    check "Hysteria2 UDP 3595x 监听" 1
  fi
fi

local_code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://127.0.0.1:9000/ 2>/dev/null)"
case "$local_code" in
  200|302|404) check "面板本地 HTTP 响应 $local_code" 0 ;;
  *) check "面板本地 HTTP 响应 ${local_code:-无}" 1 ;;
esac

public_code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 8 "https://$DOMAIN/" 2>/dev/null)"
curl_rc=$?
if [ "$curl_rc" -eq 0 ] && [ "$public_code" != "000" ]; then
  check "公网 TLS 证书与 HTTPS 响应 $public_code" 0
else
  check "公网 TLS/HTTPS 验证失败" 1
fi

if [ "$EXPECT_REALITY" = "true" ]; then
  grep -ql "reality" "$HIDDIFY_ROOT"/xray/configs/*reality*.json 2>/dev/null
  check "Xray Reality 配置" $?
fi
if [ "$EXPECT_HYSTERIA2" = "true" ]; then
  grep -ql "hysteria2" "$HIDDIFY_ROOT"/singbox/configs/*hysteria*.json 2>/dev/null
  check "Sing-box Hysteria2 配置" $?
fi

mem_avail="$(free -m | awk '/^Mem:/{print $7}')"
if [ "${mem_avail:-0}" -gt 100 ]; then
  check "可用内存 ${mem_avail}MB" 0
else
  check "可用内存不足" 1
fi
disk_free="$(df -m / | awk 'NR==2{print $4}')"
if [ "${disk_free:-0}" -gt 2000 ]; then
  check "可用磁盘 ${disk_free}MB" 0
else
  check "可用磁盘不足" 1
fi

default_count="$(cd "$HIDDIFY_ROOT/hiddify-panel" && sudo -u hiddify-panel env HOME=/home/hiddify-panel \
  "$PYTHON_BIN" -B -c '
import hiddifypanel
app = hiddifypanel.create_app()
with app.app_context():
    from hiddifypanel.models import User
    print(User.query.filter(User.name == "default").count())
' 2>/dev/null)"
if [ "$default_count" = "0" ]; then
  check "无 default 匿名账户" 0
else
  check "default 账户检查失败（${default_count:-未知}）" 1
fi

echo "=== 结果: $PASS PASS / $FAIL FAIL ==="
if [ "$FAIL" -eq 0 ]; then
  echo "健康检查通过"
else
  echo "存在失败项"
fi
exit "$FAIL"
