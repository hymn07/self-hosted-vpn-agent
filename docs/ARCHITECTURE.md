# 架构

> 状态：开源部署工具；不是已部署实例。当前兼容基线为 HiddifyPanel v12.3.3 + Ubuntu 22.04。

## 目标

`self-hosted-vpn-agent` 是一套 Agent 可执行的部署 runbook 与确定性脚本。它降低用户需要回答的问题数量，但不把默认值变成限制：

- 一次确认区域、套餐、账户、协议、域名和命名；
- 用户只在 AWS 控制台完成收费与账号权限相关动作；
- Agent 完成远程部署、配置、验证和交付；
- 每个账户有独立 UUID、额度和订阅；
- 真实凭据只落在 gitignored 的 `.local/`。

## 系统边界

```text
用户
 ├─ 确认一次默认/自定义方案
 ├─ AWS 控制台：实例、Static IP、防火墙
 └─ 浏览器：首次设置管理员密码
             |
             v
本机 Agent + self-hosted-vpn-agent
 ├─ .local/deployment.yaml（唯一配置源）
 ├─ preflight / upload / SSH orchestration
 └─ .local/{SECRETS,USER_GUIDE,DEPLOYMENT_REPORT}.md
             |
             v
AWS Lightsail / Ubuntu 22.04
 ├─ HiddifyPanel v12.3.3
 ├─ HAProxy/Nginx：HTTPS、面板、订阅
 ├─ Xray：Reality / TCP 443
 ├─ Sing-box：Hysteria2 / UDP 35952-35953
 └─ 每账户独立 UUID、额度、重置周期
```

Agent 不进入 AWS 账号控制面，不接收账号密码、MFA 或永久 Access Key。AWS 资源本身不由仓库脚本创建。

## 配置数据流

`config/deployment.example.yaml` 只定义建议值与 schema。确认后复制到 `.local/deployment.yaml`：

```text
example -> 用户一次确认 -> .local/deployment.yaml
                              ├─ preflight
                              ├─ configure-domain/protocols/users
                              ├─ patch 参数渲染
                              ├─ health/subscription 验证
                              └─ 本次部署的交付文档
```

所有消费者通过 `scripts/deployment_config.py` 使用相同校验逻辑。服务器副本会清空本机 SSH 私钥路径。配额校验使用：

```text
所有账户额度之和 <= 套餐月流量 × (1 - quota_reserve_ratio)
```

这只是费用安全护栏；用户可选择任何账户数和额度，只需选用匹配的套餐或调整预留比例。

## 网络与安全

建议 Lightsail 入站面：

| 协议 | 端口 | 组件 |
|---|---:|---|
| TCP | 22 | SSH 密钥登录 |
| TCP | 80 | ACME / HTTP |
| TCP | 443 | HTTPS / Reality |
| UDP | 443 | HTTP/3 |
| UDP | 35952-35953 | Hysteria2 |

数据库、Redis 和面板内部端口不得暴露。Hiddify 管理 iptables，因此不叠加 UFW；公网边界由 Lightsail Firewall 控制。最终验证严格校验 TLS，不以 `curl -k` 结果作为交付依据。

## 版本策略

仓库固定 v12.3.3，原因是四个补丁包含上游文件上下文，必须与精确源码匹配。应用器会：

1. 校验 `/opt/hiddify-manager/VERSION`；
2. 节点前缀与订阅名从 Hiddify 配置动态读取；
3. dry-run 全部目标；
4. 备份涉及文件；
5. 应用后重启面板。

升级不是普通配置变更，而是新兼容性工作；见 `docs/UPGRADING.md`。

## 默认方案

默认 Oregon、参考 $7 的 1GB/2TB 档、3 × 500GB/月、Reality + Hysteria2 和 sslip.io，是为了减少首次部署决策，不是产品限制。AWS 区域流量包和超额单价不同且会调整，因此最终成本字段必须来自创建时控制台。

## 已知限制

- sslip.io 是第三方免费服务；可换成自有域名。
- 单机 Lightsail 没有高可用；实例或 IP 故障会中断。
- Hiddify 代码补丁会被升级覆盖。
- AWS Console 仍需用户本人操作，流程是 Agent-guided，不是无人值守云资源创建。
- UDP “开放”不能由 TCP 连通性测试证明，需结合 Lightsail 规则和真实客户端验证。
