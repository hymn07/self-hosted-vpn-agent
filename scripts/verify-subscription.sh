#!/bin/bash
# 在 Hiddify 服务器上验证 deployment.yaml 中声明的每一个账户。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${1:-/opt/vpn-deploy/deployment.yaml}"
HIDDIFY_ROOT="${HIDDIFY_ROOT:-/opt/hiddify-manager}"
PYTHON_BIN="${HIDDIFY_PYTHON:-$HIDDIFY_ROOT/.venv313/bin/python}"
CONFIG_TOOL="$SCRIPT_DIR/deployment_config.py"
PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  echo "[PASS] $*"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "[FAIL] $*" >&2
}

fatal() {
  echo "[FAIL] $*" >&2
  exit 1
}

[ -x "$PYTHON_BIN" ] || fatal "找不到 Hiddify Python: $PYTHON_BIN"
[ -f "$CONFIG_FILE" ] || fatal "找不到部署配置: $CONFIG_FILE"
[ -f "$CONFIG_TOOL" ] || fatal "找不到配置解析器: $CONFIG_TOOL"
"$PYTHON_BIN" "$CONFIG_TOOL" validate "$CONFIG_FILE" >/dev/null || exit 1

SERVER_IP="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" server.ip)"
DOMAIN_MODE="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" domain.mode)"
CUSTOM_DOMAIN="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" domain.custom_domain)"
EXPECT_REALITY="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" protocols.reality)"
EXPECT_HYSTERIA2="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" protocols.hysteria2)"
if [ "$DOMAIN_MODE" = "custom" ]; then
  DOMAIN="$CUSTOM_DOMAIN"
else
  DOMAIN="$SERVER_IP.sslip.io"
fi
[ -n "$SERVER_IP" ] || fatal "deployment.yaml 中 server.ip 不能为空"

WORK_DIR="$(mktemp -d)" || fatal "无法创建临时目录"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# 输出配置要求的账户；缺失账户会使脚本立即失败。字段以 TAB 分隔，配置校验器已禁止 TAB。
if ! (cd "$HIDDIFY_ROOT/hiddify-panel" && \
  "$PYTHON_BIN" - "$CONFIG_FILE" "$SCRIPT_DIR") >"$WORK_DIR/users.tsv" <<'PY'
import sys

sys.path.insert(0, sys.argv[2])
from deployment_config import load_config, resolve_users

cfg = load_config(sys.argv[1])
import hiddifypanel

app = hiddifypanel.create_app()
with app.app_context():
    from hiddifypanel.models import User

    for spec in resolve_users(cfg):
        user = User.query.filter(User.name == spec["name"]).first()
        if not user:
            raise SystemExit(f"配置账户不存在于面板: {spec['name']}")
        print(f"{user.uuid}\t{spec['name']}")
PY
then
  fatal "无法读取配置账户"
fi

CLIENT_PATH="$(cd "$HIDDIFY_ROOT/hiddify-panel" && "$PYTHON_BIN" - <<'PY'
import hiddifypanel

app = hiddifypanel.create_app()
with app.app_context():
    from hiddifypanel.models import ConfigEnum, hconfig
    print(str(hconfig(ConfigEnum.proxy_path_client)).strip("/"))
PY
)" || fatal "无法读取 Hiddify 客户端路径"
[ -n "$CLIENT_PATH" ] || fatal "Hiddify 客户端路径为空"

while IFS=$'\t' read -r user_uuid user_name; do
  [ -n "$user_uuid" ] || continue
  clash_url="https://$DOMAIN/$CLIENT_PATH/$user_uuid/clashmeta/"
  auto_url="https://$DOMAIN/$CLIENT_PATH/$user_uuid/auto/"
  clash_file="$WORK_DIR/$user_uuid.clash"
  auto_file="$WORK_DIR/$user_uuid.auto"
  header_file="$WORK_DIR/$user_uuid.headers"

  if curl --fail --silent --show-error --location \
    --connect-timeout 10 --max-time 30 --output "$clash_file" "$clash_url"; then
    pass "$user_name: Clash/Mihomo 订阅可下载（TLS 已验证）"
  else
    fail "$user_name: Clash/Mihomo 订阅下载失败"
    continue
  fi

  if "$PYTHON_BIN" - "$clash_file" <<'PY'
import sys

import yaml

with open(sys.argv[1], encoding="utf-8") as stream:
    config = yaml.safe_load(stream)
if not isinstance(config, dict):
    raise SystemExit("Clash 配置根节点不是 mapping")
if not isinstance(config.get("proxies"), list) or not config["proxies"]:
    raise SystemExit("Clash 配置缺少非空 proxies 列表")
if not isinstance(config.get("rules"), list) or not config["rules"]:
    raise SystemExit("Clash 配置缺少非空 rules 列表")
PY
  then
    pass "$user_name: Clash/Mihomo YAML 结构有效"
  else
    fail "$user_name: Clash/Mihomo YAML 结构无效"
  fi

  if curl --fail --silent --show-error --location \
    --connect-timeout 10 --max-time 30 --dump-header "$header_file" \
    --output "$auto_file" "$auto_url"; then
    pass "$user_name: 通用订阅可下载（TLS 已验证）"
  else
    fail "$user_name: 通用订阅下载失败"
    continue
  fi

  if grep -qi '^subscription-userinfo:' "$header_file"; then
    pass "$user_name: 流量信息响应头存在"
  else
    fail "$user_name: 缺少 subscription-userinfo 响应头"
  fi

  if grep -q 'GEOIP,CN,DIRECT' "$clash_file"; then
    pass "$user_name: 国内流量直连规则存在"
  else
    fail "$user_name: 缺少 GEOIP,CN,DIRECT 规则"
  fi

  if [ "$EXPECT_REALITY" = "true" ]; then
    if grep -Eqi 'reality|reality-opts|reality_opts' "$clash_file"; then
      pass "$user_name: Reality 节点存在"
    else
      fail "$user_name: 未找到 Reality 节点"
    fi
  fi

  if [ "$EXPECT_HYSTERIA2" = "true" ]; then
    if grep -Eqi 'hysteria2|hysteria-?2|hy2' "$clash_file"; then
      pass "$user_name: Hysteria2 节点存在"
    else
      fail "$user_name: 未找到 Hysteria2 节点"
    fi
  fi
done < "$WORK_DIR/users.tsv"

echo
echo "订阅验证结果: $PASS PASS / $FAIL FAIL"
[ "$FAIL" -eq 0 ]
