# HiddifyPanel v12.3.3 补丁

这些补丁只针对上游 tag `v12.3.3`、commit `cf2e60de038c7d658d2bf4b2d84c7b433e3c918d` 验证。升级后不得直接重用。

## 唯一支持的应用方式

```bash
sudo bash /opt/vpn-deploy/scripts/apply-patches.sh \
  /opt/vpn-deploy/deployment.yaml
```

应用器会：

- 校验 Hiddify 精确版本；
- 从 Hiddify 配置动态读取节点前缀和订阅名；
- 检查每个目标文件；
- 先运行 `patch --dry-run`；
- 将所有目标备份到 `/opt/hiddify-manager/vpn-agent-backups/<timestamp>/`；
- 任何 patch 失败时停止，并恢复该 patch 涉及的文件；
- 对已确认存在兼容缺口的 v12.3.3 应用 AdminUser 补丁。

不要直接修改已安装的 site-packages；需要调整行为时先更新 patch 并重新跑上游兼容测试。

## 清单

| Patch | 作用 |
|---|---|
| `hiddify-12.3.3-adminuser.patch` | 修复特定 AdminUser AttributeError 导致的面板 500 |
| `friendly-node-names.patch` | 使用配置的通用前缀生成 Reality/Hysteria2 节点名 |
| `clash-cn-rules.patch` | 为 Mihomo/Clash 订阅加入私网与中国 IP 直连规则 |
| `subscription-customization.patch` | 使用配置的订阅名，并建议客户端每 24 小时更新 |

## 回滚

应用日志会显示备份时间戳。先停面板，逐个将该时间戳目录中的文件恢复到相同相对路径，再启动面板并运行健康/订阅验证。不要删除其他时间戳备份。

## 许可证与来源

Patch 包含 HiddifyPanel 源码上下文，按上游 CC BY-NC-SA 4.0 分发，而不是根目录 MIT。每个文件头记录 SPDX 标识、上游仓库、tag 和 commit；完整声明见根目录 `THIRD_PARTY_NOTICES.md`。
