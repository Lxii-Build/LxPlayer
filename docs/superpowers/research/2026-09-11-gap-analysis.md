# LxPlayer 差距分析（调研）

- 日期：2026-09-11
- 调研人：许清楚（产品经理）
- 方法论（所有结论都有可复现来源，不是凭印象）：
  1. **逐字节比对** CyreneMusic 上游与本地：从 GitHub Trees API 取每个 `lib/*.dart` 的 blob sha，用 `git hash-object` 算本地同名文件的 sha 后对比。结论是精确的、可重复的。
  2. 定向读码（Read/Grep，带行号），不遍历整份 jsonl。
  3. 参考项目经 GitHub API + raw 抓取实际源码后对比（Hyacine 首页、CyreneMusic 全树、NeriPlayer 结论复用上游调研但已核验过关键值）。
  4. CI / PR / 分支状态经 GitHub API 核实。
- **无法确认的部分**：本机没有 Flutter / Android SDK，未能实际跑 `flutter test`、`flutter build` 或任何模拟器渲染；桌面端（Windows/macOS/Linux）构建与运行**未验证**。这些在下文明确标注「无法确认 + 原因」。

---

## 0. 一句话结论

当前 `flutter-rewrite` 分支上的 LxPlayer，**实质是 CyreneMusic Flutter 底座的品牌替换版**：它与上游 248 个 `lib/*.dart` 里 **208 个逐字节相同**，39 个只改了品牌字符串，1 个改了文件名，自己新写的只有 3 个文件（滑动推荐卡、一个网易云映射器、一个配置服务改名）。原计划里的 Kotlin/Compose 版（含按用户要求重做的登录页、22 个 Kotlin 测试）在 `702c545` 被整体删除。

由此产生三个最要紧的落差：

1. **自研 Go 后端是「孤儿」**：`server/` 写得完整、9 个测试全过，但客户端**零引用**（`grep -rn "api/v1" app/lib` 无命中）。App 的账号与在线能力全部打向 CyreneMusic 自己的第三方后端 `https://music.nekofun.top`。
2. **「UI 参考 CyreneMusic-tauri」从未落地**，实际走的是 fork `moraxs/CyreneMusic`；后者是「保留底座全部能力」，与原设计规格（只用本地音源、明确不做第三方解析/下载/悬浮歌词）方向相反，README 已承认规格作废。
3. **云构建只证明「能编译 + 34 个 Dart 测试 + 签名一致」**，没有任何截图 / golden / 模拟器渲染产物；其中 1 个新测试还钉在了一个 App 根本不渲染的组件上（见 §3）。

---

## 1. 未完成 / 半完成需求清单

逐条对照 `.workbuddy/claude_user_msgs.txt`（[1] 为主需求，[13][15][23] 为 Stop hook 反复追的验收缺口，[25] 为追加需求）。

