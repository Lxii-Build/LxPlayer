# LxPlayer 设计规格

日期：2026-09-09 ・ 状态：已确认 ・ 调研依据：[参考项目调研](../research/2026-09-09-reference-analysis.md)

## 1. 产品定义

LxPlayer 是一个 Android 音乐播放器。

- **UI 视觉**参考 CyreneMusic-tauri：中性灰 shadcn New York 色板 + 液态玻璃胶囊导航 +
  Apple Music 式纯黑播放页。
- **首页推荐卡**参考 Hyacine-music：单卡 + 三层扇形封面堆叠 + 离散跳变式左右滑动。
- **播放逻辑**参考 NeriPlayer：先解析后 `setMediaItem`、令牌防竞态、自定义缓存键、
  按 URL 设 wakeMode、音频专用 LoadControl。
- **后端只做账号登录与数据保存**，不代理音频、不存音频、不解析第三方音源。

全部品牌标识统一为 **LxPlayer**：applicationId `cc.lxii.player`，包名 `cc.lxii.player`，
应用名「LxPlayer」，仓库 `Lxii-Build/LxPlayer`。

### 明确不做（YAGNI）

第三方音源（网易云/B站/YouTube）解析、桌面端、iOS、歌词悬浮窗、USB 独占输出、
Xposed 集成、一起听、真交叉淡化、均衡器、可视化特效、下载管理器。

第一版音源只有**设备本地音乐**（MediaStore）。这不是缩水：它让播放链路可以端到端
真实测试而不依赖任何外部服务，也避开了 NeriPlayer 的 GPL 边界与音源反爬维护成本。
`MusicSource` 接口留出扩展点，但只有一个实现。

## 2. 技术栈

| 项 | 值 | 依据 |
| --- | --- | --- |
| 语言 | Kotlin 2.4.10 | 与 NeriPlayer / LxDay 一致 |
| UI | Jetpack Compose，Compose BOM 2026.06.01 | 同上 |
| 播放 | **media3 1.10.1**，`MediaSessionService` | 与 NeriPlayer 同版本，但用官方 Session（分歧见调研 §3） |
| 图片 | Coil 3.0.4 | 与 LxDay 一致 |
| 网络 | OkHttp 4.12.0 | 与 LxDay 一致 |
| 偏好 | DataStore Preferences 1.2.1 | |
| 取色 | AndroidX Palette | 封面取色驱动播放页背景 |
| 构建 | AGP 9.3.1 / Gradle 9.7.0 / JDK 21 | 与 LxDay 一致 |
| SDK | compileSdk 37 / minSdk 28 / targetSdk 36 | Compose BOM 2026.06.01 的 AAR 要求 compileSdk ≥ 37；targetSdk 保持 36 |

第一版**不引入 Room**：队列跨进程存活可以先用 DataStore 存 id 列表，
为一张表拉进注解处理器不划算。等真的需要多表关联时再加。

AGP 9 内置 Kotlin 支持，**不能**再套 `org.jetbrains.kotlin.android` 插件（会直接报错拒绝）。
| 后端 | Go 1.23 + net/http + SQLite | 沿用 LxDay 范式，去掉 Gin 依赖 |

**不引入 miuix**。LxDay 用 miuix 是因为要 HyperOS 风格；LxPlayer 要的是 Cyrene 的
中性灰 + 玻璃风，用 Material3 自定义主题实现更直接。

## 3. 模块结构

```
LxPlayer/
├── android/                     Android 客户端（Gradle 根）
│   ├── app/                     单模块应用
│   ├── keystore/lxplayer-debug.p12   随仓库提交的固定 debug 密钥库
│   └── gradle/libs.versions.toml
├── server/                      Go 后端（账号 + 数据同步）
├── docs/superpowers/            规格、计划、调研
└── .github/workflows/           CI
```

单 Gradle 模块。理由：第一版代码量不足以支撑多模块的构建复杂度，
而 NeriPlayer 的 26 个 player 子目录是 2700 行服务催生的，我们没有那个体量。
按包分层即可。

