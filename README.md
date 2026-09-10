# LxPlayer

Flutter 音乐播放器，构建在 [CyreneMusic](https://github.com/moraxs/CyreneMusic) 的 Flutter 底座之上，包名 `cc.lxii.player`。首页推荐卡复刻 Hyacine 的左右滑动扇形封面，播放链路按 NeriPlayer 的「先解析、后 setMediaItem」思路实现。

自带后端只负责账号登录和数据保存——不代理、不存储、不解析音频。联网取歌由客户端直连音源完成，不经后端。

- 应用名：LxPlayer
- applicationId：`cc.lxii.player`
- 仓库：https://github.com/Lxii-Build/LxPlayer
- 技术栈：Flutter（Dart）+ Go 后端；覆盖 Android / Windows / macOS / Linux

## 功能

底座自带的能力全部保留，规格按此调整：

- **本地音乐**：扫描设备音乐、歌单、喜欢、历史、缓存
- **在线音源**：网易云、酷狗、LX Music（`lx_music_source_parser` 运行时）。
  登录方式含账号密码、二维码、LinuxDo
- **首页推荐卡**：单卡 + 三层扇形封面（112/120/128dp，旋转 +12°/+5°/−4°）+
  离散跳变式左右滑动。阈值 12dp 激活 / 24dp 让位纵向滚动 / 36dp 提交，
  松手后 260ms 入场。**刻意不用 Pager**——参考手感是拖动时卡片静止，松手整卡换一张
- **播放页**：封面取色径向光（换歌 800ms 交叉淡入），点封面在方形与黑胶唱盘间切换
  （18 秒一圈，唱臂 4°→24°）。逐字歌词、流光云背景、队列、随机/循环、睡眠定时、倍速
- **歌词**：标准 / 一行多时间戳 / 增强型逐字 LRC；另有 Android 悬浮歌词与桌面歌词窗
- **下载与缓存**、**系统媒体通知**、**桌面小部件**
- **桌面端**（Windows/macOS/Linux）：系统托盘、迷你播放器窗口、SMTC 媒体控制
- **管理后台**：见 `app/docs/ADMIN_PANEL.md`
- **自动更新**、开发者模式
- **账号**：邮箱注册登录，多设备同步歌单、喜欢、历史、设置

界面可在 Material / Windows Fluent / Cupertino 三套框架间切换（运行时由 `ThemeManager` 决定），
因此不存在单一品牌色——播放相关配色取自当前封面。

> **规格变更**：最初写的「明确不做：第三方音源解析、下载管理、歌词悬浮窗」已经作废。
> 换成 CyreneMusic 底座后这三项都在，并且是应用的主要能力。

## 构建

APK 只在 GitHub Actions 上构建，本地不需要 Android SDK。工作流会：

1. 跑后端 `go vet` + `go test`
2. 跑 `flutter test`（Dart 单测）
3. **一次产出 debug 和 release 两个 APK**
4. 用同一张 PKCS12 给两个变体签名
5. 用 `apksigner` 提取两者 SHA-256 并逐字节比对，不一致就让任务失败
6. 把两个 APK 作为 Artifact 上传

> **待补（重要）**：`702c545` 换成 Flutter 底座时，重写前的 21 个 Kotlin 测试被整体删除，
> 其中包括 Robolectric 真渲染截图和风格几何断言（圆角、扇形三层、唱盘、玻璃、均衡器、
> 歌词行高）。目前还没有对应的 Dart 版本，也就是说「风格到底做出来没有」现在
> **没有任何自动化证据**，只能靠人眼看截图。补回来是接下来的第一优先级。

固定密钥库在 `app/android/keys/lxplayer-release.p12`（口令 `lxplayer`，别名 `lxplayer`），
证书指纹：

```
39:B3:DA:9A:FB:B9:EB:C7:0F:BB:F6:BA:75:F1:BC:4F:C2:D6:3A:A8:56:9E:1E:FE:7A:FC:B5:F4:F6:34:B8:76
```

仓库 Secret `LXPLAYER_KEYSTORE_BASE64` 存在时优先用它。无论走哪条路径，
debug 与 release 都指向同一个 `storeFile`，所以两者签名必然一致。

之所以要把 debug 密钥库提交进仓库：CI runner 每次都是全新机器，
`~/.android/debug.keystore` 会被自动重新生成，导致每次构建的指纹都不同、装不上也覆盖不了。
密钥库必须是确定的文件，而不是自动生成的。debug 密钥按安卓惯例是公开的。

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
