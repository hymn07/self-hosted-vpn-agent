# Agent Instructions

> 目标：在 AWS Lightsail 上为用户部署一套自建 Hiddify VPN，最终交付管理后台、每个账户的订阅链接和一份针对本次部署生成的使用说明。
> 体验：用户只需说 “Read AGENTS.md and deploy this for me.”，确认一次建议方案，再完成少量 AWS 控制台操作。

## 1. 启动顺序

1. 完整阅读 `docs/ARCHITECTURE.md` 和 `docs/DEPLOYMENT_GUIDE.md`。
2. 复制 `config/deployment.example.yaml` 为 gitignored 的 `.local/deployment.yaml`。
3. 运行 `python3 scripts/deployment_config.py summary .local/deployment.yaml`。
4. 把下列默认方案作为**一个问题**发给用户，不逐项追问：
   - 区域：Oregon（`us-west-2`）
   - 套餐：1GB 内存、控制台显示约 2TB 月流量的档位（模板参考 $7/月）
   - 账户：3 个（`user1`、`user2`、`user3`），每个 500GB/月
   - 有效期：3650 天；月度重置
   - 协议：Reality + Hysteria2
   - 域名：免费 sslip.io
   - 节点前缀：US；订阅名：Private VPN
   - 资源保护：2GB swap
5. 告诉用户：“回复‘按默认’即可；要修改时请一次性列出修改项。默认值只是建议，不是限制。”
6. 用户确认后只编辑 `.local/deployment.yaml`，重新运行 `validate` 和 `summary`，把摘要回显给用户。之后所有脚本、验证和交付物都读取这一个文件；禁止在命令或文档中另写一套参数。

没有用户明确修改时，不再询问账户数、配额、有效期、协议、域名或命名。只有控制台信息无法预知时才在对应步骤确认。

## 2. 最少必需输入

用户确认默认/自定义方案后，Agent 逐步引导用户创建资源。最终只需用户提供：

- AWS 下载到本机的 SSH `.pem` 路径；
- 已绑定实例的 Static IP；
- 若选自有域名：域名及已完成的 DNS 解析；
- 首次打开面板时，由用户本人设置管理员密码。

区域、套餐价格和流量包必须以创建时 AWS 控制台显示为准，并同步回 `.local/deployment.yaml`。不要索取：

- AWS 账号密码、MFA 验证码或银行卡信息；
- 永久 Access Key；
- 私钥内容（只接收本机路径）。

## 3. 工作流

```text
confirm      -> 默认建议一次确认，生成唯一配置
aws          -> 按操作组指导用户创建实例、Static IP、防火墙
preflight    -> 配置、SSH、系统规格和端口检查
stage        -> 上传脚本、补丁和已确认配置
install      -> 安装固定 Hiddify v12.3.3
configure    -> 协议、账户、补丁、apply_configs/apply_users
harden       -> SSH 密钥认证、swap 与系统安全更新
validate     -> 健康检查和每账户订阅检查全部 PASS
deliver      -> 生成并下载 .local/ 部署资料
```

严格按 `docs/DEPLOYMENT_GUIDE.md` 执行。可由脚本完成的动作不要临场拼接替代命令：

- `scripts/preflight.sh`
- `scripts/configure-protocols.py`
- `scripts/configure-users.py`
- `scripts/apply-patches.sh`
- `scripts/harden-server.sh`
- `scripts/diagnose-resources.sh`
- `scripts/health-check.sh`
- `scripts/verify-subscription.sh`
- `scripts/generate-deliverables.py`

## 4. 执行与安全规则

- 标注 `【用户操作】` 的 AWS 控制台步骤按完整操作分组。创建实例时一次给出从区域、镜像、套餐到创建完成的全部步骤，用户完成这一组后，再进入绑定 Static IP，随后进入防火墙配置；不要在每次点击后要求确认。只有界面与文档不一致、出现错误，或即将产生额外费用和执行不可逆操作时才中途暂停确认。
- 任何收费资源在创建前说明固定费用、流量超额风险，并让用户确认控制台显示值。
- 不创建 NAT Gateway、Load Balancer、RDS、CloudFront 或其他未在配置中声明的收费资源。
- 不把真实 IP、私钥路径、UUID、admin path、API key、订阅 URL 写入 tracked 文件；只写 `.local/`。
- 私钥不上传到服务器。`.local/deployment.yaml` 上传副本前必须移除或清空 `server.ssh_key_path`。
- Patch 仅用于精确版本 v12.3.3；先 dry-run、再逐文件备份；任何失败立即停止。
- 重跑脚本必须幂等。删除 Static IP、删除非 default 账户、升级或回滚等破坏性动作必须再次得到确认。
- 内存不足时先运行只读资源诊断；不得只凭一次可用内存读数自动执行 `drop_caches` 或重启 Hiddify 服务。
- 最终验证禁止用 `curl -k` 掩盖证书问题；诊断时若临时跳过 TLS，必须明确标为诊断，不得据此判定通过。
- 部署状态和秘密仅保存在 `.local/`，权限尽量为 0600。

## 5. 故障处理

先诊断，再对照 `docs/TROUBLESHOOTING.md`：

| 症状 | 路由 |
|---|---|
| 安装器 `cli_progress` 高 CPU 卡住 | 问题 2；确认进程后终止并用 `--no-gui --no-log` 恢复 |
| 面板 500 / AdminUser AttributeError | 核对 v12.3.3 补丁是否已应用及面板日志 |
| 版本文件与 `hiddifypanel` 包版本不一致 | 立即停止 patch；保留安装日志并按 TROUBLESHOOTING 版本不一致问题诊断 |
| 面板、订阅和全部节点同时变慢或超时 | 先运行只读资源诊断，检查内存、swap、I/O wait、服务重启和系统更新活动，再决定恢复动作 |
| 实例 Running 但所有端口 timeout | 先排除启动、服务、防火墙和临时网络异常；多网络复测后若仍不可达，再走 Static IP 更换流程 |
| `geoip_cn not found` | 保持 country=UN 并检查 clash-cn-rules patch |
| 国内站点错误走代理 | 检查订阅中的 `GEOIP,CN,DIRECT` |

遇到文档外错误：暂停变更，收集版本、日志和可复现步骤，提出修复并补测试，不静默绕过。

## 6. 交付门槛

全部满足才算完成：

- [ ] `scripts/health-check.sh` 零失败；
- [ ] `scripts/verify-subscription.sh` 对配置中的每个账户零失败；
- [ ] Lightsail 入站规则与已启用协议一致：TCP 22/80/443、UDP 443；仅启用 Hysteria2 时开放 UDP 35952-35953；
- [ ] 无 `default` 匿名账户，每个配置账户有独立 UUID 与正确配额；
- [ ] 公网 HTTPS 证书严格验证通过；
- [ ] 配置要求的 swap 已启用；
- [ ] `.local/SECRETS.md` 含后台和每账户两种订阅；
- [ ] `.local/USER_GUIDE.md` 是针对本次部署生成的使用说明；
- [ ] `.local/DEPLOYMENT_REPORT.md` 记录版本、区域、账户和最终验证结论；
- [ ] tracked 文件及 Git 历史不含真实秘密或个人身份信息。