### Android 包结构

```
cc.lxii.player
├── LxPlayerApp.kt               Application，容器初始化
├── MainActivity.kt
├── core/
│   ├── player/
│   │   ├── PlaybackService.kt        MediaSessionService
│   │   ├── PlayerController.kt       单例，持有 ExoPlayer + 队列 + StateFlow
│   │   ├── PlayerFactory.kt          ExoPlayer 构建（LoadControl / 缓存 / 渲染器）
│   │   ├── MediaCacheFactory.kt      自愈式 SimpleCache
│   │   └── policy/                   纯函数决策（可单测，无 Android 依赖）
│   │       ├── WakeModePolicy.kt
│   │       ├── QueuePolicy.kt        下一首插入/去重/移动/随机
│   │       ├── RepeatPolicy.kt
│   │       └── SleepTimerPolicy.kt
│   ├── source/
│   │   ├── MusicSource.kt            音源接口 + SongUrlResult
│   │   └── LocalMusicSource.kt       MediaStore 实现
│   └── net/                          OkHttp + 后端 API 客户端
├── data/
│   ├── model/                        Track、Playlist、PlayQueueState
│   ├── db/                           Room（entity / dao / database）
│   ├── prefs/                        DataStore 设置
│   └── repo/                         LibraryRepository、AuthRepository、SyncRepository
└── ui/
    ├── theme/                        色板、排版、形状
    ├── component/                    玻璃导航、迷你播放器、封面卡、均衡器动画
    ├── home/                         首页 + 推荐卡滑动
    ├── library/  search/  nowplaying/  queue/  settings/  login/
    └── nav/                          导航图
```

## 4. 播放引擎

### 4.1 契约

```kotlin
// core/source/MusicSource.kt
interface MusicSource {
    val id: String
    suspend fun resolve(track: Track, quality: AudioQuality): SongUrlResult
}

sealed interface SongUrlResult {
    data class Success(
        val url: String,
        val mimeType: String?,
        val cacheKeyOverride: String?,     // 与轮换签名 URL 解耦（NeriPlayer 的好设计）
        val expectedContentLength: Long = -1L,
        val fallbackUrls: List<String> = emptyList(),
    ) : SongUrlResult
    data class Failure(val reason: String, val retryable: Boolean) : SongUrlResult
}
```

`Track` 带**显式** `source: SourceId` 字段，不像 NeriPlayer 用 `album` 兼当来源标记。

### 4.2 播放流程

`PlayerController.playAt(index)`：

1. `playJob?.cancel()`；`requestToken += 1`，捕获本次 token
2. 设 `pendingLoad = true`（UI 显示解析中）
3. IO 协程调用 `source.resolve(track, quality)`
4. **应用前再校验 `token == requestToken`**，不等则整个丢弃（防旧请求覆盖新请求）
5. 按 URL 协议设 `wakeMode`（`WakeModePolicy`）
6. 构建 `MediaItem`（`mediaId` = track 稳定 id；非本地时 `setCustomCacheKey`）
7. `setMediaItem` → `prepare()` → `play()`

### 4.3 ExoPlayer 配置

```kotlin
// LoadControl：音频场景专用（对齐 NeriPlayer 的实测参数）
DefaultLoadControl.Builder()
    .setBufferDurationsMs(15_000, 30_000, 1_000, 3_000)
    .setPrioritizeTimeOverSizeThresholds(true)
    .setBackBuffer(60_000, false)          // 小幅回退拖动不重新下载
    .build()

DefaultExtractorsFactory().setConstantBitrateSeekingEnabled(true)  // CBR 音频可拖动

AudioAttributes.Builder()
    .setUsage(C.USAGE_MEDIA)
    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
    .build()                               // handleAudioFocus = true
player.setHandleAudioBecomingNoisy(true)   // 拔耳机暂停，用官方能力
```

