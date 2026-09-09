# LxPlayer 参考项目调研

调研日期：2026-09-09。三个参考仓库均已浅克隆到 `C:\Users\Administrator\Downloads\_refs\`（不入库）。

本文只记录会影响 LxPlayer 设计决策的结论。

---

## 1. Hyacine-music（首页推荐卡左右滑动）

来源：https://github.com/Ruoxi-TH/Hyacine-music ・ 许可：**MIT** ・ 版本 Beta2.49

**技术栈与我们不同**：React Native 0.86 + Expo SDK 57 + Expo Router + NativeWind + Zustand，
不是 Compose。因此只能移植交互语义，不能移植代码。

### 关键结论：那不是 Pager

首页 `app/(tabs)/index.tsx` 的推荐卡**没有使用** PageView / HorizontalPager / Swiper。
它是**一张卡片** + **三张扇形堆叠的封面** + **离散跳变**：

| 机制 | 实测值 | 说明 |
| --- | --- | --- |
| 手势 | `Gesture.Pan()` | react-native-gesture-handler |
| 横向激活阈值 | **12 px** | `activeOffsetX([-12, 12])` |
| 纵向让位阈值 | **24 px** | `failOffsetY([-24, 24])`，让位给垂直滚动 |
| 提交阈值 | **\|dx\| ≥ 36** | 只看位移，不看速度 |
| 左滑 | direction = +1（下一首） | |
| 右滑 | direction = -1（上一首） | |
| 循环 | `(i + dir + n) % n` | 无限循环 |

**拖动过程中封面不跟手**：没有实时 scale / alpha / 视差 / 旋转。松手后才动。

**松手后的入场动画**（非跟手）：`featuredIndex` 变化时把 `recommendationEntrance` 重置为 0，
再 `Animated.timing` **260 ms**、`useNativeDriver`：
- opacity `0 → 1`
- translateX `swipeDirection * 40 → 0`（从滑动来的方向入场）

### 封面扇形堆叠（右侧 160×192 区域）

| 层 | 尺寸 | 位置 | 不透明度 | 旋转 | 圆角 |
| --- | --- | --- | --- | --- | --- |
| 后（index+2） | 112×144 | right 1, top 9 | **0.35** | **+12°** | 24 |
| 中（index+1） | 120×160 | right 18, top 4 | **0.65** | **+5°** | 24 |
| 前（当前） | 128×176 | right 36, top 0 | 1.0 | **−4°** | 24 |

前层阴影：色 `#17212d`、opacity 0.22、radius 14、offset (0, 8)。

**没有页面指示器，没有自动轮播。**

### 滑动是否切歌

浏览为主，一个例外：若当前正在播放的歌在日推列表里，滑动同时 `skipTrack(±1)` 操作队列。
LxPlayer 采纳这个语义（浏览 + 命中时联动），但会用稳定 id 判定，避免 shuffle 下索引错位。

### 卡片内容与主题

左列：眼标 `featuredForYou`（12sp bold，accent 色）→ 标题（24sp bold，2 行）→ 艺术家（14sp，muted，1 行）。
下方 `h-12` 圆角胶囊播放按钮。卡片圆角 **28**，内边距 20。
**卡片本身不做封面取色渐变**。

数据来源：Netease 日推，经用户自建 hyacine-server 代理，非本地。

---

## 2. CyreneMusic-tauri（视觉参考）

来源：https://github.com/ChuxinNeko/CyreneMusic-tauri ・ v0.5.5
技术栈：Next.js 16 + React 19 + Tailwind 4 + **shadcn/ui New York**（`baseColor: neutral`）+ Tauri。

### 最重要的一点：主色是中性灰，不是品牌色

尽管名字来自崩铁角色，UI **不是**二次元/马卡龙风。它是 shadcn New York 中性灰 +
Windows 11 Fluent + iOS 液态玻璃 + Apple Music 播放页。颜色几乎全部来自**封面取色**。

### 色板（OKLCH → 近似 hex）

| Token | Light | Dark |
| --- | --- | --- |
| background | `#FFFFFF` | `#171717` |
| foreground | `#171717` | `#FAFAFA` |
| primary | `#262626` | `#E5E5E5` |
| primary-foreground | `#FAFAFA` | `#262626` |
| secondary / muted / accent | `#F5F5F5` | `#242424` |
| muted-foreground | `#737373` | `#A3A3A3` |
| destructive | `#E5484D` | `#F07167` |
| border | 黑 5% | 白 10% |

