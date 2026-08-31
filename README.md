# Self-Hosted VPN Agent

[English](README_EN.md) | 简体中文

> 准备一个 AWS 账号，剩下的交给 AI，部署属于你自己的 VPN。

`self-hosted-vpn-agent` 是一套基于 HiddifyPanel、面向 AI Coding Agent 的自托管 VPN 部署工具。

把这个仓库交给 Claude Code、Codex、Cursor Agent 等能够操作本地文件、终端和 SSH 的 Agent。你只需要提供 AWS 环境和必要信息，并完成少量必须本人确认的 AWS 控制台操作，Agent 会帮你完成安装、配置、检查、故障处理和最终交付。

部署完成后，你会得到：

- 一个可以在浏览器中使用的 VPN 管理后台
- 每个用户独立的 Clash / Mihomo / Shadowrocket 订阅链接
- 一份根据本次实际部署结果生成的使用说明

服务器运行在你自己的 AWS 账号中，用户和订阅由你管理，流量不会经过项目维护者的服务器。

## 你需要准备什么？

开始前只需要：

1. 一个可以创建 AWS Lightsail 实例的 AWS 账号
2. 一台已经安装好 AI Coding Agent 的电脑

你可以自行完成下面的 AWS 初始化，也可以直接让 Agent 指导你完成：

- 创建 Lightsail 实例
- 下载 SSH 私钥（`.pem`）
- 创建并绑定 Static IP
- 设置防火墙规则

Agent 会按完整操作分组指导：一次说明完“创建实例”所需的全部步骤，完成后再进入“绑定 Static IP”和“设置防火墙”，不会在每次点击后停下来确认。

完成这些初始化步骤后，把 `.pem` 文件路径和服务器 Static IP 告诉 Agent，后续安装、配置、检查、修复、用户创建、订阅生成、最终验证和交付都由 Agent 完成。

部署完成后，Agent 会给出管理后台地址，你只需要首次打开后台并设置管理员密码。

AWS 登录密码、MFA、银行卡信息和永久 Access Key 始终由你自己保管。

SSH 私钥无需复制到聊天中，Agent 只需要知道本机 `.pem` 文件路径和服务器 Static IP。

## 开始部署

最简单的方法是直接把项目地址发给 Agent：

```text
下载并阅读这个项目的 AGENTS.md，然后帮我部署自己的 VPN：
https://github.com/hymn07/self-hosted-vpn-agent
```

如果 Agent 无法直接下载仓库，使用下面的手动方式。

```bash
git clone https://github.com/hymn07/self-hosted-vpn-agent.git
cd self-hosted-vpn-agent
```

然后告诉 Agent：

```text
阅读这个项目的 AGENTS.md，然后帮我部署自己的 VPN。
```

第一次运行时，Agent 会一次性展示推荐方案。如果不想研究区域、套餐、用户额度和域名，直接回复：

```text
按默认
```

如果需要调整，可以在一条回复中列出全部修改项。推荐值用于减少提问，不是对区域、套餐、用户数量或流量额度的限制。

## Agent 会完成什么？

```text
确认默认或自定义方案
    ↓
完成 Lightsail、Static IP 和防火墙规则初始化
    ↓
检查本地配置、SSH、系统规格和网络端口
    ↓
安装固定兼容版本的 HiddifyPanel
    ↓
配置 Reality、Hysteria2、用户和分流规则
    ↓
检查服务、TLS 和协议状态
    ↓
逐个验证用户订阅
    ↓
生成管理后台地址、订阅链接和使用说明
```

AWS 初始化完成后，后续服务器操作由 Agent 和仓库脚本执行。涉及费用、资源删除、升级或其他高风险操作时，Agent 会先请求确认。

只有管理后台、协议和用户订阅实际验证通过后，部署才算完成。

## 最后你会得到什么？

### 1. 网页管理后台

部署完成后，你会得到一个类似这样的地址：

```text
https://your-domain.example/<admin-path>/
```

打开后台可以：

- 创建、停用和删除用户
- 设置用户流量额度、重置周期和有效期
- 查看使用量
- 获取新的订阅链接

日常管理不需要再操作 Linux。

### 2. 每个用户独立的订阅链接

Mihomo / Clash：

```text
https://your-domain.example/<client-path>/<user-id>/clashmeta/
```

Shadowrocket / 通用订阅：

```text
https://your-domain.example/<client-path>/<user-id>/auto/
```

每个用户拥有独立的身份、流量额度、重置周期、有效期和订阅凭据。停用或删除一个用户不会影响其他用户。

### 3. 针对本次部署生成的使用说明

部署资料会保存在本机的 `.local/` 目录中：

```text
.local/
├── USER_GUIDE.md
├── SECRETS.md
├── DEPLOYMENT_REPORT.md
└── deployment.yaml
```

- `USER_GUIDE.md`：各平台导入订阅、后台管理和常见问题说明
- `SECRETS.md`：需要妥善保管的后台地址和用户订阅链接
- `DEPLOYMENT_REPORT.md`：区域、版本、用户配置和最终检查结果
- `deployment.yaml`：本次部署最终采用的配置

