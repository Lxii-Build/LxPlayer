import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/lyric_line.dart';
import '../../services/playback_mode_service.dart';
import '../../services/player_service.dart';

/// 极简歌词流布局（minimal lyric-flow）。
///
/// 这是 `LyricStyle.defaultStyle` 在移动端与桌面端共用的新版播放页布局。
/// 结构自上而下**全部按可用高度比例切分**（不写死像素），因此任何屏幕比例下都成立：
///
/// ```text
/// ┌───────────────────────────────┐  ← 封面区（默认占上半屏，顶部可含返回/窗口按钮）
/// │        专辑封面（铺满）          │
/// │  ░░░ 封面底边 ShaderMask 渐隐 ░░░ │  ← 封面底边直接「溶解」进背景，
/// │        歌名 / 歌手              │     文字叠在渐隐带上，与下方歌词区无缝相接
/// ├───────────────────────────────┤  ← 分界线不再是硬边，而是渐变过渡
/// │                               │
/// │        滚动歌词（铺满）          │  ← 由调用方注入的平台歌词面板，占满剩余空间
/// │                               │     直到屏幕底部（底部按手势区补内边距）
/// └───────────────────────────────┘
/// ```
///
/// 设计要点：
/// 1. **封面占上半屏**：[coverHeightFactor]（默认 0.5）乘以可用高度得到封面区高度，
///    用 `LayoutBuilder` 的约束计算，而非写死像素。
/// 2. **封面与文字自然融合**：封面用 `ShaderMask` 让底边 alpha 由不透明渐隐到透明，
///    封面的下边缘不再有硬边，而是直接过渡到它背后的页面背景；歌名/歌手叠在这条渐隐带
///    上（外加一层半透明暗渐变保证文字可读）。这样得到的是「封面—文字—歌词」一条
///    连续的视觉流，而不是两块拼接的板。
/// 3. **歌词铺满下半屏到底部**：歌词区是 `Expanded`，从文字区下方一直延伸到底；
///    底部用 `MediaQuery.padding.bottom` 补内边距，文字不会被手势条压住，背景仍然铺到屏幕最底。
/// 4. **控制键默认全部隐藏**：切歌/播放/进度等不再常驻，改为**点击封面**弹出的底部操作面板
///    （见 [_showControlsSheet]），关闭后回到极简状态。
class MinimalLyricFlowLayout extends StatefulWidget {
  const MinimalLyricFlowLayout({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.lyricsPanel,
    this.showTranslation = true,
    this.coverHeightFactor = 0.5,
    this.topBar,
    this.onPlaylistPressed,
    this.onSleepTimerPressed,
    this.onTranslationToggle,
  });

  /// 当前歌曲的全部歌词行。
  final List<LyricLine> lyrics;

  /// 当前正在播放的歌词下标。
  final int currentLyricIndex;

  /// 歌词渲染面板（平台相关实现）：
  /// 移动端传 `MobilePlayerKaraokeLyric`，桌面端传 `PlayerKaraokeLyricsPanel`。
  /// 行高模型、高亮、译文、居中逻辑都在面板内部，本布局只负责给它一块「铺满到底」的空间。
  final Widget lyricsPanel;

  /// 是否显示译文（仅用于操作面板里的译文开关状态）。
  final bool showTranslation;

  /// 封面区占可用高度的比例，默认上半屏（0.5）。
  final double coverHeightFactor;

  /// 封面区顶部的浮层（返回按钮 / 窗口控制等），可选。
  final Widget? topBar;

  /// 操作面板里的「播放队列 / 歌单」入口（移动端与桌面端实现不同）。
  final VoidCallback? onPlaylistPressed;

  /// 操作面板里的「睡眠定时器」入口。
  final VoidCallback? onSleepTimerPressed;

  /// 操作面板里的「译文开关」。
  final VoidCallback? onTranslationToggle;

  @override
  State<MinimalLyricFlowLayout> createState() => _MinimalLyricFlowLayoutState();
}

