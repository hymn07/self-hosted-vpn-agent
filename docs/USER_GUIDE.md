# 使用与管理手册模板

> 部署结束后，以 `.local/USER_GUIDE.md` 为准；它根据服务器真实状态生成并包含实际订阅链接。本文不含任何部署者身份或真实凭据。

## 订阅链接

每个账户会收到两种独立链接：

```text
Mihomo / Clash: https://<DOMAIN>/<CLIENT_PATH>/<USER_UUID>/clashmeta/
Shadowrocket:   https://<DOMAIN>/<CLIENT_PATH>/<USER_UUID>/auto/
```

订阅链接中的 UUID 就是凭据。只发给对应使用者；泄露时应在面板停用旧账户并创建新账户。

## 客户端导入

### Windows / macOS

在 Clash Verge Rev 等 Mihomo 客户端的“订阅/配置”页面粘贴 `clashmeta/` 链接，更新并选中配置，然后启用系统代理。

### Android

在 Mihomo 系客户端新建 URL 配置，粘贴 `clashmeta/` 链接，更新、选中并授予 VPN 权限。

### iPhone / iPad

在 Shadowrocket 新建 Subscribe，粘贴 `auto/` 链接，更新后选择 Reality 或 Hysteria2 节点并连接。

客户端名称和菜单可能随版本变化；从官方发布渠道安装。不要从不可信网站下载修改版客户端。

## 管理后台

部署生成的 `.local/SECRETS.md` 包含：

```text
https://<DOMAIN>/<ADMIN_PATH>/
```

管理后台可查看使用量、停用账户、修改配额和创建新账户。管理路径和密码都不得公开。

通过面板后来新增的账户不会自动写入原有 `.local/deployment.yaml`。若希望 Agent 继续统一维护，应先把新账户与额度加入配置，再重跑账户配置、验证和交付生成。

## 费用监控

每月在 Lightsail 控制台核对：

- 套餐包含的月流量；
- 当前实例数据传输；
- AWS Billing 的实际费用；
- 是否触发预算邮件。

区域配额和超额单价不同。不要按本文中的示例数字估算真实账单，以 AWS 当期控制台与账单为准。

## 常见问题

| 现象 | 处理 |
|---|---|
| Reality 不通 | 切换 Hysteria2；再检查 TCP 443 和服务状态 |
| Hysteria2 不通 | 检查 UDP 35952-35953 规则并用真实客户端测试 |
| `geoip_cn not found` | 删除客户端旧缓存后重新导入；仍失败则重跑订阅验证 |
| 订阅链接失效 | 在面板确认账户启用、未超额、未过期 |
| 面板打不开 | 等待实例重启完成；检查 TLS、hiddify-panel 与 haproxy |
| IP 更换 | sslip.io 链接会变化；重新生成并分发全部交付物 |

## 安全提醒

1. 不公开管理链接或订阅链接。
2. 不把 `.local/` 上传到 Git、网盘共享目录或公开聊天。
3. 不直接修改 Hiddify site-packages；使用仓库脚本并保留备份。
4. 账户异常使用时先停用，确认原因后再删除。
5. 仅向获授权用户提供服务，并遵守所在地法律与云平台政策。