`.local/` 在部署过程中生成并默认被 Git 忽略。真实 IP、SSH 私钥路径、UUID、后台路径、API Key 和订阅 URL 不会写入公开仓库。

## 推荐配置

如果直接回复“按默认”，当前模板采用：

| 项目 | 推荐值 |
|---|---|
| 云服务 | AWS Lightsail |
| 区域 | Oregon（`us-west-2`） |
| 系统 | Ubuntu 22.04 LTS |
| 套餐 | 至少 1GB 内存；模板参考约 2TB 月流量的档位 |
| 面板 | HiddifyPanel v12.3.3 |
| 协议 | Reality + Hysteria2 |
| 域名 | 免费 `sslip.io` |
| 用户 | 3 个（`user1`、`user2`、`user3`） |
| 每用户流量 | 500GB/月 |
| 流量重置 | 每月重置 |
| 有效期 | 3650 天 |
| 客户端 | Clash / Mihomo / Shadowrocket |

这些只是建议值。用户数量、名称、流量、重置方式、有效期、区域、套餐、域名和节点名称都可以修改。

AWS 的套餐价格、区域流量包和超额单价可能变化。创建资源前，Agent 会让你确认 AWS 控制台当时显示的规格、价格和流量，不会把 README 中的数字作为账单承诺。

## 为什么不是一个巨大的“一键脚本”？

安装 HiddifyPanel 本身不是最困难的部分。真实环境中还可能遇到：

- 安装器在无终端环境下卡住
- 管理后台返回 HTTP 500
- Reality 或 Hysteria2 没有正确启用
- UDP 防火墙端口遗漏
- 用户创建成功但订阅不可用
- Clash / Mihomo 分流规则异常
- 更换 Static IP 后域名和订阅失效
- HiddifyPanel 升级覆盖兼容补丁
- SSH、证书或网络状态异常

一段固定的 Shell 脚本很难在所有环境下可靠处理这些情况。因此项目采用：

> **Agent + Runbook + Scripts + Diagnostics**

环境检查、配置验证、服务检查和交付文件生成由脚本完成；遇到异常时，Agent 根据实际版本、日志、服务状态和故障手册判断下一步。遇到文档之外的问题时，Agent 应暂停变更、收集证据并说明情况，而不是盲目重复安装。

## 技术范围与验证状态

当前兼容基线：

- AWS Lightsail
- Ubuntu 22.04 LTS
- HiddifyPanel v12.3.3
- Reality + Hysteria2
- Clash / Mihomo / Shadowrocket 订阅

仓库已经完成配置测试、静态检查和针对 HiddifyPanel v12.3.3 上游源码的补丁兼容验证。新的 Lightsail 环境端到端回归尚未完成，因此这里不宣称所有云端环境都已经完整验证。

部分补丁与该版本源码结构绑定，因此 Agent 不会擅自升级到 `latest`。升级前必须重新检查上游变更、补丁适用性和完整部署流程，详见 [docs/UPGRADING.md](docs/UPGRADING.md)。

当前方案还有以下边界：

- 只支持 AWS Lightsail，其他云服务商尚未适配
- `sslip.io` 是第三方免费服务，也可以改用自有域名
- AWS 资源初始化需要用户在控制台中完成，后续服务器部署由 Agent 执行（为减少权限暴露，不建议将完整 AWS 账号权限交给 Agent）

## 安全与费用

本项目默认遵守以下原则：

- AWS 密码和 MFA 始终由用户本人掌握
- SSH 使用本机 `.pem` 文件，不复制私钥内容，也不把私钥上传到服务器
- 敏感部署信息只保存在被 Git 忽略的 `.local/`
- 每个用户使用独立订阅凭据
- 修改 HiddifyPanel 文件前先备份，版本不匹配时停止应用补丁
- 删除资源、删除非默认用户、升级或回滚前必须再次确认
- 所有关键服务必须实际检查通过后才能交付

实际费用来自用户自己的 AWS Lightsail 实例、超出套餐后的网络流量，以及可选的自定义域名。项目不会创建配置之外的收费资源；最终价格以 AWS 控制台和账单为准。

## 文档

如果只是想部署，从 [AGENTS.md](AGENTS.md) 开始即可。

- [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)：完整部署流程
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：架构、配置数据流和系统边界
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)：故障诊断和已知问题
- [docs/SECURITY.md](docs/SECURITY.md)：部署安全设计
- [docs/UPGRADING.md](docs/UPGRADING.md)：版本升级流程
- [SECURITY.md](SECURITY.md)：安全问题报告方式
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)：第三方代码和许可证说明

## 免责声明

本项目仅用于合法、合规和获得授权的场景。使用者需要自行遵守所在地法律法规、AWS 服务条款以及 HiddifyPanel、客户端软件和其他第三方项目的许可证与服务条款。

云服务费用、网络可用性、IP 可用性和当地法律合规责任由使用者自行承担。

## License

本仓库原创脚本、配置模板和文档采用 MIT License。

`patches/` 包含来自 HiddifyPanel v12.3.3 的上游源码上下文，按 CC BY-NC-SA 4.0 分发，不属于根目录 MIT License 的授权范围。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
