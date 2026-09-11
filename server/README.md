# LxPlayer 自研后端（Go）

App 的**可选**账号后端。它只做账号登录与用户数据保存——**不代理音频、不存储音频、不解析音源**。

> ⚠️ **这是 opt-in 的，App 默认不使用它。** 默认后端仍是第三方服务 `https://music.nekofun.top`。
> 只有你在 App「设置 → 网络」里显式把后端切到「自定义源」并填入本后端地址，账号请求才会走这里。

## 它为什么「能力不全」（先读这段）

本后端是在 App 从「本地音乐播放器 + 自建账号」**pivot 到当前 CyreneMusic 底座之前**写的，
只覆盖了当时规格里的最小账号能力。pivot 之后 App 的账号模型复杂得多（username 非空、邮箱验证码、
LinuxDo 绑定、账号绑定表、地理位置…），因此本后端**不是「没写完」，而是「与当前 App 账号架构不是同一套」**。

结论：App 侧目前只在 selfHosted 模式下接通它，且**只对接「登录 / 获取用户信息」**；
其余能力在 App 侧会**明确报「该后端不支持」**，不会静默成功或降级。

## 与 App 的能力兼容矩阵

| 能力 | App 官方端点 | 自研后端 | 说明 |
| --- | --- | --- | --- |
| 登录 | `POST /auth/login` | ✅ `POST /api/v1/auth/login` | 自研端收 `{email, password}`，返回 `{token, user:{id, email}}` |
| 校验令牌 / 取用户 | `GET /auth/validate-token` | ✅ `GET /api/v1/me` | 自研仅返回 `{id, email}` |
| 注册 | `POST /auth/register`（+ `/auth/register/send-code`） | ❌ | 自研**没有 username 字段**，也没有邮箱验证码端点 |
| 重置密码 | `POST /auth/reset-password`（+ `/send-code`） | ❌ | 未实现 |
| 修改用户名 | `POST /auth/update-username` | ❌ | 未实现 |
| LinuxDo 登录 | `POST /auth/linuxdo/login` | ❌ | 未实现 |
| 第三方账号绑定 | `/accounts/bindings`、`/accounts/*/unbind` | ❌ | 未实现 |
| 注册状态查询 | `GET /auth/registration-status` | ❌ | 未实现 |
| IP 归属地更新 | `POST /auth/update-location` | ❌ | 未实现 |
| 数据快照同步 | 无 | ⚠️ `GET / PUT /api/v1/sync/snapshot` | 后端已实现，但 App 侧**尚无对应功能**，暂无人消费 |

> 上表中 ❌ 的能力，在 App 的 selfHosted 模式下会返回明确的「该后端不支持」错误，UI 可直接提示用户。

## 本地运行

```bash
cd server

export JWT_SECRET="请换成一个足够长的随机串"   # 不设置则回退到不安全的 "dev-only-change-me"
export DB_PATH="lxplayer.db"                   # 默认 lxplayer.db（SQLite 单文件）
export LISTEN_ADDR=":8080"                     # 默认 :8080

go run .
```

- 健康检查：`GET /api/v1/health` → `{"status":"ok","version":"1.0.0"}`
- 跑测试：`cd server && go test ./...`

环境变量一览：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `JWT_SECRET` | `dev-only-change-me` | JWT 签名密钥（HS256）。**生产必须改。** |
| `DB_PATH` | `lxplayer.db` | SQLite 数据库文件路径。 |
| `LISTEN_ADDR` | `:8080` | 监听地址。 |

## 部署

仓库自带多阶段构建的 `Dockerfile`（distroless 运行镜像，非 root 用户）：

```bash
cd server
docker build -t lxplayer-server .
docker run -d -p 8080:8080 \
  -e JWT_SECRET="<random-long-secret>" \
  -e DB_PATH="/data/lxplayer.db" \
  -v lxplayer-data:/data \
  lxplayer-server
```

部署注意事项：

1. **务必设置强 `JWT_SECRET`**（默认值仅供本地开发）。
2. 把 `DB_PATH` 挂到**持久卷**，否则容器重建会丢账号数据。
3. 生产环境请置于 **TLS 反向代理**之后，不要在公网裸奔 HTTP。

## 在 App 里启用（opt-in）

自研后端由 App 里一个**独立的账号后端开关**控制，与「自定义源」配置**互不影响**
（切换自定义源不会改变账号后端，反之亦然）：

| 持久化键 | 取值 | 说明 |
| --- | --- | --- |
| `account_backend_mode` | `official`（默认）/ `selfHosted` | 账号后端模式 |
| `account_backend_base_url` | 后端地址 | 仅 `selfHosted` 时生效 |

只有当**两者同时满足**（模式为 `selfHosted` 且地址非空）时，App 的账号请求才走本后端；
其它任何情况一律走官方后端，**存量用户升级后账号行为零变化**。

> 说明：本轮先提供**持久化配置 + 文档**；设置页里的可视化开关（下拉 / 输入框）
> 安排在下一轮加入。在此之前需要先写入上面两个键才能启用。

## 安全说明

- 密码使用 **bcrypt** 哈希存储；令牌为 **JWT HS256**，签发者 `lxplayer`，30 天过期。
- 请求体上限 1 MiB；邮箱、密码均有长度校验。
- 邮箱冲突与其它写入失败对外使用**同一句文案**，避免账号枚举探测。