class _MinimalLyricFlowLayoutState extends State<MinimalLyricFlowLayout> {
  @override
  Widget build(BuildContext context) {
    final EdgeInsets insets = MediaQuery.of(context).padding;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableHeight = constraints.maxHeight;
        final double availableWidth = constraints.maxWidth;

        // 封面高度 = 可用高度 × 比例。不用写死像素，任何屏幕比例下「上半屏」都成立；
        // 同时给一个上下限，避免超矮/超高窗口把比例拉得离谱。
        final double coverHeight =
            (availableHeight * widget.coverHeightFactor)
                .clamp(160.0, availableHeight * 0.68);

        return Column(
          children: <Widget>[
            SizedBox(
              height: coverHeight,
              child: _buildCoverStage(context, availableWidth, coverHeight, insets),
            ),
            // 歌词区：从文字区下方一直铺到屏幕最底部。
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  // 底部手势区：给文字补内边距，别被手势条压住。
                  bottom: insets.bottom + 8,
                ),
                child: widget.lyricsPanel,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 封面区：封面 + 底边渐隐 + 叠在渐隐带上的歌曲信息 + 顶部浮层。
  Widget _buildCoverStage(
    BuildContext context,
    double width,
    double height,
    EdgeInsets insets,
  ) {
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (BuildContext context, Color? themeColor, Widget? _) {
        return AnimatedBuilder(
          animation: PlayerService(),
          builder: (BuildContext context, Widget? __) {
            final PlayerService player = PlayerService();
            final String imageUrl = player.currentCoverUrl ??
                player.currentSong?.pic ??
                player.currentTrack?.picUrl ??
                '';
            final Color theme = themeColor ?? (Colors.grey[700] ?? const Color(0xFF424242));

            // 触控/点击整块封面区都唤出操作面板，比「只点图片正中央」更宽容。
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showControlsSheet(context),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // 1) 封面本体（底边已用 ShaderMask 渐隐，见 _buildCoverImage）
                  _buildCoverImage(imageUrl, width, height, theme),

                  // 2) 底部暗渐变：让歌名/歌手在封面渐隐区上依然可读。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: height * 0.6,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.transparent,
                              Colors.black.withOpacity(0.12),
                              Colors.black.withOpacity(0.55),
                            ],
                            stops: const <double>[0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 3) 歌曲信息：直接叠在封面的渐隐带上，成为「封面 → 文字 → 歌词」的中间环。
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 16,
                    child: _buildSongInfo(player),
                  ),

                  // 4) 顶部浮层（返回/窗口按钮），加一层极浅的顶部暗渐变保证图标可读。
                  if (widget.topBar != null) ...<Widget>[
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: insets.top + 64,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.black.withOpacity(0.28),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: Padding(
                        padding: EdgeInsets.only(top: insets.top),
                        child: widget.topBar!,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 封面图片。
  ///
  /// 「融合」的关键就在这里：用 `ShaderMask`（`BlendMode.dstIn`）把封面**自身**的下边缘
  /// alpha 从不透明渐隐到透明。于是封面底边不再形成一条硬边界，而是直接过渡到它背后的
  /// 页面背景 —— 无论背景是主题色渐变还是模糊封面，都能无缝衔接。
  ///
  /// 宽屏（桌面大窗口）下不把正方形封面拉成横幅：改为居中的正方形（边长 = 封面区高度），
  /// 两侧留白由页面背景填充，避免桌面端比例失真。
  Widget _buildCoverImage(
    String imageUrl,
    double width,
    double height,
    Color theme,
  ) {
    Widget raw;
    if (imageUrl.isEmpty) {
      // 无封面：用主题色的柔和渐变作为占位，保持整体一致。
      raw = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.lerp(theme, Colors.black, 0.25) ?? theme,
              Color.lerp(theme, Colors.black, 0.6) ?? theme,
            ],
          ),
        ),
        child: const Center(
          child: Icon(Icons.music_note_rounded, size: 72, color: Colors.white24),
        ),
      );
    } else {
      raw = _buildCoverImageContent(imageUrl, theme);
    }

    final bool ultraWide = width > height * 1.3;
    final Widget sized = ultraWide
        ? Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(width: height, height: height, child: raw),
            ),
          )
        : raw;

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        // 上段完全保留，最后 ~38% 渐隐到透明 —— 封面在这里「溶解」。
        colors: <Color>[Colors.white, Colors.white, Colors.transparent],
        stops: <double>[0.0, 0.62, 1.0],
      ).createShader(bounds),
      child: sized,
    );
  }

  /// 渲染封面图片内容（支持预取的 ImageProvider、网络图、本地文件）。
  Widget _buildCoverImageContent(String imageUrl, Color theme) {
    final ImageProvider? provider = PlayerService().currentCoverImageProvider;
    if (provider != null) {
      return Image(image: provider, fit: BoxFit.cover);
    }

    final bool isNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    if (!isNetwork) {
      return Image.file(
        File(imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            _buildCoverPlaceholder(theme),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (BuildContext context, String url) =>
          _buildCoverPlaceholder(theme),
      errorWidget:
          (BuildContext context, String url, Object error) =>
              _buildCoverPlaceholder(theme),
    );
  }

  Widget _buildCoverPlaceholder(Color theme) {
    return ColoredBox(
      color: Color.lerp(theme, Colors.black, 0.4) ?? theme,
      child: const Center(
        child: Icon(Icons.music_note_rounded, size: 64, color: Colors.white24),
      ),
    );
  }

  /// 歌名 + 歌手，居中叠在封面渐隐带上。
  Widget _buildSongInfo(PlayerService player) {
    final String title =
        player.currentSong?.name ?? player.currentTrack?.name ?? '未知歌曲';
    final String artist =
        player.currentSong?.arName ?? player.currentTrack?.artists ?? '未知艺术家';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              shadows: <Shadow>[
                Shadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 2)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            artist,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 点击封面后弹出的操作面板（底部弹层，可关闭）。
  void _showControlsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _MinimalControlsSheet(
        showTranslation: widget.showTranslation,
        onPlaylistPressed: widget.onPlaylistPressed == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                widget.onPlaylistPressed!();
              },
        onSleepTimerPressed: widget.onSleepTimerPressed == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                widget.onSleepTimerPressed!();
              },
        onTranslationToggle: widget.onTranslationToggle,
      ),
    );
  }
}

