#!/bin/bash
# 在已确认 SSH 密钥登录正常后执行；根据 deployment.yaml 做幂等安全加固。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${1:-/opt/vpn-deploy/deployment.yaml}"
CONFIG_TOOL="$SCRIPT_DIR/deployment_config.py"
PYTHON_BIN="${HIDDIFY_PYTHON:-/opt/hiddify-manager/.venv313/bin/python}"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

[ "$(id -u)" -eq 0 ] || fail "请用 sudo 运行"
[ -x "$PYTHON_BIN" ] || fail "找不到 Python: $PYTHON_BIN"
"$PYTHON_BIN" "$CONFIG_TOOL" validate "$CONFIG_FILE" >/dev/null

DISABLE_PASSWORD="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" security.disable_password_ssh)"
AUTO_UPDATES="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" security.enable_auto_updates)"
SWAP_SIZE_GB="$("$PYTHON_BIN" "$CONFIG_TOOL" get "$CONFIG_FILE" security.swap_size_gb)"
SWAP_FILE="${VPN_SWAP_FILE:-/swapfile}"
FSTAB_FILE="${VPN_FSTAB_FILE:-/etc/fstab}"
APT_POLICY_FILE="${VPN_APT_POLICY_FILE:-/etc/apt/apt.conf.d/99-self-hosted-vpn-agent-periodic}"

if [ "$DISABLE_PASSWORD" = "true" ]; then
  SSH_DROPIN="/etc/ssh/sshd_config.d/99-self-hosted-vpn-agent.conf"
  SSH_TEMP="$(mktemp)"
  SSH_BACKUP="$(mktemp)"
  HAD_SSH_DROPIN=false
  if [ -f "$SSH_DROPIN" ]; then
    cp -p "$SSH_DROPIN" "$SSH_BACKUP"
    HAD_SSH_DROPIN=true
  fi
  cleanup() {
    rm -f "$SSH_TEMP" "$SSH_BACKUP"
  }
  trap cleanup EXIT
  {
    echo "PubkeyAuthentication yes"
    echo "PasswordAuthentication no"
    echo "KbdInteractiveAuthentication no"
    echo "PermitRootLogin prohibit-password"
  } >"$SSH_TEMP"
  install -m 0644 "$SSH_TEMP" "$SSH_DROPIN"
  if ! sshd -t; then
    if [ "$HAD_SSH_DROPIN" = "true" ]; then
      cp -p "$SSH_BACKUP" "$SSH_DROPIN"
    else
      rm -f "$SSH_DROPIN"
    fi
    fail "sshd 配置校验失败，已恢复原配置"
  fi
  if ! systemctl reload ssh; then
    if [ "$HAD_SSH_DROPIN" = "true" ]; then
      cp -p "$SSH_BACKUP" "$SSH_DROPIN"
    else
      rm -f "$SSH_DROPIN"
    fi
    if sshd -t; then
      systemctl reload ssh || true
    fi
    fail "sshd reload 失败，已尝试恢复原配置"
  fi
  echo "[PASS] SSH 已限制为密钥认证"
fi

if [ "$SWAP_SIZE_GB" -gt 0 ]; then
  REQUIRED_BYTES=$((SWAP_SIZE_GB * 1024 * 1024 * 1024))
  CREATED_SWAP=false
  if [ -e "$SWAP_FILE" ]; then
    [ ! -L "$SWAP_FILE" ] || fail "$SWAP_FILE 是符号链接；不会修改"
    [ -f "$SWAP_FILE" ] || fail "$SWAP_FILE 已存在但不是普通文件"
    ACTUAL_BYTES="$(stat -c '%s' "$SWAP_FILE")"
    [ "$ACTUAL_BYTES" -ge "$REQUIRED_BYTES" ] ||
      fail "$SWAP_FILE 小于配置的 ${SWAP_SIZE_GB}GB；请人工确认后调整"
  else
    if ! fallocate -l "${SWAP_SIZE_GB}G" "$SWAP_FILE"; then
      dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$((SWAP_SIZE_GB * 1024))" status=progress
    fi
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE" >/dev/null
    CREATED_SWAP=true
  fi
  chmod 600 "$SWAP_FILE"
  if ! swapon --show=NAME --noheadings 2>/dev/null | awk '{$1=$1; print}' |
    grep -Fxq "$SWAP_FILE"; then
    if [ "$CREATED_SWAP" != "true" ]; then
      [ "$(blkid -p -s TYPE -o value "$SWAP_FILE" 2>/dev/null)" = "swap" ] ||
        fail "$SWAP_FILE 已存在但不是可识别的 swap；不会覆盖"
    fi
    swapon "$SWAP_FILE"
  fi
  if ! grep -Fqx "$SWAP_FILE none swap sw 0 0" "$FSTAB_FILE"; then
    printf '%s none swap sw 0 0\n' "$SWAP_FILE" >>"$FSTAB_FILE"
  fi
  echo "[PASS] ${SWAP_SIZE_GB}GB swap 已启用并写入 fstab"
else
  echo "[SKIP] 配置未要求创建 swap"
fi

if [ "$AUTO_UPDATES" = "true" ]; then
  rm -f "$APT_POLICY_FILE"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y unattended-upgrades
  dpkg-reconfigure -f noninteractive unattended-upgrades
  systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
  systemctl enable --now unattended-upgrades
  systemctl is-active --quiet unattended-upgrades ||
    fail "unattended-upgrades 未启动"
  echo "[PASS] Ubuntu 自动安全更新已启用"
else
  systemctl disable --now unattended-upgrades 2>/dev/null || true
  systemctl disable --now apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
  printf 'APT::Periodic::Enable "0";\nAPT::Periodic::Update-Package-Lists "0";\nAPT::Periodic::Unattended-Upgrade "0";\n' \
    >"$APT_POLICY_FILE"
  echo "[WARN] Ubuntu 自动安全更新已禁用；必须另行安排系统安全补丁"
fi
