# 部署 Runbook

> 本文给执行部署的 Agent 使用。AWS 控制台步骤按“创建实例”“绑定 Static IP”“配置防火墙”等完整操作分组；每组一次给出全部步骤，用户完成后再进入下一组，不在每次点击后停下来确认。其余动作由 Agent 完成。

## Phase 0：一次确认，建立唯一配置

在仓库根目录：

```bash
mkdir -p .local
cp config/deployment.example.yaml .local/deployment.yaml
chmod 600 .local/deployment.yaml
python3 scripts/deployment_config.py validate .local/deployment.yaml
python3 scripts/deployment_config.py summary .local/deployment.yaml
```

把摘要作为一个问题发给用户。用户回复“按默认”时不再追问；若用户修改区域、套餐、用户、额度、有效期、协议、域名或命名，一次写入 `.local/deployment.yaml`，重新校验并回显最终摘要。

默认值是 UX 建议，不是限制。至少保留 1 个账户；校验器会阻止账户配额合计超过“套餐月流量 ×（1 - 预留比例）”。

## Phase 1：AWS 资源

先提醒用户：创建实例会产生月费，流量超出套餐会另外计费；套餐与流量以控制台当时显示值为准。

### 【用户操作 1】创建实例

指导用户打开 AWS Lightsail：

1. 选择已确认区域；
2. Linux/Unix → OS Only → Ubuntu 22.04 LTS；
3. 选择至少 1GB 内存的套餐；
4. 关闭未确认的收费附加项；
5. 创建并下载 SSH Key；
6. 创建实例。

用户完成后，把控制台显示的 `region`、内存、月流量、月费和实例名同步进 `.local/deployment.yaml`。不要沿用模板猜测值。

### 【用户操作 2】绑定 Static IP

Networking → Create static IP → 绑定刚创建的实例。让用户只提供 IP，不提供 AWS 凭据。

### 【用户操作 3】设置入站规则

删除不需要的规则，只保留：

| 协议 | 端口 | 用途 |
|---|---:|---|
| TCP | 22 | SSH |
| TCP | 80 | ACME/HTTP |
| TCP | 443 | HTTPS + Reality |
| UDP | 443 | HTTP/3 |
| UDP | 35952-35953 | Hysteria2 |

若用户关闭 Hysteria2，仍可不开放其 UDP 范围；交付报告应与配置一致。

### 填入运行时信息

把 Static IP 和本机 PEM 绝对路径填入 `.local/deployment.yaml`，然后：

```bash
chmod 400 /absolute/path/to/key.pem
python3 scripts/deployment_config.py validate .local/deployment.yaml --runtime
bash scripts/preflight.sh .local/deployment.yaml
```

失败即暂停。若选择自有域名，先确认 A 记录已解析到 Static IP。

## Phase 2：传输部署包

私钥只留在本机。生成不含私钥路径的服务器配置：

```bash
python3 scripts/deployment_config.py server-copy \
  .local/deployment.yaml .local/deployment.server.yaml
```

从配置读取 IP、用户和 PEM 路径，使用 `.local/known_hosts`，先建目录再上传：

```bash
ssh <SSH_OPTIONS> ubuntu@<IP> 'install -d -m 700 /tmp/self-hosted-vpn-agent'
scp <SSH_OPTIONS> -r scripts patches ubuntu@<IP>:/tmp/self-hosted-vpn-agent/
scp <SSH_OPTIONS> .local/deployment.server.yaml \
  ubuntu@<IP>:/tmp/self-hosted-vpn-agent/deployment.yaml
ssh <SSH_OPTIONS> ubuntu@<IP> \
  'sudo install -d -m 700 /opt/vpn-deploy &&
   sudo cp -R /tmp/self-hosted-vpn-agent/scripts /tmp/self-hosted-vpn-agent/patches /opt/vpn-deploy/ &&
   sudo install -m 600 /tmp/self-hosted-vpn-agent/deployment.yaml /opt/vpn-deploy/deployment.yaml'
```