| # | 原始要求（出处） | 状态 | 代码证据 / 说明 |
| --- | --- | --- | --- |
| 1 | 首页推荐卡左右滑动，参考 Hyacine（[1]） | ✅ 完成 | `app/lib/pages/home_page/swipe_recommend_card.dart:31-71`（阈值 12/24/36、260ms、40dp 入场）、`:95-127`（三层扇形 112/120/128）、`:160-263`（手势与动画）。接入点：`home_for_you_tab.dart:292`、`charts_tab.dart:145`。测试：`app/test/swipe_recommend_card_test.dart`、`style_geometry_test.dart` |
| 2 | UI 参考 `ChuxinNeko/CyreneMusic-tauri`（[1]） | ❌ 未采用 | 仓库内**没有任何** tauri 项目文件；实际 UI 来自 `moraxs/CyreneMusic`（Flutter）。见 §2 |
| 3 | UI 参考 `moraxs/CyreneMusic`（[25] 追加） | ✅ 以 fork 形式满足 | 208/248 文件逐字节相同（§2.2） |
| 4 | 全面改名 LxPlayer（[1]） | 🟡 半完成 | 已完成：`android/app/build.gradle.kts:19,35`（namespace/applicationId `cc.lxii.player`）、`windows/runner/main.cpp:26,60`、`lx_config_service.dart:48`（magic `"LXPL"`）。**未完成**：`app/README.md:1` 标题仍是「Cyrene Music 🎵」；`app/windows/runner/Runner.rc:92-98`、`runner.exe.manifest:6-8`、`updater.ps1:1` 仍是 Cyrene Music / `cyrene_music.exe`；`app/lib/services/README.md:20` 仍写 `package:cyrene_music`；`url_service.dart:17` 官方源仍是 `https://music.nekofun.top`。全仓库品牌残留 **49 个文件** |
| 5 | 写一个只做账号登录与数据保存的后端（[1]） | 🟡 写了但未接入 | 后端存在且质量高：`server/main.go`（bcrypt cost 12、HS256+token_ver、注册登录、快照乐观并发），`server/main_test.go` 9 个测试。**但客户端 0 引用**：`grep -rn "api/v1\|:8080\|sync/snapshot" app/lib app/android` 无命中。App 实际账号走 `auth_service.dart:174-933`（`${UrlService().baseUrl}/auth/*` → `music.nekofun.top`）。「后端不代理音频」对 Go 服务成立，但 App 真正依赖的那个第三方后端本身就是音频解析代理（`url_service.dart:137-200`：`/song`、`/bili/playurl`…） |
| 6 | 播放逻辑参考 NeriPlayer（[1]） | 🟡 部分 | 已对齐：「先解析后 open」`player_service.dart:770,853,975`（`mk.Media(url)`）；丢弃过期结果用 id 判定 `:454,461`；缓存键与 URL 解耦 `cache_service.dart:205-207`（`{source}_{songId}`）。未对齐：无单调 request token、无 wakeMode、无 LoadControl/backBuffer（media_kit 无对应物）、**无倍速**（全库无 `setRate`/`playbackRate`）。见 §2.4 |
| 7 | 严格按 SuperPowers 规范构建（[1]） | 🟡 初期做了，重写后断档 | `docs/superpowers/` 只有 3 份（plans/specs/research），**全部描述已被删除的 Kotlin/Compose 版**：`plans/2026-09-09-lxplayer.md:5,7,9`（"Android Compose music player"、Kotlin 2.4.10、AGP 9.3.1）、`specs/...design.md:32-40`。重写 `702c545` **没有产出**对应的新 spec/plan/research；README:87-89 仍把这三份当权威文档链接 |
| 8 | 构建在云端 + 工作流一直盯到绿（[1]） | ✅ 完成 | 本地不构建，`README.md:40`；run **#63 @ `6e3dcc6` = success**（API 核实）。⚠️ 但 `main` 上还没有这些改动：`main` head = `9ea50dd`（Kotlin 时代的登录改版提交），**PR #3（flutter-rewrite → main）仍 open 未合并** |
| 9 | 签名统一（debug/release 同证书）（[1]） | ✅ 完成 | `.github/workflows/ci.yml`「校验 debug 与 release 签名指纹一致」步骤：`apksigner --print-certs` 提取两个 APK 的 SHA-256 并逐字节比对，不等即 `exit 1`；另有期望指纹 `39B3DA9A…` 判定来源。密钥库 `app/android/keys/lxplayer-release.p12` |
| 10 | 安装包含 debug + release（[1]） | ✅ 完成 | ci.yml 两个 `upload-artifact`（`lxplayer-release-$sha` / `lxplayer-debug-$sha`） |
| 11 | 中间不要打扰用户（[1]） | ✅ 过程性，符合 | — |
| 12 | 登录界面太简单，找参考项目改好看（[25]） | ❌ **被重写丢弃** | 用户提需求后确实做了：`127be26 feat: redesign the login screen`(2026-09-10 10:20) + `LoginScreenTest.kt`(273 行) + `714599c`/`0939245`/`9ea50dd`（断言忙碌态、锁字段）。这些在 `702c545` **全部删除**。现在跑的是 CyreneMusic 自带的 `AuthPage`（`mobile_setup_page.dart:581`）/`FluentAuthPage`（`desktop_setup_page.dart:912`）——与上游 diff 只有 1 行品牌字符串（`auth_page.dart:265`）。即：**当前登录页 = CyreneMusic 的登录页**，符合度是「因为它就是」，不是「按参考做的」 |
| 13 | 云构建的验证能力：截图 / 风格断言（[13][15][23] Stop hook 反复追） | 🟡 有渲染级断言，无任何视觉产物 | 重写删掉 22 个 Kotlin 测试（含 `ScreenshotTest.kt`276 行、`ComponentGeometryTest.kt`257、`StyleGeometryTest.kt`286、`ShadowAndGlassTest.kt`241、`TypographyAndShapeTest.kt`147、`LxColorsTest.kt`、`LoginScreenTest.kt`）。现在只剩 `flutter test`：3 个文件 34 个用例，其中 `style_geometry_test.dart`(9) 与 `lyric_highlight_test.dart`(6) 是**真的 pump widget 后量几何/字号的渲染级断言**（这是对删掉的 Robolectric 那套的部分替代）。**没有截图、没有 golden、没有模拟器渲染**。`.shots/` 目录为空；CI 无相关步骤 ⚠️ 其中 `lyric_highlight_test` 钉的是 App 不渲染的组件，见 §3 |

