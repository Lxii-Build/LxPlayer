# 视觉基线（golden）

这个目录里的测试**不属于**默认单测：它们在 `app/test_visual/`，而不是 `app/test/`，
所以 `flutter test`（无参数）不会跑到它们，既有的 `android` CI job 完全不受影响。

它们由独立的 CI job `visual` 运行：

```bash
cd app
flutter test test_visual --update-goldens
```

渲染的界面（都用固定画布尺寸，保证可重复）：

| 文件 | 基线图 | 说明 |
| --- | --- | --- |
| `visual_surface_test.dart` | `goldens/lx_surface_solid.png` | `LxSurface` 实心分支（Material 宿主） |
| `visual_surface_test.dart` | `goldens/lx_surface_fluent.png` | `LxSurface` Fluent 分支（FluentApp 宿主） |
| `visual_surface_glass_test.dart` | `goldens/lx_surface_glass.png` | `LxSurface` 玻璃分支（尽力而为，见下） |
| `visual_recommend_test.dart` | `goldens/fan_cover_stack_empty.png` | 扇形封面三层堆叠（空封面占位） |
| `visual_recommend_test.dart` | `goldens/recommend_card.png` | 首页推荐卡整体 |
| `visual_lyric_test.dart` | `goldens/lyric_window.png` | 当前歌词窗口 |

## 这些图能证明什么 / 不能证明什么

- **能证明**：本仓库当前代码在固定尺寸下的**渲染结果**，作为视觉变更的人工审阅依据。
- **不能证明**：它们**不代表**「和参考项目长得一样」。golden 只能对照**本仓库自己的历史基线**，
  跨项目比对没有意义——判定「是否还原参考交互」仍然要靠人看真机 + 参考实现。

## 已知限制

1. **文字渲染为方块**：测试环境不加载应用字体（`Microsoft YaHei`）与系统字体，
   截图里的中文/拉丁文字通常渲染成占位方块。这是 `flutter test` 的固有行为，
   **不要**为了「让字好看」往仓库塞大字体包。审阅时重点看**布局、间距、几何、配色**，
   不要以文字可读性为准。
2. **玻璃分支不等于真机像素**：`LxSurface` 的玻璃分支只在 Cupertino/Oculus 真机上命中，
   headless 主机触发不到（详见 `visual_surface_glass_test.dart` 顶部注释）。
   该图用同一套公共参数直接绘制，仅作为「当前玻璃参数长什么样」的参考。
3. **依赖 GPU / 环境**：不同机器/驱动可能产生像素差异。因此 CI job
   `continue-on-error: true`，且产物上传 `if-no-files-found: warn`——目的是**拿到可审阅的图**，
   而不是卡住流水线。

## 流程

首次运行由 `--update-goldens` 生成 PNG，作为构建产物（`lxplayer-visuals-<sha>`）上传。
**人工审阅通过后**再把需要的 PNG 提交入库；之后可以考虑把 CI 从
`--update-goldens` 切换为普通比对模式，从而真正卡住视觉回归。当前阶段**故意**不提交
初始 baseline，避免把未经审阅的像素当成既定事实。