缓存：`SimpleCache` + `LeastRecentlyUsedCacheEvictor`，默认 512 MiB（比 NeriPlayer 的
1 GiB 保守，本地音源为主时不需要那么大），`StandaloneDatabaseProvider`。
`MediaCacheFactory` 必须**自愈**：`checkInitialization()` 失败时区分「被占用」（放弃缓存直接播）
与「损坏」（删除重开一次），**任何情况下不因缓存问题崩溃播放**。

### 4.4 队列

队列由 `PlayerController` 持有（`queue: List<Track>` + `currentIndex`），
ExoPlayer 单 item。与 NeriPlayer 一致，理由相同：每首歌都要独立解析。
接受「无 gapless」这个代价。

`QueuePolicy` 是纯函数，全部可单测：

```kotlin
fun insertNext(queue: List<Track>, currentIndex: Int, track: Track): QueueMutation
fun addToEnd(queue: List<Track>, track: Track): QueueMutation
fun remove(queue: List<Track>, currentIndex: Int, removeIndex: Int): QueueMutation
fun move(queue: List<Track>, currentIndex: Int, from: Int, to: Int): QueueMutation
fun shuffled(queue: List<Track>, currentIndex: Int, seed: Long): QueueMutation
```

`insertNext` 必须去重：已存在则先移除，且当被移除项在插入点之前时**插入下标要减一**。
随机播放物理打乱并快照原序，关闭时还原（与 NeriPlayer 同策略）。
`RepeatPolicy` 循环 OFF → ONE → ALL。

### 4.5 状态暴露

`PlayerController` 单例暴露 StateFlow，Compose 直接 collect（不套一层播放 ViewModel）：

`currentTrack: StateFlow<Track?>`、`queue`、`currentIndex`、`isPlaying`、
`positionMs`、`durationMs`、`repeatMode`、`shuffleEnabled`、`pendingLoad`、
`events: SharedFlow<PlayerEvent>`（一次性错误提示）。

进度 tick **200 ms**（无逐字歌词，不需要 NeriPlayer 的 80 ms）。

### 4.6 其它播放能力

- 睡眠定时：倒计时 / 播完当前，预设 15/30/45/60/90 分钟（`SleepTimerPolicy` 纯函数）
- 倍速：0.5×–2.0×，`PlaybackParameters(speed, 1f)`

## 5. UI 设计

### 5.1 色板（Cyrene 移植）

```kotlin
// Light
background        = 0xFFFFFFFF   onBackground   = 0xFF171717
surface           = 0xFFFFFFFF   surfaceVariant = 0xFFF5F5F5
primary           = 0xFF262626   onPrimary      = 0xFFFAFAFA
mutedForeground   = 0xFF737373   outline        = Black 5%
// Dark
background        = 0xFF171717   onBackground   = 0xFFFAFAFA
surface           = 0xFF171717   surfaceVariant = 0xFF242424
primary           = 0xFFE5E5E5   onPrimary      = 0xFF262626
mutedForeground   = 0xFFA3A3A3   outline        = White 10%
// 语义
liked  = 0xFFEF4444      destructive = 0xFFE5484D / 0xFFF07167
stage  = 0xFF000000      （播放页台面）
```

主色是中性灰，**不设品牌彩色**。颜色由封面取色（Palette）在播放页与歌单页产生。

圆角：sm 6 / md 8 / lg 10 / xl 14 / card 16 / cover 20 / hero 24 / pill 全圆。

排版：`titleLarge` 24sp W800 tracking -0.5、`headlineLarge` 30sp W900、
卡片标题 14sp W700、正文 14sp W500、元信息 12sp/10sp muted、时间用等宽 tabular。

### 5.2 导航

底部**悬浮玻璃胶囊导航**：高 68dp、左右各 16dp 边距 + 安全区、全圆角、
`surface.copy(alpha=0.72f)` + `Modifier.blur` 玻璃、外阴影。
四项：首页 / 搜索 / 音乐库 / 我的。活动项 `primary.copy(alpha=0.10f)` 药丸背景 +
primary 色图标（描边 2.5dp）+ 11sp W700 标签；非活动 muted + 10sp W500。