语义硬编码：喜欢 = `#EF4444`（填充）；热搜前三 = `#F97316`；全屏播放台 = 纯黑 `#000000`。

`--radius: 0.625rem`（10px）→ sm 6 / md 8 / lg 10 / xl 14 / 2xl 18 / 3xl 22。

### 排版

UI 字体 Geist Sans，等宽 Geist Mono（时间用 `tabular-nums`），歌词字体 MiSans Bold。
标题偏重：`font-extrabold` / `font-black` + `tracking-tight`。
问候语 30–48sp/900；页标题 20/30/36sp；区块标题 24sp bold；卡片标题 12–14sp bold；
元信息 10–12sp muted，小号元信息 `uppercase tracking-widest`。

### 布局

- 桌面：240px 左侧栏（折叠 64px）+ 顶栏 h-14 + 底部播放条 h-20（三栏 Spotify 式）。
  活动项左侧 3px `bg-primary` 药丸。
- 移动（<768px）：**无侧栏**。底部悬浮**全圆角玻璃药丸导航**，高 68px，`max-w-sm`，
  内边距 `px-4` + 安全区。活动项 `bg-primary/10 text-primary rounded-2xl`，图标 `stroke-2.5`，
  标签 11sp bold；非活动 10sp muted。
- 移动迷你播放器在导航**上方** `bottom-[calc(84px+safe-area)]`：h-16、`w-[92vw]`、
  全圆角、`bg-background/90 backdrop-blur-xl`、`shadow-2xl`。左侧 48px **旋转唱片**（10s/圈，
  暂停时停），中间跑马灯标题（12s），进度条是**底部内嵌 2px 细条**。

### 首页

问候语（时段感知，48px emoji + 30sp black）→ Hero 区 `lg:grid-cols-5`：
每日推荐 `col-span-3 h-240px`（`from-primary/10 via-background to-accent/5` 渐变 + 右侧
`rotate-5.7deg opacity-40` 封面拼贴）+ 私人 FM `col-span-2`（模糊封面填充 + `backdrop-blur-xl`）
→ 歌单网格 2/3/4/6 列 → 最新歌曲列表。

卡片：`rounded-xl`~`rounded-2xl`，hover 封面 `scale-110`/500ms + `bg-black/40 backdrop-blur-[2px]`
遮罩 + 白色圆形播放键，播放量药丸 `bg-black/40 backdrop-blur-md`。

### 播放页

纯黑台面，滑上 500ms。封面 `rounded-[14px]` + `shadow-[0_20px_60px_rgba(0,0,0,0.6)]`，
或黑胶模式（外圈 `border-white/15` + 旋转 + 唱臂 4°→24°）。传输键是自绘填充 SVG，
`active:scale-90`。进度条 Apple 风：`white/80` on `white/20`，**无滑块**。
右侧歌词，当前行白、其余 `white/30`。

### 队列

shadcn Sheet：桌面右侧 `max-w-md`，移动底部 **80vh** `rounded-t-2xl`，`bg-background/95 backdrop-blur-md`。
当前行 `bg-primary/10 border-primary/20` + **三条竖条均衡器动画**。

### 图标

Lucide，**1.5px 描边、不填充**（移动导航注释明确「Always use stroke」）。
例外：列表播放键填充、播放页 5 个自绘 SVG、喜欢填充。

仓库无截图（README 明写欢迎贡献截图）。`colors.xml` 里残留的 Material 紫 `#6200EE` 不是产品色，忽略。

---

## 3. NeriPlayer（播放逻辑）

来源：https://github.com/cwuom/NeriPlayer ・ 许可：**GPL-3.0（无 later、无链接例外）**

### 许可边界（重要）

每个源文件都带 GPLv3 头。抄代码 = LxPlayer 必须 GPL。
因此 LxPlayer **只借鉴架构与 Media3 用法（事实性知识，不受版权保护），不誊抄其表达**。

### 版本基线（可直接对齐）

| 项 | 值 |
| --- | --- |
| Gradle | 9.4.1 |
| AGP | 9.2.1 |
| Kotlin | 2.4.10 |
| compileSdk / minSdk / targetSdk | 37 / 28 / 36 |
| JVM target | 17 |
| Compose BOM | 2026.06.01 |
| **Media3** | **1.10.1** |
| Room / DataStore / OkHttp / Coil | 2.8.4 / 1.2.1 / 5.4.0 / 2.7.0 |

