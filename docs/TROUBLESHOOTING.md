# 故障排查手册（Troubleshooting）

> 以下包括实际部署中遇到的问题，以及经核实的版本相关上游问题；未完成本项目回归的上游修复会明确标注。

> Agent 部署遇到问题时查阅；每个问题都有【症状】【根因】【解决】。
> 原则：**先诊断再动手**；修改前备份；失败即停，不猜测。

## 问题 1：Hysteria2 连不上

- 症状：Reality 正常，Hysteria2 节点无法连接
- 根因：Hysteria2 走 **UDP 35952/35953**（不是 443）；Lightsail 防火墙漏开 UDP 端口
- 解决：Lightsail → Networking → IPv4 Firewall → Add rule → Custom UDP → `35952-35953`

## 问题 2：安装/应用配置卡死（cli_progress 无 TTY）

- 症状：`ps aux | grep cli_progress` 存在且 98% CPU 空转；下游进程（jinja.py 等）阻塞在 `pipe_write`；安装永不完成
- 根因：`cli_progress` 在无终端（非 TTY）环境下空转，不消费输出管道 → 管道缓冲满 → 阻塞所有写管道的子进程
- 解决：
  1. 按 PID 杀进程链（**不要用 `pkill -f <字符串>`**——会匹配 SSH 自身命令行导致断连，exit 255；先用 `pgrep -f` 取 PID）
  2. 绕过进度条重跑：
  ```bash
  sudo bash /tmp/hiddify/hiddify_installer.sh release --no-gui --no-log > /tmp/install2.log 2>&1
  ```
  3. 应用配置同理，必须带 `--no-gui --no-log`：
  ```bash
  cd /opt/hiddify-manager && sudo env DO_NOT_INSTALL=true bash ./install.sh apply_configs --no-gui --no-log
  ```
- 说明：安装器有断点续装（lock 机制），已装组件会跳过

## 问题 3：pkill -f 自杀（SSH 断连）

- 症状：`ssh host 'sudo pkill -f "app.py"'` 执行后 exit 255，连接断开
- 根因：pkill -f 匹配完整命令行，SSH 自身的 `bash -c '...'` 包含该字符串
- 解决：先 `pgrep -f <pattern>` 拿 PID 再 `kill -9 <PID>`；或 pkill 用不会出现在自身命令行的模式

## 问题 4：Hiddify v12.3.3 AdminUser bug（面板 500）

- 症状：面板 HTTPS 返回 500；err.log 报 `AttributeError: 'AdminUser' object has no attribute 'remaining_days'`（随后依次 usage_limit_GB / ed25519_private_key / wg_pk 等）
- 根因：AdminUser 缺少 User 模型才有的属性，`get_common_data` 等代码无差别访问
- 解决：应用 `patches/hiddify-12.3.3-adminuser.patch`（或 `scripts/apply-patches.sh`）
- 注意：错误"推进到下一行"= 补丁生效，继续修下一处缺失属性即可

## 问题 5：改错文件（panel/user/user.py vs models/）

- 症状：改了 `panel/user/user.py` 但错误依旧
- 根因：运行代码实际加载 `models/` 下的模型定义；视图文件与模型文件是两个文件
- 解决：AdminUser 补丁目标文件是 `hiddifypanel/models/admin.py`

## 问题 6：面板配置缓存（get_hconfigs）

- 症状：外部进程 `set_hconfig` 改配置后，订阅/apply 仍是旧值（幽灵节点、旧协议）
- 根因：面板进程内存缓存配置（get_hconfigs），外部改数据库不会通知它
- 解决：改配置后必须 `systemctl restart hiddify-panel`；改用户/协议后跑 `apply_users` / `apply_configs`

## 问题 7：Hiddify 升级覆盖补丁

- 症状：升级后之前修好的问题复发
- 根因：site-packages 代码被新版本覆盖
- 解决：升级后重新检测并应用 patches（见 `docs/UPGRADING.md`）

## 问题 8：API 404

- 症状：`/api/v2/admin/users` 等返回 404
- 根因：路由名是单数 `/api/v2/admin/user/`
- 解决：用 `app.url_map` 核对实际路由；用户列表用 `user/`，用户操作带 uuid：`user/<uuid>/`

## 问题 9：订阅 URL 302 重定向

