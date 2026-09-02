#!/bin/bash
# 在 Hiddify 服务器上执行只读资源诊断。不会修改配置、重启服务或安装软件。
set -uo pipefail

SINCE="${1:-24 hours ago}"

section() {
  echo
  echo "=== $* ==="
}

section "失败的 systemd 单元"
systemctl --failed --no-pager || true

section "Hiddify 相关服务状态"
for service in \
  hiddify-panel hiddify-haproxy hiddify-nginx hiddify-redis \
  hiddify-xray hiddify-singbox; do
  systemctl show "$service" --no-pager \
    --property=Id,LoadState,ActiveState,SubState,Result,NRestarts,ExecMainStatus \
    2>/dev/null || true
done

section "监听端口"
ss -lntup || true

section "相关进程"
ps axo pid,stat,%cpu,%mem,rss,etimes,command --sort=-rss |
  grep -Ei 'PID|hiddify|xray|sing-box|singbox|hysteria|haproxy|nginx|redis|maria|celery|unattended|apt' |
  grep -v grep || true

section "运行时间与最近重启"
uptime || true
last reboot | head -5 || true

section "内存与 swap"
free -m || true
swapon --show || true

section "CPU、阻塞进程与 I/O 等待（3 秒采样）"
vmstat 1 3 || true

section "磁盘空间"
df -h / || true

section "内核内存/OOM线索（$SINCE）"
journalctl -k --since "$SINCE" --no-pager --lines=200 2>/dev/null |
  grep -Ei 'out of memory|oom|killed process|memory pressure|blocked for more than|I/O error' || true

section "Hiddify 服务异常线索（$SINCE）"
for service in \
  hiddify-panel hiddify-haproxy hiddify-nginx hiddify-xray hiddify-singbox; do
  echo "--- $service ---"
  journalctl -u "$service" --since "$SINCE" --no-pager --lines=200 2>/dev/null |
    grep -Ei 'failed|core-dump|abrt|malloc|killed|out of memory|timeout|reset|broken pipe|bind|certificate' || true
done

section "自动安全更新活动（$SINCE）"
journalctl -u unattended-upgrades -u apt-daily.service -u apt-daily-upgrade.service \
  --since "$SINCE" --no-pager --lines=200 2>/dev/null || true

section "root 定时任务"
crontab -u root -l 2>/dev/null || echo "未配置 root crontab"

echo
echo "只读诊断完成；请结合发生时间比较资源、服务和订阅响应，不要仅凭单项阈值自动重启服务。"
