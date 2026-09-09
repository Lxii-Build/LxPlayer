# LxPlayer

Android 音乐播放器。视觉参考 Cyrene 的中性灰与玻璃胶囊导航，首页推荐卡复刻 Hyacine 的左右滑动扇形封面，播放链路按 NeriPlayer 的「先解析、后 setMediaItem」思路实现。后端只做账号登录和数据保存，不代理、不存储、不解析音频。

- 应用名：LxPlayer
- applicationId：`cc.lxii.player`
- 仓库：https://github.com/Lxii-Build/LxPlayer

## 功能（第一版）

- 扫描并播放设备本地音乐
- **首页推荐卡**：单卡 + 三层扇形封面（112/120/128dp，旋转 +12°/+5°/−4°）+
  离散跳变式左右滑动。阈值 12dp 激活 / 24dp 让位纵向滚动 / 36dp 提交，
  松手后 260ms 入场。**刻意不用 Pager**——参考手感是拖动时卡片静止，松手整卡换一张
- **首页 Hero 区**：每日推荐渐变卡（右侧封面拼贴旋转 5.7°）+ 私人 FM 卡（呼吸电台徽标）
- **横向封面卡**：按压时封面放大 1.08、40% 黑遮罩淡入、白色圆形播放键浮出，前三名排名药丸用主色
- 底部悬浮玻璃胶囊导航（68dp）+ 胶囊迷你播放器（旋转唱片、跑马灯标题、底部内嵌 2dp 进度条）
- **播放页**：纯黑台面 + 封面取色径向光（换歌 800ms 交叉淡入）。
  点封面在方形与**黑胶唱盘**间切换（18 秒一圈，唱臂 4°→24°）。
  进度条无滑块、右侧显示剩余时间
- **歌词**：读取音频同目录同名的 `.lrc` 侧车文件，支持标准、一行多时间戳、
  增强型逐字三种写法。播放页左右滑动在封面与歌词间切换，当前行白色高亮、
  其余 `white/30`，自动滚动居中且不抢手动滑动，点某一行跳到那一句
- 播放队列（80% 高度玻璃面板、当前行三竖条均衡器）、随机/循环、睡眠定时、倍速
- 喜欢：本地持久化，播放页与所有列表行贯通
- 可选账号：邮箱注册登录，多设备同步歌单、喜欢、历史、设置

配色是 shadcn New York 中性灰，**不设品牌彩色**——界面上的颜色全部来自当前封面取色。

明确不做：第三方音源解析、下载管理、歌词悬浮窗、USB 独占输出。

## 构建

APK 只在 GitHub Actions 上构建，本地不需要 Android SDK。工作流会：

1. 跑后端 `go vet` + `go test`
2. 跑 Android JVM 单测与 Lint，并把测试数量写进 Job Summary（0 个测试直接判失败）
3. **用 Robolectric 真渲染界面并导出 PNG**（首页深/浅色、播放页含歌词、玻璃导航），
   作为 `lxplayer-screenshots` 产物上传。每张图断言不透明像素 >90%，
   挡住「渲染成空白却看着有图」。截图目录刻意放在 `build/` 之外并关掉任务缓存——
   否则缓存命中时测试会被跳过，而旧图被一起恢复，上传的就是上一轮的证据
4. **一次产出 debug 和 release 两个 APK**
4. 用同一张 PKCS12 给两个变体签名
5. 用 `apksigner` 提取两者 SHA-256 并逐字节比对，不一致就让任务失败
6. 把两个 APK 和 R8 mapping 作为 Artifact 上传

固定密钥库在 `android/keystore/lxplayer-debug.p12`（口令 `android`，别名 `lxplayer`），
证书指纹：

```
CC:4A:58:23:7C:47:B2:7C:87:2C:EB:94:7F:C8:E8:F7:21:1D:55:45:68:8B:BC:A9:65:14:73:A6:1A:71:C8:DD
```

仓库 Secret `ANDROID_KEYSTORE_BASE64` 存在时优先用它。无论走哪条路径，
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