> 备注（供纠偏）：README 第 49-52 行「21 个 Kotlin 测试被删、Dart 版还没有、风格没有任何自动化证据」**已过期**——`9f5ceae`/`d6eacb4` 之后已补了 3 个 Dart 测试文件。另外被删的 Kotlin 测试文件实为 **22 个**（README 与旧调研写的 21 偏少 1）。

---

## 2. 参考项目差距分析

### 2.1 Hyacine-music（`Ruoxi-TH/Hyacine-music`，MIT，TypeScript/React Native）

已抓取 `app/(tabs)/index.tsx`（14 156 B）逐行核对，参考实现的机制与 LxPlayer 的复刻度如下：

| 机制 | Hyacine 实测（行号） | LxPlayer | 判定 |
| --- | --- | --- | --- |
| 手势 | `Gesture.Pan()`，`activeOffsetX([-12,12])`、`failOffsetY([-24,24])`（:192-195） | `SwipeGesturePolicy` 12/24/36（swipe_recommend_card.dart:32-34） | ✅ 一致 |
| 提交 | 在 **`onEnd`** 里判 `|translationX| >= 36`（:196-197） | 在 **`onHorizontalDragUpdate`** 里一旦累计 ≥36 立即提交（:232-236） | ❌ **手感差异**：Hyacine 松手才换卡；LxPlayer 拖过 36 就已换，之后拖回来也回不去 |
| 是否切歌 | 播放中曲目在列表里才 `skipTrack(±1)`，`songs.some(s => s.id === currentTrack.id)`（:182-191） | `home_for_you_tab.dart:86-101`，同样按 id 判定 | ✅ 一致 |
| 入场动画 | 260ms，`translateX = dir*40 → 0` + opacity 0→1（:65, :210） | 260ms + 同方向 40dp（:37-40, :238-252） | ✅ 一致 |
| 卡片 | `ThemedCard` radius 28、内 `p-5`、`min-h-48`（:209-211） | `Container` radius 28 + `padding: 20` + `minHeight: 192`（:207-212, :282） | ✅ 一致 |
| 三层扇形 | 112×144 r24 right1 top9 op.35 rot12；120×160 r24 right18 top4 op.65 rot5；128×176 right36 top0 rot-4；前层阴影 `#17212d` .22 / r14 / (0,8)（:218） | 同值（:95-127, :385-421） | ✅ 数值级一致 |
| 主色 | 眼标/播放键用 accent，卡片/按钮是 **LiquidControlSurface 液态玻璃**（:203, :221） | 卡片是实心 `surfaceContainerHigh`，播放键是 Material `FilledButton.icon`（:207-211, :326-334） | ❌ **质感差异**：LxPlayer 没有复用底座的玻璃组件，退化成实心卡 + 实心按钮 |
| 播放键文案 | 正在播放时显示「正在播放…」而非「▶ 播放推荐」（:221） | 恒定「播放」+ 图标，无状态区分（:326-334） | ❌ 缺 |
| 卡片下方列表 | `songs.slice(1)` 竖向列表，跳过已在卡里展示的第 0 首（:227-228） | 移动端同时渲染 `SwipeRecommendCard`(:292) **和** `MobileDailyRecommendCard`(:299)，同一批 `dailySongs` 出现两次 | ❌ **重复入口**（`6e3dcc6` 只修了 `charts_tab`，没修 `home_for_you_tab`） |

### 2.2 CyreneMusic（`moraxs/CyreneMusic`，Dart，437★，无 license 文件）

逐字节比对结果（可复现）：

| 项 | 数量 | 说明 |
| --- | --- | --- |
| 与上游完全相同 | **208** | — |
| 仅品牌差异 | **39** | 抽样核对：`login_page.dart` 只差 1 行（`Cyrene Music`→`LxPlayer`）；`auth_page.dart` 只差 1 行（:265）；`auth_service.dart` 只差 3 处网页标题文案 |
| 改名 | 1 | `cyrene_config_service.dart` → `lx_config_service.dart`（magic number 改 `"LXPL"`） |
| LxPlayer 新增 | 3 | `home_page/swipe_recommend_card.dart`、`models/netease_song_mapper.dart`、`services/lx_config_service.dart` |