迷你播放器悬浮在导航**上方** 16dp：高 64dp、`width 92%`、全圆角、
`surface.copy(alpha=0.90f)` + blur。左 48dp **旋转封面**（10s/圈，暂停时停转）、
中跑马灯标题、右队列/播放/下一首键，**底部内嵌 2dp 进度条**。

### 5.3 首页推荐卡（核心交互，严格复刻 Hyacine 数值）

外层 `Card` 圆角 28dp、内边距 20dp、最小高 192dp。

**手势**（`Modifier.pointerInput` + `awaitPointerEventScope`，不是 `HorizontalPager`）：

| 参数 | 值 |
| --- | --- |
| 横向激活阈值 | 12dp |
| 纵向让位阈值 | 24dp（超过则放弃，交给垂直滚动） |
| 提交阈值 | \|dx\| ≥ 36dp（只看位移，不看速度） |
| 左滑 | +1（下一张） |
| 右滑 | −1（上一张） |
| 循环 | `(i + dir + n) % n` |

**拖动中封面不跟手**（与参考一致）。松手且达阈值后：`featuredIndex` 变化触发入场动画
**260 ms**：alpha 0→1，translationX `direction * 40dp → 0`。

**三层扇形封面**（右侧 160×192dp 区域，绝对定位）：

| 层 | 尺寸 | 位置 | alpha | 旋转 | 圆角 |
| --- | --- | --- | --- | --- | --- |
| 后 (i+2) | 112×144dp | right 1, top 9 | 0.35 | +12° | 24dp |
| 中 (i+1) | 120×160dp | right 18, top 4 | 0.65 | +5° | 24dp |
| 前 (i) | 128×176dp | right 36, top 0 | 1.0 | −4° | 24dp |

前层阴影：`#17212D` alpha 0.22、blur 14dp、offset (0, 8)。

**无页面指示器，无自动轮播**（与参考一致）。

左列：眼标「为你推荐」12sp W700 primary → 标题 24sp W700 最多 2 行 →
艺术家 14sp muted 1 行。下方 48dp 高全圆角播放胶囊。

**滑动语义**：默认仅浏览。若当前播放曲目在推荐列表内（按稳定 id 判定，非索引），
滑动同时切换队列上下曲——复刻 Hyacine 行为，但用 id 判定避免随机播放下错位。

### 5.4 首页其余部分

时段问候（30sp W900）+ 头像 → 推荐卡 → 「每日歌曲」列表（跳过第 0 首，
它已在推荐卡展示）→ 最近播放横向卡片列表。

歌单/专辑卡：圆角 20dp，按压封面 `scale 1.08`（400ms），
`Black 40%` 遮罩 + 白色圆形播放键。

### 5.5 播放页

纯黑台面，从底部滑入 400ms。封面圆角 14dp + 大投影，或黑胶模式（旋转 + 唱臂 4°→24°）。
背景为封面取色的径向渐变叠加，换歌时 800ms 交叉淡入。
传输键：播放 72dp、上下曲 60dp，`active` 时 `scale 0.9`。
进度条 Apple 风：`White 80%` on `White 20%`、**无滑块**、右侧显示剩余时间。
喜欢键填充 `#EF4444`。

### 5.6 队列

`ModalBottomSheet` 高 80%、顶部圆角 18dp、`surface alpha 0.95` + blur。
标题「播放队列」20sp W900 + 清空（destructive）。行高 56dp、封面 40dp 圆角 10dp。
当前行 `primary alpha 0.10` 背景 + primary 标题 + **三条竖条均衡器动画**。
可拖拽重排、右滑移除。

### 5.7 图标

Material Symbols 描边风（Compose `Icons.Outlined.*`），描边视觉对齐 1.5dp。
例外：列表播放键、播放页传输键、喜欢键用填充版。

## 6. 后端（只做账号与数据）

Go + `net/http` + SQLite 单实例，**不代理音频、不存音频、不解析音源**。

### 职责

1. 邮箱 + 密码注册/登录，签发 JWT
2. 保存用户数据：歌单、喜欢、播放历史、设置快照
3. 多设备拉取/合并这些数据