### 播放核心

服务是 `AudioPlayerService`（约 2700 行），**不是 `MediaSessionService`**——用的是 framework
`android.media.session.MediaSession` + 手搓 `NotificationCompat`，为了塞自定义收藏键、
状态栏歌词、各家 OEM 特性。播放器本身归单例 `PlayerManager` 持有。

> LxPlayer 决定分歧：用 media3 `MediaSessionService`，让通知栏由
> `MediaNotificationProvider` 免费提供，省掉 2000+ 行 OEM 适配。

播放器构建（`PlayerManagerLifecycleExtensions.initializeImpl`）：

```kotlin
DefaultExtractorsFactory().setConstantBitrateSeekingEnabled(true)   // 可变码率音频可拖动
ExoPlayer.Builder(app, renderersFactory)
    .setMediaSourceFactory(mediaSourceFactory)
    .setLoadControl(buildAudioLoadControl())
    .build()
```

音频属性**后置且条件化**（因为「混音播放」开关要关掉焦点处理）：

```kotlin
player.setAudioAttributes(
    AudioAttributes.Builder()
        .setUsage(C.USAGE_MEDIA)
        .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
    /* handleAudioFocus = */ handleFocus,
)
```

LoadControl 针对音频调参：min 15s / max 30s / 起播 1s / 重缓冲后 3s，
`setPrioritizeTimeOverSizeThresholds(true)`，**`setBackBuffer(60_000, false)`**
（小幅回退拖动不重新下载，音频场景很划算）。

`wakeMode` **按 URL 逐次设置**：http(s) → `WAKE_MODE_NETWORK`，
`file://`/`content://`/绝对路径 → `WAKE_MODE_LOCAL`，空 → `WAKE_MODE_NONE`。

### 最关键的设计：先解析、后 setMediaItem

**没有 `ResolvingDataSource`，也没有自定义 `MediaSource`。** URL 在协程里解析完，
才把成型的 `MediaItem` 交给播放器。配单调递增令牌防竞态：

```kotlin
playJob?.cancel()
playbackRequestToken += 1
val requestToken = playbackRequestToken
playJob = ioScope.launch {
    val result = resolveSongUrl(song, requestToken)
    if (!shouldApplyResolvedMedia(requestToken, playbackRequestToken)) return@launch  // 旧请求作废
    player.setMediaItem(buildMediaItem(...)); player.prepare()
}
```

解析顺序：直链 → 本地文件 → 下载缓存 → ExoPlayer 缓存（校验 content-length）→ 网络。

`setCustomCacheKey` 把缓存身份和会轮换的签名 URL 解耦——**这条必须抄（思想）**，
否则 CDN 每次换签名参数，缓存全部失效。

### 队列

队列在 `PlayerManager` 里（`currentPlaylist: List<SongItem>` + `currentIndex`），
ExoPlayer **一次只持有一个 MediaItem**（到处都是 `setMediaItem` 单数）。
上下曲 = `playAtIndex(currentIndex ± 1)` → 重新解析。代价是**没有 gapless**。

随机播放是**物理打乱列表**并快照原序（关闭时还原），而非用 ExoPlayer 的 shuffleOrder。
「下一首播放」会先去重（移除已存在项并修正插入下标）再插到 `currentIndex + 1`。

`SongItem` 是一个 30+ 字段的扁平 `@Parcelize data class`，用 `album` 字段兼当来源标记
（`isBiliTrack` 等靠它判断）——**这点不抄**，LxPlayer 用显式 `source` 枚举。

### 状态暴露

没有播放 ViewModel，`PlayerManager` 单例直接暴露约 30 个 `StateFlow` 给 Compose collect：
`currentSongFlow` / `currentQueueFlow` / `isPlayingFlow` / `playbackPositionFlow` /
`playbackDurationFlow` / `shuffleModeFlow` / `repeatModeFlow` / `pendingMediaLoadFlow`…
进度 tick **80 ms**（为逐字歌词）。另有 `playerEventFlow: SharedFlow<PlayerEvent>` 发一次性错误。

### 音源

netease（weapi/eapi 加密 + 扫码登录）、bilibili、YouTube Music（含签名解密栈）、本地文件、下载。
**没有统一的播放音源接口**——只有搜索层的 `SearchApi`，播放解析是一个巨大的分支
`resolveSongUrl`。统一契约是 `SongUrlResult.Success(url, candidateUrls, mimeType,
expectedContentLength, cacheKeyOverride, fallbackCandidates)`。