结论：**「CyreneMusic 有而 LxPlayer 没有的界面/动画」= 0（文件层面）**。相反方向才是问题——LxPlayer 继承了底座**全部**能力，包括原设计规格明确「不做」的第三方音源解析、下载管理器、Android 悬浮歌词、桌面端，把原规格废弃了（README:35-36 已承认）。

值得单列的两个连带问题：
- `app/lib/services/README.md` 是**上游文档原样残留**，教人 `import 'package:cyrene_music/...'` 并指向 `http://127.0.0.1:4055` 的 OmniParse 后端说明——与当前代码不符。
- `CacheService._getCacheFilePath` 用 `.lxcfg` 作为**音频缓存**扩展名（`cache_service.dart:210`），而 `LxConfigService` 用 `.lxcfg` 作为**音源配置**格式（`lx_config_service.dart:48`）。同名不同物，容易混淆（功能上不冲突，目录不同）。

### 2.3 CyreneMusic-tauri（`ChuxinNeko/CyreneMusic-tauri`）

- 抓取结果：TypeScript，35★，无 license。仓库里**没有**任何文件被 LxPlayer 引用 —— 该参考**完全未落地**。
- 原设计规格里移植自它的设计语言（`docs/superpowers/specs/...design.md:5.1/5.2`）在 Flutter 版里**也不存在**：LxPlayer 走 `ThemeManager` 在 Material / Fluent / Cupertino / Oculus 四套框架间运行时切换（`app/lib/main.dart:445-548`），没有「中性灰 shadcn 色板 + 单一品牌色」这一层；配色随主题与封面走。
- 因此「UI 参考 tauri 那版」这项：**参考对象被换掉了**，不是做得不好。
- 无法确认：tauri 仓库 README 明写无截图，配色/排版结论来自其源码 token（沿用 2026-09-09 调研，已核过关键值），未在本轮重新逐值复核。

### 2.4 NeriPlayer（`cwuom/NeriPlayer`，Kotlin，GPL-3.0，3 350★）

| NeriPlayer 播放链路要点 | LxPlayer 现状 | 证据 |
| --- | --- | --- |
| 先解析、后 `setMediaItem`，不在数据源里解析 | ✅ 等价 | `player_service.dart:770/853/975`：解析得到 url 后才 `open(mk.Media(url))` |
| 单调递增 token 作废旧请求 | 🟡 用「当前 track id 相等」代替 | `player_service.dart:454, 461`（`_currentTrack?.id == track.id`）；`home_for_you_tab.dart:73, 93`。没有全局 token，理论上存在两次快速切歌的竞态窗口 |
| `setCustomCacheKey` 与轮换签名 URL 解耦 | ✅ 更强（按 songId 而非 URL） | `cache_service.dart:205-207` |
| 按 URL 设 `wakeMode` | ❌ 无（media_kit 无该 API） | 全库无 `wakeMode` |
| 音频专用 `LoadControl` + `setBackBuffer(60s)` | ❌ 无（media_kit/mpv 用自己的缓冲策略） | 未做等价配置 |
| 队列在播放器侧、ExoPlayer 单 item | ✅ 等价 | `playlist_queue_service.dart:24`（`List<Track> _queue`），player_service 单 `mk.Media` |
| 随机 = 物理打乱 + 快照还原，非 shuffleOrder | ✅ 等价实现 | `playlist_queue_service.dart:30-31,137-158`（Fisher-Yates 索引序列 + 清空还原） |
| 倍速 / 变调 `PlaybackParameters` | ❌ **无倍速功能** | 全库 `grep "setRate\|playbackRate\|倍速"` 无命中 |
| 睡眠定时 | ✅ 有（更全：含定时到点/播完当前） | `sleep_timer_service.dart:65-179` |
| 均衡器 | ✅ 真实现（mpv `af` 滤镜，10 段） | `player_service.dart:2695-2740` |
| 音量归一 / 淡入淡出 / 真交叉淡化 / USB 独占 | ❌ 无（原规格也列为不做） | — |
| 无 gapless（单 item 的代价） | 同样无 | — |

---

## 3. 功能可用性盘点