`<SSH_OPTIONS>` 至少包括 `-i <PEM> -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=.local/known_hosts`。不要使用 `StrictHostKeyChecking=no`。

## Phase 3：安装固定版本

当前补丁只验证 HiddifyPanel v12.3.3。安装 URL 的版本必须带 `v`：

```bash
ssh <SSH_OPTIONS> ubuntu@<IP> \
  "sudo bash -c 'bash <(curl -fsSL https://i.hiddify.com/v12.3.3)'"
```

完成后确认：

```bash
sudo test "$(cat /opt/hiddify-manager/VERSION)" = "12.3.3"
/opt/hiddify-manager/.venv313/bin/python - <<'PY'
from importlib.metadata import version

actual = version("hiddifypanel")
assert actual == "12.3.3", f"hiddifypanel package={actual}, expected=12.3.3"
print(actual)
PY
sudo systemctl is-active hiddify-panel hiddify-haproxy
```

版本文件和实际 Python 包必须同时为 `12.3.3`。若不一致，停止应用补丁并按 `TROUBLESHOOTING.md` 的版本不一致问题诊断，不要把补丁套到其他包版本。

若安装器的 `cli_progress` 高 CPU 且长期不前进，按 `TROUBLESHOOTING.md` 问题 2 诊断；不要盲目 `pkill -f`。

## Phase 4：补丁与配置

所有命令在服务器执行。

### 4.1 应用兼容补丁

```bash
sudo bash /opt/vpn-deploy/scripts/apply-patches.sh \
  /opt/vpn-deploy/deployment.yaml
```

脚本会校验精确版本、渲染已确认的节点/订阅命名、先 dry-run、按时间戳备份，再应用。任一失败立即停止。

### 4.2 域名、协议和账户

```bash
cd /opt/hiddify-manager/hiddify-panel
sudo -u hiddify-panel env HOME=/home/hiddify-panel \
  /opt/hiddify-manager/.venv313/bin/python -B \
  /opt/vpn-deploy/scripts/configure-domain.py /opt/vpn-deploy/deployment.yaml
sudo -u hiddify-panel env HOME=/home/hiddify-panel \
  /opt/hiddify-manager/.venv313/bin/python -B \
  /opt/vpn-deploy/scripts/configure-protocols.py /opt/vpn-deploy/deployment.yaml
sudo -u hiddify-panel env HOME=/home/hiddify-panel \
  /opt/hiddify-manager/.venv313/bin/python -B \
  /opt/vpn-deploy/scripts/configure-users.py /opt/vpn-deploy/deployment.yaml
sudo systemctl restart hiddify-panel

cd /opt/hiddify-manager
sudo env DO_NOT_INSTALL=true bash ./install.sh apply_configs --no-gui --no-log
sudo env DO_NOT_INSTALL=true bash ./install.sh apply_users --no-gui --no-log
```

账户脚本按名称幂等更新，保留已有 UUID；新账户使用随机 UUID；只自动删除名为 `default` 的匿名账户，不删除其他未列出的账户。

自有域名必须在执行前已经解析到服务器。若证书签发失败，不得用 `-k` 当作成功，先修正 DNS/80 端口再重跑 `apply_configs`。

## Phase 5：安全加固

在本机已再次确认密钥 SSH 正常后执行：

```bash
sudo bash /opt/vpn-deploy/scripts/harden-server.sh \
  /opt/vpn-deploy/deployment.yaml
```

此脚本按配置禁用 SSH 密码认证、创建 swap，并配置 Ubuntu 自动安全更新。默认 1GB 实例会先创建 2GB swap，再运行可能消耗额外内存和 I/O 的系统包操作。运行后新开一个 SSH 连接验证，旧会话在验证前保持打开。