/// 极简操作面板：平时隐藏的所有控制集中在这里。
///
/// 包含：进度条 + 时间、上一首/播放暂停/下一首、播放模式、音量，以及可选的
/// 播放队列、睡眠定时器、译文开关。弹层可下拉/点遮罩/点右上角关闭。
class _MinimalControlsSheet extends StatefulWidget {
  const _MinimalControlsSheet({
    required this.showTranslation,
    this.onPlaylistPressed,
    this.onSleepTimerPressed,
    this.onTranslationToggle,
  });

  final bool showTranslation;
  final VoidCallback? onPlaylistPressed;
  final VoidCallback? onSleepTimerPressed;
  final VoidCallback? onTranslationToggle;

  @override
  State<_MinimalControlsSheet> createState() => _MinimalControlsSheetState();
}

class _MinimalControlsSheetState extends State<_MinimalControlsSheet> {
  late double _volume;

  @override
  void initState() {
    super.initState();
    _volume = PlayerService().volume;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color sheetColor =
        ThemeData.estimateBrightnessForColor(scheme.surface) == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : scheme.surface;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        decoration: BoxDecoration(
          color: sheetColor,
          borderRadius: BorderRadius.circular(28),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // 拖动指示条 + 关闭
            Row(
              children: <Widget>[
                Expanded(
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: scheme.onSurface.withOpacity(0.7)),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 进度条 + 时间
            _buildProgress(scheme),

            const SizedBox(height: 8),

            // 上一首 / 播放暂停 / 下一首
            _buildTransport(scheme),

            const SizedBox(height: 8),

            // 播放模式 + 音量
            _buildVolume(scheme),

            const SizedBox(height: 8),

            // 次要入口：播放模式、播放队列、睡眠定时器、译文
            _buildSecondaryActions(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(ColorScheme scheme) {
    return AnimatedBuilder(
      animation: PlayerService().positionNotifier,
      builder: (BuildContext context, Widget? _) {
        final PlayerService player = PlayerService();
        final Duration position = player.positionNotifier.value;
        final Duration duration = player.duration;
        final double max = duration.inMilliseconds.toDouble();
        final double value =
            position.inMilliseconds.toDouble().clamp(0.0, max > 0 ? max : 0.0);

        return Column(
          children: <Widget>[
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: scheme.primary,
                inactiveTrackColor: scheme.onSurface.withOpacity(0.18),
                thumbColor: scheme.primary,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0,
                onChanged: max > 0
                    ? (double v) =>
                        player.seek(Duration(milliseconds: (v * max).toInt()))
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    _formatDuration(position),
                    style: TextStyle(
                      color: scheme.onSurface.withOpacity(0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      color: scheme.onSurface.withOpacity(0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTransport(ColorScheme scheme) {
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (BuildContext context, Widget? _) {
        final PlayerService player = PlayerService();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton(
              iconSize: 40,
              color: scheme.onSurface,
              icon: const Icon(Icons.skip_previous_rounded),
              onPressed: player.hasPrevious ? player.playPrevious : null,
              tooltip: '上一首',
            ),
            const SizedBox(width: 20),
            Container(
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                iconSize: 40,
                padding: const EdgeInsets.all(14),
                color: scheme.onPrimary,
                icon: Icon(
                  player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                onPressed: player.togglePlayPause,
                tooltip: player.isPlaying ? '暂停' : '播放',
              ),
            ),
            const SizedBox(width: 20),
            IconButton(
              iconSize: 40,
              color: scheme.onSurface,
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: player.hasNext ? player.playNext : null,
              tooltip: '下一首',
            ),
          ],
        );
      },
    );
  }

  Widget _buildVolume(ColorScheme scheme) {
    return Row(
      children: <Widget>[
        Icon(Icons.volume_down_rounded, color: scheme.onSurface.withOpacity(0.7), size: 22),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: scheme.onSurface.withOpacity(0.7),
              inactiveTrackColor: scheme.onSurface.withOpacity(0.18),
              thumbColor: scheme.onSurface,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            ),
            child: Slider(
              value: _volume.clamp(0.0, 1.0),
              onChanged: (double v) {
                setState(() => _volume = v);
                PlayerService().setVolume(v);
              },
            ),
          ),
        ),
        Icon(Icons.volume_up_rounded, color: scheme.onSurface.withOpacity(0.7), size: 22),
      ],
    );
  }

  Widget _buildSecondaryActions(ColorScheme scheme) {
    return AnimatedBuilder(
      animation: PlaybackModeService(),
      builder: (BuildContext context, Widget? _) {
        final PlaybackMode mode = PlaybackModeService().currentMode;
        final IconData modeIcon;
        final String modeLabel;
        switch (mode) {
          case PlaybackMode.sequential:
            modeIcon = Icons.repeat_rounded;
            modeLabel = '顺序播放';
            break;
          case PlaybackMode.repeatOne:
            modeIcon = Icons.repeat_one_rounded;
            modeLabel = '单曲循环';
            break;
          case PlaybackMode.shuffle:
            modeIcon = Icons.shuffle_rounded;
            modeLabel = '随机播放';
            break;
        }

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _actionButton(
              scheme: scheme,
              icon: modeIcon,
              label: modeLabel,
              onTap: () => PlaybackModeService().toggleMode(),
            ),
            if (widget.onPlaylistPressed != null)
              _actionButton(
                scheme: scheme,
                icon: Icons.queue_music_rounded,
                label: '播放队列',
                onTap: widget.onPlaylistPressed!,
              ),
            if (widget.onSleepTimerPressed != null)
              _actionButton(
                scheme: scheme,
                icon: Icons.schedule_rounded,
                label: '定时关闭',
                onTap: widget.onSleepTimerPressed!,
              ),
            if (widget.onTranslationToggle != null)
              _actionButton(
                scheme: scheme,
                icon: widget.showTranslation
                    ? Icons.subtitles_rounded
                    : Icons.subtitles_off_rounded,
                label: widget.showTranslation ? '译文开' : '译文关',
                onTap: widget.onTranslationToggle!,
              ),
          ],
        );
      },
    );
  }

  Widget _actionButton({
    required ColorScheme scheme,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.onSurface.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: scheme.onSurface.withOpacity(0.85)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: scheme.onSurface.withOpacity(0.85),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String two(int n) => n.toString().padLeft(2, '0');
    final String minutes = two(duration.inMinutes.remainder(60));
    final String seconds = two(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