判定基准：**能跑通到可用**（前提条件写清）/ **存疑**（有前提或依赖外部、未验证）/ **不能用或只是壳**。证据均为文件:行。

### 3.1 能用

| 功能 | 证据 | 前提 |
| --- | --- | --- |
| 首页滑动推荐卡 | `swipe_recommend_card.dart` 全套；2 个测试文件覆盖几何与阈值 | 有推荐数据即可，纯前端 |
| 本地音乐扫描/播放 | `local_library_service.dart:228`、`local_page.dart:265/321/422`（`pickAndScanFolder`） | 依赖 SAF 文件选择器（见 3.2 权限条目） |
| 播放核心（在线/本地/缓存分支） | `player_service.dart:369-1074`（media_kit + audioplayers 双路） | 在线需先配音源 |
| 队列 / 上一首下一首 / 循环 / 随机 | `playlist_queue_service.dart:58,100,137-189`、`playback_mode_service.dart:5-11` | — |
| 歌词解析（含 YRC 逐字）+ 卡拉OK/流体云歌词渲染 | `utils/lyric_parser.dart`；`mobile_player_karaoke_lyric.dart`、`mobile_player_fluid_cloud_lyric_panel.dart:38` | — |
| 均衡器 | `player_service.dart:2695-2740`（mpv `af` 属性） | 仅 media_kit 路径生效 |
| 睡眠定时 | `sleep_timer_service.dart:65-179` | — |
| 系统媒体通知/控制 | `audio_service` + `android_media_notification_service.dart`、`native_smtc_service.dart`(桌面) | Android 需通知权限（main.dart:280 已请求） |
| 下载 | `download_service.dart` | 需配置音源 |
| 桌面端托盘 / 迷你播放器窗 / 桌面歌词 | `tray_service.dart`、`mini_player_window_service.dart`、`desktop_lyric_service.dart`（main.dart:312） | **仅 Windows 分支被 main.dart 显式初始化**；macOS/Linux 未验证 |
| CI 签名一致性校验 | `.github/workflows/ci.yml` | run#63 绿 |

### 3.2 存疑

| 功能 | 疑点 | 证据 |
| --- | --- | --- |
| **账号注册/登录** | 能通，但连的是 **CyreneMusic 的第三方后端** `music.nekofun.top`（实测 root 200、`/auth/login` 422、`/recommend/songs` 401），不是 LxPlayer 自研后端。用户数据落在别人的服务上 | `url_service.dart:17`、`auth_service.dart:301,357,606,655,815,850,923` |
| **自研 Go 后端的注册/登录/多设备同步** | 客户端**零调用** → 在 App 里走不到，等于「有后端没前端」 | `grep -rn "api/v1" app/lib` 无命中；`server/main.go:99-112` |
| **在线音源（网易云/QQ/酷狗/酷我/B站/Apple）** | 出厂**无内置音源**，必须用户自行导入 LX 洛雪 / TuneHub / OmniParse 音源；`isConfigured` 为假时在线播放直接报「音源未配置」并弹框 | `app/README.md`（上游原文：「已经移除了内置音源，您需要先导入音源才能正常使用」）；`audio_source_service.dart:322,128-160`；`player_service.dart:388-403` |
| **首页「为你推荐」** | 双前提：已登录 **且** 已配音源；数据来自第三方 `music.nekofun.top/recommend/*`（无鉴权会 401） | `home_for_you_tab.dart:173-194`（未登录显示登录提示、未配音源显示音源提示）、`:120-129` |
| **LX 音源脚本运行时** | 靠 `flutter_inappwebview` 起 WebView 跑 JS（`lx_music_runtime_service.dart:4,722`）。桌面端 WebView 可用性、Android WebView 版本兼容性**未验证** | 未跑过真机 |
| **本地音乐的媒体权限** | manifest 声明了 `READ_MEDIA_AUDIO` / `MANAGE_EXTERNAL_STORAGE`，但 `PermissionService` **只请求通知与电池优化**，没有运行时请求媒体权限；目前只能靠 SAF 选择器。另：`MANAGE_EXTERNAL_STORAGE` 有 Play 商店上架风险 | `AndroidManifest.xml:24-32`；`permission_service.dart:12,56,114-129` |
| **Android 悬浮歌词** | 需 `SYSTEM_ALERT_WINDOW` 运行时授权，`PermissionService` 未请求 | `AndroidManifest.xml:18`；`permission_service.dart` 无对应项 |
| **缓存** | 功能齐（含 XOR 加密、md5 校验），但**默认关闭**（`_cacheEnabled = false`），需用户手动开；不看代码会以为「缓存不生效」 | `cache_service.dart:125,165-166` |
| **桌面端整体（Win/macOS/Linux）** | 不在 CI；Windows 安装信息/清单/updater 仍是 Cyrene Music；**无法确认能否构建运行（原因：本机无 Flutter 与桌面工具链，CI 仅构建 Android）** | `Runner.rc:92-98`、`runner.exe.manifest:6-8`、`ci.yml` 只有 Android job |

