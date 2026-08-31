# 升级与回滚

当前自动化只支持 HiddifyPanel v12.3.3。升级会覆盖补丁，并可能改变数据库 schema、模型 API、路径和订阅格式。因此，“升级到最新”不是本仓库已支持的日常操作。

## 升级前门槛

只有在以下条件满足后才升级：

1. 用户明确批准维护窗口和中断风险；
2. 已阅读目标版本官方 release notes；
3. 在隔离测试实例上运行补丁 dry-run、配置脚本、健康检查和每账户订阅检查；
4. 为新版本更新 `hiddify.version` 支持列表、补丁来源 SHA 和 CI；
5. 已取得 Hiddify 官方备份，并验证备份文件非空、可读取；
6. 已记录当前版本和严格 TLS 下的订阅基线。

示例检查：

```bash
cat /opt/hiddify-manager/VERSION
sudo systemctl is-active hiddify-panel hiddify-xray hiddify-singbox hiddify-haproxy
curl --fail --show-error --location \
  https://<DOMAIN>/<CLIENT_PATH>/<UUID>/clashmeta/ \
  --output /tmp/subscription-before.yaml
```

不要用在线复制整个运行目录的方式冒充可靠备份；数据库和服务可能处于不一致状态。优先使用目标版本官方支持的备份/恢复功能。

## 升级后

1. 确认版本正是测试过的目标版本；
2. 检查数据库迁移与服务日志；
3. 不要把 v12.3.3 patch 直接套到新版本；
4. 运行新版本适配后的 configure、apply、health-check 与 verify-subscription；
5. 重新生成交付物，并确认旧 UUID 与配额符合预期。

任何一步失败，停止继续修改并进入已演练的恢复流程。

## 回滚原则

数据库迁移可能让旧程序无法读取新 schema，单纯替换代码目录不等于可回滚。回滚必须同时匹配：

- 程序版本；
- 数据库备份；
- `current.json` 与密钥；
- 证书和域名配置；
- systemd 与代理配置。

先把失败环境移动到带时间戳的隔离路径，保留取证；不要用宽泛通配符删除备份或失败目录。恢复完成后先验证服务和订阅，再由用户确认是否删除旧目录。