- 症状：用户订阅链接跳转到登录页
- 根因 1：用了 admin proxy_path 而非 client proxy_path（两者不同！`hconfig(ConfigEnum.proxy_path_client)` 才是订阅路径）
- 根因 2：新用户 password 为 NULL（应为空串 `""`）
- 解决：用 `proxy_path_client` 构造订阅 URL；创建用户后设 `password = ""`

## 问题 10：订阅里出现多余"幽灵节点"

- 症状：订阅有 vless-tls/xhttp/grpc/mieru 等未启用协议的节点
- 根因：面板缓存旧配置（见问题 6）或协议开关未关全
- 解决：关闭 `mieru_enable`/`xhttp_enable`/`grpc_enable`/`vless_enable` 等后重启面板 + apply_configs

## 问题 11：新用户订阅 302

- 见问题 9（password 为空串）

## 问题 12：Clash 报 `rule set [geoip_cn] not found`

- 症状：Clash Verge 校验失败
- 根因：Hiddify 模板 bug——country=zh 时 rule-provider 名生成 `geoip_zh`，但 rules 引用 `geoip_cn`，不匹配
- 解决：不要用 country=zh 方案；保持 country=UN + 应用 `clash-cn-rules.patch`（用客户端内置 GEOIP,CN，无外部依赖）

## 问题 13：订阅里 trojan 假节点

- 症状：订阅有一个 `trojan://1@时间戳?sni=fake_ip_for_sub_link` 节点
- 解释：**不是代理节点**，是 Hiddify 的"流量显示"节点（客户端显示剩余流量），由 `show_usage_in_sublink` 控制
- 处理：保留即可

## 问题 14：国内网站走代理打不开

- 症状：百度/bilibili 等国内网站打不开（错误走代理或代理路径不可达）
- 根因：订阅 rules 缺国内直连规则
- 解决：应用 `clash-cn-rules.patch`（私网/cn/GEOIP,CN 直连规则写入订阅模板）

## 问题 15：Hiddify 模板 geoip bug

- 见问题 12（同一个 bug）

## 问题 16：公网 IP 在特定网络下持续不可达

- 症状：客户端突然全部超时；本机 ping/22/80/443 全部 timeout；Lightsail 控制台实例 **Running**、防火墙正常
- 判断：先排除实例尚未启动完成、服务异常、防火墙或路由错误，以及临时 AWS 网络问题。只有服务和规则正常，并且从不同网络测试 22/80/443 等端口仍持续全部超时后，才将公网 IP 路由或可达性异常作为高概率判断
- 解决：完整流程见 `DEPLOYMENT_GUIDE.md` Phase 8（经用户确认后换 Static IP → 重配域名/证书 → 重新验证与交付）
- 换 IP 后：**所有订阅链接的域名段变化**（IP.sslip.io），必须重新把新链接发给所有用户

## 问题 17：订阅名带 `.yaml` 或引号

- 症状：客户端订阅名显示 `Private VPN.yaml` 或额外引号
- 根因：Content-Disposition 的 filename 带扩展名/引号，Clash Verge 不剥除
- 解决：filename 使用配置中的通用订阅名，不添加扩展名或额外引号

## 问题 18：个别客户端订阅名仍不对

- 症状：某客户端不显示自定义订阅名
- 根因：旧版客户端不支持 Content-Disposition 命名
- 解决：客户端内手动重命名（一次性）

## 问题 19：面板外改配置后订阅不更新

- 见问题 6（重启面板 + apply）

## 问题 20：新 IP 创建后短暂不可达

- 症状：刚创建的新 Static IP 22/443 全 timeout
- 根因：实例/网络初始化中
- 解决：重启实例（Lightsail → Reboot）或等待 1-2 分钟再测

## 问题 21：版本文件与实际 HiddifyPanel 包不一致