### 接口

```
POST /api/v1/auth/register     {email, password}        → {token, user}
POST /api/v1/auth/login        {email, password}        → {token, user}
GET  /api/v1/me                                          → {user}
GET  /api/v1/sync/snapshot                               → {playlists, likes, history, settings, revision}
PUT  /api/v1/sync/snapshot     {…, baseRevision}         → {revision} | 409 冲突
GET  /api/v1/health                                      → {status, version}
```

同步用**整快照 + 单调 revision** 乐观并发，不做 CRDT。理由：单人多设备场景冲突罕见，
`baseRevision` 不匹配返回 409 让客户端重取合并即可，复杂度换来的收益不成正比。

### 安全（继承 LxDay 的既有结论）

- JWT 固定 HS256；库中存 `token_ver`，每次请求校验，改密即全端失效
- 密码 bcrypt cost 12
- 登录失败不区分「账号不存在 / 密码错误」
- **APK 内不放任何共享密钥**；客户端只用 HTTPS + 用户 JWT
- Android 端令牌用 Keystore AES/GCM 加密存储
- 所有输入在服务端做长度/格式/归属校验；请求体大小上限
- TLS 由容器外反向代理终止

## 7. 测试策略

TDD。可在 JVM 上跑的纯逻辑必须先写测试：

| 目标 | 测试内容 |
| --- | --- |
| `QueuePolicy` | 下一首去重与下标修正、移除当前项、移动、随机后还原 |
| `RepeatPolicy` | 三态循环、播完与手动跳转的差异 |
| `WakeModePolicy` | http/https/file/content/绝对路径/空串 |
| `SleepTimerPolicy` | 剩余时间计算、播完当前模式 |
| `SwipeGesturePolicy` | 12/24/36dp 阈值判定、循环索引换算 |
| `RequestTokenGuard` | 迟到解析结果被丢弃 |
| `LxColors` | 色板数值不被顺手改掉 |
| `filterTracks` | 标题/艺术家/专辑匹配、大小写、空查询 |
| `SyncMerge` | revision 冲突、快照合并 |
| Go 后端 | 注册/登录/JWT 校验/token_ver 撤销/快照乐观并发 |

Lint 的 `UnsafeOptInUsageError` 不受编译器 opt-in flag 影响：
碰 Media3 的类必须显式标注 `@UnstableApi`，否则 `lintDebug` 会拦住构建。

Android 框架强耦合部分（Service、Compose 渲染）不写脆弱的仪器测试，
靠把决策抽成纯函数来获得覆盖——这是 NeriPlayer `policy/` 模式的核心价值。

## 8. CI 与签名（硬性要求）

工作流 `.github/workflows/build-android.yml`：

1. JDK 21 + `gradle/actions/setup-gradle`，`gradle wrapper --gradle-version 9.7.0`
2. 跑 JVM 单测 + lint
3. **一次构建同时产出 debug 与 release**（`assembleDebug assembleRelease`）
4. **两者签名必须一致**：release 密钥库来自 Secret `ANDROID_KEYSTORE_BASE64`，
   同一密钥库**同时**用于 debug 与 release 的 `signingConfig`
5. Secret 缺失时，两者统一回退到随仓库提交的固定 `keystore/lxplayer-debug.p12`
   （口令 `android`）——仍然保证 debug 与 release 指纹相同
6. base64 解码后用 `openssl pkcs12` 校验合法性再继续
7. `enableV1Signing=false`，V2/V3/V4=true
8. **构建后用 `apksigner verify --print-certs` 提取两个 APK 的 SHA-256，
   逐字节比对；不一致则 `exit 1` 让工作流失败**，并把指纹写进 Job Summary

第 8 条是「签名统一」的机器证据：不是口头承诺，而是每次构建都执行的断言。

后端工作流 `build-server.yml`：`go vet` + `go test ./...` + 交叉编译。

**验收标准：工作流在 GitHub Actions 上跑到绿**，产物包含签名一致的 debug 与 release APK。