### 3.3 不能用 / 只是壳

| 项 | 证据 |
| --- | --- |
| 自研后端的账号与同步链路（App 侧） | 无任何调用点（见 3.2 第 2 行） |
| **登录三件套是死代码**：`login_page.dart`(243 行)、`register_page.dart`(421)、`forgot_password_page.dart`(324) | 全库无引用（`login_page.dart` 自己 import 了另两个，但没人 import 它）；真正渲染的是 `AuthPage`（`mobile_setup_page.dart:581`） |
| `layouts/cupertino_main_layout.dart` | 无任何 import（main.dart 的 Cupertino 分支走 `MobileAppGate`） |
| `pages/playlists_page.dart`、`pages/profile_page.dart` | 无任何 import |
| `services/navigator_service.dart` | 无任何 import |
| `pages/mobile_player_components/mobile_player_current_lyric.dart` | 生产代码无 import，**只有 `test/lyric_highlight_test.dart` 在引用** |

> ⚠️ **最后一条是本次调研最值得立刻修的问题**：`lyric_highlight_test.dart` 的注释写着「当前歌词窗口的渲染级断言」，但它断言的是 `MobilePlayerCurrentLyric`，而 App 真正渲染的是 `MobilePlayerKaraokeLyric`（`mobile_player_classic_layout.dart:104`）或 `MobilePlayerFluidCloudLyricsPanel`（`mobile_player_fluid_cloud_layout.dart:840,961`）。也就是说，**这个测试给了「歌词高亮有自动化证据」的假信心**——把它正在验证的组件删掉，测试仍然是绿的。

---

## 4. 给下一步的三条建议（按优先级）

1. **先决定「底座路线」还是「原规格路线」**。现在的状态是两条路各走了一半：拿了 CyreneMusic 的全部能力（含第三方音源），却留着描述 Kotlin 版、且宣称这些能力「不做」的 `docs/superpowers/*`。二者必须对齐，否则后续每一项验收都无参照。PR #3 在合并前应先回答这个问题。
2. **修 `lyric_highlight_test` 的假信心**：让它断言真正上屏的歌词组件，或者把 `MobilePlayerCurrentLyric` 接进播放页。同理，`style_geometry_test` 钉的是 `SwipeRecommendCard`——这个确实上屏（`home_for_you_tab.dart:292`），没问题；但值得补一条断言证明「卡片真的挂在首页」。
3. **补上唯一缺失的「视觉证据」**：CI 目前只有编译 + 单测 + 签名。用户三轮 Stop hook 追的就是这一项。低成本做法是在 CI 里跑 `flutter test` 的 golden 或用 `flutter drive` 截图并按 sha 存档，至少让「风格做出来没有」有机器产物可查，而不是靠人眼。

---

### 附：核验命令（可复现）

```bash
# 1) 底座逐字节比对（208/248 相同）
python - <<'EOF'
import json,os,subprocess,urllib.request
req=urllib.request.Request("https://api.github.com/repos/moraxs/CyreneMusic/git/trees/main?recursive=1",headers={'User-Agent':'curl'})
d=json.load(urllib.request.urlopen(req,timeout=60))
cy={t['path']:t['sha'] for t in d['tree'] if t['path'].startswith('lib/') and t['path'].endswith('.dart')}
same=diff=absent=0
for p,sha in cy.items():
    lp=os.path.join('app',p)
    if not os.path.exists(lp): absent+=1; continue
    s=subprocess.run(['git','hash-object',lp],capture_output=True,text=True).stdout.strip()
    same+= (s==sha); diff+= (s!=sha)
print('identical',same,'modified',diff,'renamed',absent)
EOF

# 2) 客户端是否调用自研后端（应为空）
grep -rn "api/v1\|:8080\|sync/snapshot" app/lib app/android

# 3) 无引用文件（死代码）
#  见正文 §3.3；对每个候选执行：grep -rn "<文件名>" app/lib app/test
```
