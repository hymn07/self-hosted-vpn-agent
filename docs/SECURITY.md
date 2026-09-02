# 安全设计（Security Model）

## 分层防护

```
第 1 层：AWS Lightsail 防火墙（实例层面，主防线）
         只开 TCP 22/80/443 + UDP 443；启用 Hysteria2 时再开 UDP 35952-35953
         数据库、Redis、面板内部端口（9000 等）外部不可达

第 2 层：服务器内 iptables（Hiddify 自动管理）
         Hiddify 安装时写入放行规则，apply_configs 自动维护

第 3 层：SSH 加固
         仅 SSH Key 登录（PasswordAuthentication no）
         禁止口令认证；root 仅允许密钥策略或完全禁止

第 4 层：Hiddify 面板
         随机 secret 路径（admin_path 含两层随机段）
         管理员强密码（≥12 位，首次设置）
         每用户独立凭证（UUID + 订阅链接），无匿名用户（default 已删除）

第 5 层：资源与系统维护
         默认 2GB swap 缓冲 1GB 实例的突发内存压力
         unattended-upgrades 负责 Ubuntu 系统安全更新
```

## 明确不做的事

- **不启用 UFW**：Hiddify 的 apply_configs 会重写 iptables，与 UFW 冲突。防火墙控制以 Lightsail 实例层面为准（AWS 托管，更可靠）
- **不部署额外公网管理面板**：Hiddify 已提供完整管理功能
- **不自动创建额外收费防护资源**：如用户面临更高威胁，应另做风险评估

## Agent 安全规则

1. 绝不索取：AWS 账号密码 / MFA 验证码 / 银行卡信息 / 永久 Access Key
2. 真实凭据（IP、UUID、admin path、API key、订阅 URL）只写入 `.local/`（gitignored），绝不进 tracked 文件
3. 任何不可逆操作（删 Static IP、删用户、改防火墙）执行前明确告知用户
4. 修改 Hiddify 文件前先备份；patch 失败立即停止
5. Lightsail 入站规则必须与已启用协议一致：TCP 22/80/443、UDP 443；仅启用 Hysteria2 时开放 UDP 35952-35953；3306/6379/9000 等内部端口不得公开
6. 资源异常先执行只读诊断；不根据一次低内存读数自动清缓存或重启服务

## 面板访问保护

- 面板 URL：`https://<DOMAIN>/<ADMIN_PATH>/`（admin_path 为随机两层路径，用户浏览器需先设密码）
- 订阅链接：`https://<DOMAIN>/<CLIENT_PATH>/<UUID>/`（UUID 即个人凭证，泄露=可被他人使用，提醒用户勿公开）
- 用户流量限额由面板强制执行（usage_limit_GB），用光自动停用
