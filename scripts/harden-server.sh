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

if [ "$AUTO_UPDATES" = "true" ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y unattended-upgrades
  dpkg-reconfigure -f noninteractive unattended-upgrades
  systemctl enable --now unattended-upgrades
  systemctl is-active --quiet unattended-upgrades ||
    fail "unattended-upgrades 未启动"
  echo "[PASS] 自动安全更新已启用"
fi