> LxPlayer 改进：定义真正的 `MusicSource` 接口注册实现，但保留 `SongUrlResult`
> 的形状（候选 + 回退 + 缓存键覆盖），那个设计是好的。

### 缓存

Media3 `SimpleCache`，默认 **1 GiB**，`LeastRecentlyUsedCacheEvictor`；无限时换
`NoOpCacheEvictor`，0 则禁用。`FLAG_BLOCK_ON_CACHE or FLAG_IGNORE_CACHE_ON_ERROR`。
`createVerifiedMediaCache` 区分「被其他进程锁住」（放弃缓存直接播）与「缓存损坏」
（删除重开一次），**从不因坏缓存崩溃播放**——这条抄思想。

下载不用 Media3 DownloadManager 也不用系统的，自己基于 OkHttp 实现（要自定义头/代理）。

### 其它

睡眠定时（倒计时 / 播完当前 / 播完列表，预设 15/30/45/60/90/120 分钟）、
倍速与变调 `PlaybackParameters(speed, pitch)`、系统 `Equalizer`、
音量归一化（自研 RMS `AudioProcessor`，非真 ReplayGain）、淡入淡出（手动音量斜坡，
单 item 播放器做不了真交叉淡化）、USB 独占输出（含 C++ native）。

持久化：Room（版本 15、**35 张表**，含 `PlaybackQueueStateEntity`/`PlaybackQueueSongEntity`
让队列跨进程重启存活）+ DataStore + 两个遗留 JSON 文件。

**没有自建后端与账号系统**：登录的都是用户自己的第三方账号；同步走用户自备的
GitHub 仓库或 WebDAV；一起听是可自托管的房间服务器。

---

## 4. LxDay（同作者项目，后端与 CI 范式）

来源：https://github.com/Lxii-Build/LxDay ・ 本地 `C:\Users\Administrator\Downloads\lx`

这是最有价值的一手参考：**同一个作者、同一套工程习惯、已经解决过我们要面对的问题。**

- 后端：Go + Gin 单实例 + SQLite，JWT 固定 HS256 + `token_ver` 可撤销，
  Dockerfile 先构建前端再编译进 Go 二进制。
- Android：Compose + **miuix** 组件 + materialKolor 动态取色，
  令牌用 Android Keystore AES/GCM 存储，「不信任 APK 内的秘密」。
- 版本基线：AGP 9.3.1 / Kotlin 2.4.10 / Compose BOM 2026.06.01 / Media3 1.10.1 / JDK 21 /
  Gradle 9.7.0（CI 里 `gradle wrapper --gradle-version 9.7.0` 现生成）。

### 签名：已经踩过的坑（直接继承其结论）

`android/app/build.gradle.kts` 注释写明根因：release 曾直接复用
`signingConfigs.getByName("debug")`，而 CI runner 每次都是全新机器、
`~/.android/debug.keystore` 每次自动重新生成 → **每次构建指纹都不同，装不上/覆盖不了**。

修法（LxPlayer 照搬）：
1. **debug 密钥库随仓库提交**（`keystore/*-debug.p12`，口令固定 `android`，
   debug 密钥按安卓惯例是公开的），让本地与 CI 的 debug 包指纹恒定。
2. release 密钥库从 Secret `ANDROID_KEYSTORE_BASE64` 解码落盘，`-P` 注入路径；
   Secret 缺失时回退 debug 签名，保证 fork 也能出包。
3. `enableV1Signing = false`、V2/V3/V4 = true。
4. CI 用 `openssl pkcs12` **先验证解码结果**（base64 被换行/截断是最常见事故）。
5. 每次构建把 `apksigner verify --print-certs` 的指纹写进 Job Summary，
   **让「签名统一」从口头断言变成每次构建都产出的机器证据**。

### 本机工具链现状（已核实）

- JDK 21：`C:\Users\Administrator\jdk\jdk-21.0.5+11`
- Android SDK：`C:\Users\Administrator\AppData\Local\Android\Sdk`
  （platforms: android-36、android-37.0；build-tools: 36.0.0、37.0.0）
- Gradle 缓存已存在（`~/.gradle/caches`）
- GitHub 凭证：Windows 凭证管理器内 `Ruoxi1337`，scope `gist, repo, workflow`
- 目标仓库：`Lxii-Build/LxPlayer`（**已存在且为空**，默认分支 main，有 admin 权限）
