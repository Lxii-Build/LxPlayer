# LxPlayer

Android 音乐播放器。视觉参考 Cyrene 的中性灰与玻璃胶囊导航，首页推荐卡复刻 Hyacine 的左右滑动扇形封面，播放链路按 NeriPlayer 的「先解析、后 setMediaItem」思路实现。后端只做账号登录和数据保存，不代理、不存储、不解析音频。

- 应用名：LxPlayer
- applicationId：`cc.lxii.player`
- 仓库：https://github.com/Lxii-Build/LxPlayer

## 功能（第一版）

- 扫描并播放设备本地音乐
- 首页推荐卡：单卡 + 三层扇形封面 + 离散跳变式左右滑动（不是 Pager）
- 底部悬浮玻璃胶囊导航 + 胶囊迷你播放器
- 纯黑播放页、播放队列、随机/循环、睡眠定时、倍速
- 可选账号：邮箱注册登录，多设备同步歌单、喜欢、历史、设置

明确不做：第三方音源解析、下载管理、歌词悬浮窗、USB 独占输出。

## 构建

APK 只在 GitHub Actions 上构建。工作流会：

1. 跑后端 `go test` 与 Android JVM 单测、Lint
2. **一次产出 debug 和 release 两个 APK**
3. 用同一张 PKCS12 给两个变体签名
4. 用 `apksigner` 提取两者 SHA-256，不一致则让任务失败
5. 把两个 APK 和 R8 mapping 作为 Artifact 上传

固定密钥库在 `android/keystore/lxplayer-debug.p12`（口令 `android`，别名 `lxplayer`）。
仓库 Secret `ANDROID_KEYSTORE_BASE64` 存在时优先用它，但必须与 debug/release 指向同一文件。

## 后端

```
cd server
go test ./...
JWT_SECRET=replace-me DB_PATH=lxplayer.db LISTEN_ADDR=:8080 go run .
```

接口：

- `POST /api/v1/auth/register|login`
- `GET /api/v1/me`
- `GET|PUT /api/v1/sync/snapshot`
- `GET /api/v1/health`

JWT 仅 HS256。改密后 `token_ver` 递增，旧令牌立即失效。登录失败不区分「账号不存在 / 密码错误」。

## 文档

- 设计规格：`docs/superpowers/specs/2026-09-09-lxplayer-design.md`
- 实现计划：`docs/superpowers/plans/2026-09-09-lxplayer.md`
- 参考调研：`docs/superpowers/research/2026-09-09-reference-analysis.md`