- 症状：`/opt/hiddify-manager/VERSION` 显示 `12.3.3`，但 `importlib.metadata.version("hiddifypanel")` 返回其他版本
- 风险：补丁可能被应用到错误源码，配置和面板行为也可能不一致
- 处理：立即停止 patch 和配置流程，保留版本输出与安装日志；不要绕过检查或强行应用补丁。参考上游 [Hiddify-Manager #5434](https://github.com/hiddify/Hiddify-Manager/issues/5434) 核对安装状态，修复后重新运行版本、健康和订阅验证

## 问题 22：`additional_configs_urls` 为空时订阅生成失败

- 症状：订阅返回 500，日志出现 `AttributeError: 'NoneType' object has no attribute 'split'`
- 根因：HiddifyPanel v12.3.3 的已报告上游问题；空的 `additional_configs_urls` 未按空列表处理
- 处理：先保存脱敏日志并核对上游 [Hiddify-Manager #5495](https://github.com/hiddify/Hiddify-Manager/issues/5495) 的当前状态；本仓库暂不自动修改该处上游代码，避免未经回归的新补丁

## 问题 23：此前可用，随后面板、订阅和全部节点同时超时

- 症状：Reality、Hysteria2、订阅和面板在此前正常后同时变慢或超时；TCP 443 或 TLS 握手可能仍成功，但具体请求返回 503/504 或长时间无响应；切换网络和重启客户端后不恢复
- 分层判断：`ping` 超时不能单独证明服务器离线；TCP 443 和 TLS 成功只证明公网路径与前端监听仍在。若管理路径和订阅路径返回 503/504，应继续检查 HAProxy/Nginx 后端、Hiddify 服务和操作系统资源
- 本次已验证案例：1GB 实例当时仅约 16MB 可用内存、没有 swap，负载持续上升且 `vmstat` 显示大量阻塞进程和 92–96% I/O wait；HiddifyPanel 出现 SIGABRT/core dump，同时存在多个系统更新相关进程。停止当时的额外负载并启用 2GB swap 后，面板由 503/504 恢复为 302，订阅恢复为 200，I/O wait 回落
- 结论边界：证据支持“服务器资源压力和 I/O 阻塞导致后端失去响应”，并表明 `unattended-upgrades` 是当时的重要并发负载；它不能证明自动安全更新是所有同类故障的唯一根因，也不能仅凭一次低内存读数自动重启服务
- 只读诊断：

  ```bash
  sudo bash /opt/vpn-deploy/scripts/diagnose-resources.sh "24 hours ago"
  sudo bash /opt/vpn-deploy/scripts/health-check.sh /opt/vpn-deploy/deployment.yaml
  sudo bash /opt/vpn-deploy/scripts/verify-subscription.sh /opt/vpn-deploy/deployment.yaml
  ```

- 重点关联同一时间窗口内的：`MemAvailable`、swap、`vmstat` 的 `b/wa`、服务 `NRestarts/Result`、core dump/OOM 记录、占用最高的进程、自动安全更新日志，以及管理和订阅 URL 的响应码
- 恢复：先向用户报告证据并确认干预。若系统更新正在造成明显资源压力，优先让它正常结束或通过 systemd 正常停止，不直接强杀包管理进程；压力解除后只有相关服务仍不响应时才重启对应服务。随后运行 `dpkg --audit`，重新执行健康与订阅验证
- 预防：默认 1GB 方案在安装阶段创建 2GB swap；保留 Ubuntu 自动安全更新。如果用户明确关闭自动安全更新，必须另行安排系统补丁。若加 swap 后仍反复出现资源压力，再评估减少未使用组件或升级实例规格。Ubuntu 对自动安全更新的说明见 [Security updates](https://documentation.ubuntu.com/security/security-updates/)
- 禁止：不部署“低于固定内存阈值就执行 `drop_caches` 并重启面板”的 cron。Linux 会自行回收可回收缓存，内核文档明确说明 `drop_caches` 不适合作为缓存增长控制手段，且可能增加后续 I/O 和 CPU 开销；单指标自动重启也可能把短时压力变成服务中断。见 [Linux `/proc/sys/vm/` 文档](https://kernel.org/doc/html/v6.7/admin-guide/sysctl/vm.html#drop-caches)
- 旧部署清理：若健康检查发现 `/usr/local/bin/memory-watchdog.sh` 的 root cron，先向用户说明该任务会自动清缓存和重启面板；获得确认后再删除对应 cron 行和脚本文件，随后重新运行健康检查

## 诊断速查命令

```bash
# 服务状态
systemctl status hiddify-panel hiddify-xray hiddify-singbox hiddify-haproxy

# 面板错误日志（找 AttributeError/Traceback）
tail -50 /opt/hiddify-manager/log/system/hiddify_panel.err.log

# 端口监听
ss -tlnup | grep -E ":80 |:443 |:9000|:3595"

# 外部连通性（本机）
nc -z -w 5 <IP> 22; nc -z -w 5 <IP> 443

# 订阅内容（本机）
curl --fail --show-error https://<DOMAIN>/<CLIENT_PATH>/<UUID>/clashmeta/
```