`unattended-upgrades` 用于 Ubuntu 系统安全更新。若配置中将 `security.enable_auto_updates` 设为 `false`，Agent 必须提醒用户另行安排系统安全补丁；不要把关闭安全更新描述为零代价优化。

脚本不会安装“低于固定内存阈值就清缓存并重启面板”的看门狗。单次 `MemAvailable` 偏低不足以证明服务故障，自动重启可能制造额外中断。

### 【用户操作 4】设置面板密码

Agent 从 `/opt/hiddify-manager/current.json` 读取 admin path，但不得在 tracked 文件或公共聊天中保存。让用户打开 HTTPS 管理地址并设置唯一强密码。用户只需回复“已完成”，不要把密码发给 Agent。

### 【用户操作 5】可选费用告警

若用户愿意，在 AWS Billing 创建月度预算；建议金额取 `cost_control.budget_usd`。预算只告警，不会自动停止实例。

## Phase 6：严格验证

在服务器运行：

```bash
sudo bash /opt/vpn-deploy/scripts/health-check.sh \
  /opt/vpn-deploy/deployment.yaml
sudo bash /opt/vpn-deploy/scripts/verify-subscription.sh \
  /opt/vpn-deploy/deployment.yaml
```

两者必须零失败，健康检查还会确认配置要求的 swap 已启用。再从 Agent 本机确认 TCP 22/80/443 可达，并让用户确认 Lightsail 规则与配置一致：没有数据库、Redis、9000 等额外端口，且仅在启用 Hysteria2 时开放 UDP 35952-35953。UDP 可达性不能仅靠普通 TCP 扫描推断。

如果面板、订阅和全部协议节点在此前可用后同时变慢或超时，先在服务器运行只读诊断：

```bash
sudo bash /opt/vpn-deploy/scripts/diagnose-resources.sh "24 hours ago"
```

该脚本只读取服务、端口、进程、内存、swap、I/O wait 和近期日志，不会重启服务、停止更新、修改配置或安装软件。结合故障开始时间判断后，再向用户提出恢复动作并单独确认。

## Phase 7：生成并下载交付物

服务器上：

```bash
sudo rm -rf /tmp/vpn-delivery
sudo -u hiddify-panel env HOME=/home/hiddify-panel \
  /opt/hiddify-manager/.venv313/bin/python -B \
  /opt/vpn-deploy/scripts/generate-deliverables.py \
  /opt/vpn-deploy/deployment.yaml /tmp/vpn-delivery --validated
sudo chown -R ubuntu:ubuntu /tmp/vpn-delivery
```

本机：

```bash
scp <SSH_OPTIONS> -r ubuntu@<IP>:/tmp/vpn-delivery/. .local/
chmod 600 .local/SECRETS.md .local/USER_GUIDE.md .local/DEPLOYMENT_REPORT.md
```

Agent 检查三个文件完整后，再安全删除服务器临时交付目录。`--validated` 只能在 Phase 6 两项脚本零失败后使用。最终向用户说明：

- 管理后台在哪里；
- 每个账户的两种订阅链接在哪里；
- 各平台如何导入；
- 如何增删账户、修改额度和查看费用；
- `.local/` 不能上传 Git 或公开分享。

## Phase 8：公网 IP 持续不可达时更换 Static IP

先排除实例尚未启动完成、服务未运行、防火墙或路由错误，以及临时 AWS 网络异常。只有实例保持 Running、服务和规则正确，并且从不同网络测试 22/80/443 等公网端口仍持续全部超时后，才将公网 IP 路由或可达性异常作为高概率判断。

删除 Static IP 会造成中断，必须再次得到用户确认。用户创建并绑定新 IP 后：

1. 更新本机 `.local/deployment.yaml` 的 `server.ip`；
2. 重新生成并上传 server-copy；
3. 重跑 domain → patches（命名包含 IP 时）→ apply_configs → 两项验证；
4. 重新生成所有交付物；
5. 明确告知所有旧 sslip.io 订阅 URL 已变化。
