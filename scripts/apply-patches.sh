#!/bin/bash
# 在 Hiddify 服务器上执行。所有参数从已确认的 deployment.yaml 读取。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$(cd "$SCRIPT_DIR/../patches" && pwd)"
CONFIG_FILE="${1:-/opt/vpn-deploy/deployment.yaml}"
HIDDIFY_ROOT="${HIDDIFY_ROOT:-/opt/hiddify-manager}"
SITE_PACKAGES="${SITE_PACKAGES:-$HIDDIFY_ROOT/.venv313/lib/python3.13/site-packages}"
PYTHON_BIN="${HIDDIFY_PYTHON:-$HIDDIFY_ROOT/.venv313/bin/python}"
CONFIG_TOOL="$SCRIPT_DIR/deployment_config.py"
PASS=0

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

[ -x "$PYTHON_BIN" ] || fail "找不到 Hiddify Python: $PYTHON_BIN"
[ -f "$CONFIG_FILE" ] || fail "找不到部署配置: $CONFIG_FILE"
[ -f "$CONFIG_TOOL" ] || fail "找不到配置解析器: $CONFIG_TOOL"
"$PYTHON_BIN" "$CONFIG_TOOL" validate "$CONFIG_FILE" >/dev/null || exit 1
EXPECTED_VERSION="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" hiddify.version)"

VERSION=""
if [ -f "$HIDDIFY_ROOT/VERSION" ]; then
  IFS= read -r VERSION <"$HIDDIFY_ROOT/VERSION"
fi
[ "$VERSION" = "$EXPECTED_VERSION" ] ||
  fail "Hiddify 版本文件为 ${VERSION:-未知}，期望 $EXPECTED_VERSION"
if ! PACKAGE_VERSION="$("$PYTHON_BIN" - <<'PY'
from importlib.metadata import version

print(version("hiddifypanel"))
PY
)"; then
  fail "无法读取实际安装的 hiddifypanel Python 包版本"
fi
[ "$PACKAGE_VERSION" = "$EXPECTED_VERSION" ] ||
  fail "实际 hiddifypanel Python 包版本为 $PACKAGE_VERSION，期望 $EXPECTED_VERSION；停止应用补丁"
echo "Hiddify 版本文件与 Python 包一致: $EXPECTED_VERSION"

WORK_DIR="$(mktemp -d)" || fail "无法创建临时目录"
BACKUP_DIR="$HIDDIFY_ROOT/vpn-agent-backups/$(date +%Y%m%d-%H%M%S)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

rollback_all() {
  local backup_file relative_file
  [ -d "$BACKUP_DIR" ] || return 0
  while IFS= read -r -d '' backup_file; do
    relative_file="${backup_file#"$BACKUP_DIR/"}"
    cp -p "$backup_file" "$SITE_PACKAGES/$relative_file" || return 1
  done < <(find "$BACKUP_DIR" -type f -print0)
}

need_patch() {
  local relative_file="$1" marker="$2"
  ! grep -q "$marker" "$SITE_PACKAGES/$relative_file" 2>/dev/null
}

apply_one() {
  local patch_name="$1" patch_file="$PATCH_DIR/$1"
  local targets_file="$WORK_DIR/$1.targets"
  local relative_file backup_file
  echo "--- 应用 $patch_name ---"
  [ -f "$patch_file" ] || fail "缺少 patch: $patch_file"

  sed -n 's|^--- a/\([^[:space:]]*\).*|\1|p' "$patch_file" > "$targets_file"
  [ -s "$targets_file" ] || fail "$patch_name 没有目标文件"
  while IFS= read -r relative_file; do
    [ -f "$SITE_PACKAGES/$relative_file" ] || fail "$patch_name 目标不存在: $relative_file"
  done < "$targets_file"

  if ! (cd "$SITE_PACKAGES" && patch -p1 --dry-run < "$patch_file") >"$WORK_DIR/dry-run.log" 2>&1; then
    tail -10 "$WORK_DIR/dry-run.log" >&2
    rollback_all || true
    fail "$patch_name dry-run 失败；停止，不继续应用其他补丁"
  fi

  while IFS= read -r relative_file; do
    backup_file="$BACKUP_DIR/$relative_file"
    mkdir -p "$(dirname "$backup_file")" || fail "无法创建备份目录"
    cp -p "$SITE_PACKAGES/$relative_file" "$backup_file" || fail "备份失败: $relative_file"
  done < "$targets_file"

  if ! (cd "$SITE_PACKAGES" && patch -p1 < "$patch_file") >"$WORK_DIR/apply.log" 2>&1; then
    tail -10 "$WORK_DIR/apply.log" >&2
    rollback_all || true
    fail "$patch_name 应用失败，已尝试恢复本次运行的全部补丁"
  fi
  PASS=$((PASS + 1))
  echo "[PASS] $patch_name"
}

if need_patch "hiddifypanel/models/admin.py" "兼容 User 接口"; then
  apply_one "hiddify-12.3.3-adminuser.patch"
else
  echo "[SKIP] AdminUser 补丁已存在"
fi

if need_patch "hiddifypanel/hutils/proxy/shared.py" "自定义节点名"; then
  apply_one "friendly-node-names.patch"
else
  echo "[SKIP] 节点命名补丁已存在"
fi

if need_patch "hiddifypanel/panel/user/templates/clash_config.yml" "国内直连规则"; then
  apply_one "clash-cn-rules.patch"
else
  echo "[SKIP] 国内直连补丁已存在"
fi

if need_patch "hiddifypanel/panel/user/user.py" "自定义订阅名"; then
  apply_one "subscription-customization.patch"
else
  echo "[SKIP] 订阅自定义补丁已存在"
fi

if [ "$PASS" -gt 0 ]; then
  if ! systemctl restart hiddify-panel; then
    rollback_all || true
    systemctl restart hiddify-panel || true
    fail "hiddify-panel 重启失败，已尝试恢复本次运行的全部补丁"
  fi
  sleep 4
fi
echo "Patches 就绪: $PASS applied"
