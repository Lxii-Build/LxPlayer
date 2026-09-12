import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../../services/player_service.dart';
import '../../services/lyric_font_service.dart';
import '../../models/lyric_line.dart';
import 'lyric_window_metrics.dart';

/// 桌面端卡拉OK样式歌词面板
///
/// 显示窗口内的歌词（默认最多 8 行），当前歌词位于窗口靠中位置，支持从左到右的
/// 填充效果、上下滚动动画和鼠标滚轮跳转。
///
/// 行高模型由共享的 [resolveLyricWindowMetrics] 推导：行数是**从内容需要的行高反推**
/// 出来的，而不是把容器高度硬切八等分。开启译文时一行要装「原文 + 间距 + 译文」，
/// 装不下 8 行就少显示几行，从而保证译文完整可见、永不溢出。
class PlayerKaraokeLyricsPanel extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;

  const PlayerKaraokeLyricsPanel({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
  });

  @override
  State<PlayerKaraokeLyricsPanel> createState() => _PlayerKaraokeLyricsPanelState();
}

class _PlayerKaraokeLyricsPanelState extends State<PlayerKaraokeLyricsPanel> with TickerProviderStateMixin {
  /// 排版参数。与普通歌词面板共用同一份（见 lyric_window_metrics.dart），测量与渲染同源。
  static const LyricLayoutSpec _spec = LyricLayoutSpec.standard;

  int? _selectedLyricIndex; // 手动选择的歌词索引
  bool _isManualMode = false; // 是否处于手动模式
  Timer? _autoResetTimer; // 自动回退定时器
  AnimationController? _timeCapsuleAnimationController;
  Animation<double>? _timeCapsuleFadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    // 监听字体变化，实时刷新
    LyricFontService().addListener(_onFontChanged);
  }

  @override
  void dispose() {
    LyricFontService().removeListener(_onFontChanged);
    _autoResetTimer?.cancel();
    _timeCapsuleAnimationController?.dispose();
    super.dispose();
  }

  /// 字体变化回调
  void _onFontChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 初始化动画
  void _initializeAnimations() {
    _timeCapsuleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _timeCapsuleFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _timeCapsuleAnimationController!,
      curve: Curves.easeInOut,
    ));
  }

  /// 开始手动模式
  void _startManualMode(int lyricIndex) {
    setState(() {
      _isManualMode = true;
      _selectedLyricIndex = lyricIndex;
    });

    _timeCapsuleAnimationController?.forward();
    _resetAutoTimer();
  }

  /// 重置自动回退定时器
  void _resetAutoTimer() {
    _autoResetTimer?.cancel();
    _autoResetTimer = Timer(const Duration(seconds: 5), _exitManualMode);
  }

  /// 退出手动模式
  void _exitManualMode() {
    if (!mounted) return;

    setState(() {
      _isManualMode = false;
      _selectedLyricIndex = null;
    });

    _timeCapsuleAnimationController?.reverse();
    _autoResetTimer?.cancel();
  }

  /// 跳转到选中的歌词时间
  void _seekToSelectedLyric() {
    if (_selectedLyricIndex != null &&
        _selectedLyricIndex! >= 0 &&
        _selectedLyricIndex! < widget.lyrics.length) {

      final selectedLyric = widget.lyrics[_selectedLyricIndex!];
      if (selectedLyric.startTime != null) {
        PlayerService().seek(selectedLyric.startTime!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已跳转到: ${selectedLyric.text}'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }

    _exitManualMode();
  }

  /// 处理鼠标滚轮滑动
  void _handleScrollEvent(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (widget.lyrics.isEmpty) return;

    final scrollDelta = event.scrollDelta.dy;
    final currentIndex = _selectedLyricIndex ?? widget.currentLyricIndex;
    int newIndex = currentIndex;

    if (scrollDelta > 0) {
      // 向下滚动，选择下一句歌词
      newIndex = (currentIndex + 1).clamp(0, widget.lyrics.length - 1);
    } else if (scrollDelta < 0) {
      // 向上滚动，选择上一句歌词
      newIndex = (currentIndex - 1).clamp(0, widget.lyrics.length - 1);
    }

    if (newIndex != currentIndex) {
      if (!_isManualMode) {
        _startManualMode(newIndex);
      } else {
        setState(() {
          _selectedLyricIndex = newIndex;
        });
        _resetAutoTimer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Stack(
        children: [
          // 主要歌词区域
          Listener(
            onPointerSignal: _handleScrollEvent,
            child: widget.lyrics.isEmpty
                ? _buildNoLyric()
                : _buildKaraokeLyricList(),
          ),

          // 时间胶囊组件（桌面端版本）
          if (_isManualMode && _selectedLyricIndex != null)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _buildDesktopTimeCapsule(),
            ),
        ],
      ),
    );
  }

  /// 构建无歌词提示
  Widget _buildNoLyric() {
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        final textColor = _getAdaptiveLyricColor(themeColor, false).withOpacity(0.5);
        return Center(
          child: Text(
            '暂无歌词',
            style: TextStyle(
              color: textColor,
              fontSize: 16,
            ),
          ),
        );
      },
    );
  }

  /// 这首歌在当前开关下是否真的会渲染译文。
  ///
  /// 用**整首歌**判断而不是逐行判断：行高预算若随窗口滑动而变，歌词块会上下抖动。
  bool get _hasTranslationContent => hasTranslationContent(
        lyrics: widget.lyrics,
        showTranslation: widget.showTranslation,
      );

  /// 构建卡拉OK样式歌词列表（当前歌词位于窗口靠中位置，丝滑滚动）。
  Widget _buildKaraokeLyricList() {
    // 使用 RepaintBoundary 隔离歌词区域的重绘
    return RepaintBoundary(
      child: ValueListenableBuilder<Color?>(
        valueListenable: PlayerService().themeColorNotifier,
        builder: (context, themeColor, child) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final double availableHeight = constraints.maxHeight;

              // 行数/行高从内容需要的行高反推，而不是把容器硬切八等分。
              final LyricWindowMetrics metrics = resolveLyricWindowMetrics(
                availableHeight: availableHeight,
                withTranslation: _hasTranslationContent,
                spec: _spec,
              );

              // 使用手动选择的索引或当前播放索引
              final int displayIndex =
                  _selectedLyricIndex ?? widget.currentLyricIndex;

              // 计算显示范围
              final int startIndex = displayIndex - metrics.currentLinePosition;

              // 生成要显示的歌词列表
              final List<Widget> lyricWidgets = <Widget>[
                for (int i = 0; i < metrics.visibleLines; i++)
                  _buildRow(
                    slot: i,
                    lyricIndex: startIndex + i,
                    displayIndex: displayIndex,
                    itemHeight: metrics.itemHeight,
                    themeColor: themeColor,
                  ),
              ];

              final Widget window = _buildAnimatedWindow(
                displayIndex: displayIndex,
                lyricWidgets: lyricWidgets,
              );

              // 高度无界时（父级不给约束）本就无从谈起「铺满」，直接按内容收缩；
              // 也不能套滚动视图，否则会命中「Vertical viewport was given
              // unbounded height」断言。
              if (!availableHeight.isFinite) {
                return window;
              }

              // 上面的行数/行高推导已经保证「窗口高度 == 面板高度」，正常情况下这个
              // 滚动视图是**不会滚动**的（内容与视口等高），只负责一件事：面板矮到连
              // 一行都放不下时（极端窗口尺寸）给内容一个不受硬约束的空间，让用户可以
              // 滚动看全，而不是被裁掉半行译文。`minHeight` 让窗口在面板内撑满并居中
              // （`_buildAnimatedWindow` 里的 `Stack` 是 `Alignment.center`）。
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: availableHeight),
                  child: window,
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// 使用 AnimatedSwitcher 实现丝滑滚动效果
  Widget _buildAnimatedWindow({
    required int displayIndex,
    required List<Widget> lyricWidgets,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        // 只显示当前的 child，不显示之前的 child
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (Widget child, Animation<double> animation) {
        // 向上滑动的过渡效果
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.0, 0.1), // 从下方10%处开始
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ));

        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
      // `mainAxisSize: min` 让 Column 按内容取高，配合上面 `layoutBuilder` 里
      // `Alignment.center` 的 Stack 完成居中；行高已由 metrics 保证不小于内容需要，
      // 内容更高时行会自己撑开。
      child: Column(
        key: ValueKey<int>(displayIndex), // 关键：当索引变化时触发动画
        mainAxisSize: MainAxisSize.min,
        children: lyricWidgets,
      ),
    );
  }

  /// 构建窗口里的一行。
  ///
  /// [slot] 是窗口内的槽位序号（用于空行的 key），[lyricIndex] 是它对应的歌词下标，
  /// 越界时渲染成等高的空行占位，保证有歌词行与空行的高度模型完全一致。
  Widget _buildRow({
    required int slot,
    required int lyricIndex,
    required int displayIndex,
    required double itemHeight,
    required Color? themeColor,
  }) {
    if (lyricIndex < 0 || lyricIndex >= widget.lyrics.length) {
      // 空行占位：与歌词行共用同一个行高，滚动时窗口不会跳动。
      return SizedBox(
        height: itemHeight,
        key: ValueKey<String>('empty_$slot'),
      );
    }

    final LyricLine lyric = widget.lyrics[lyricIndex];
    final bool isCurrent = lyricIndex == displayIndex;
    final bool isActuallyPlaying = lyricIndex == widget.currentLyricIndex;

    // 用 ConstrainedBox 的**最小**高度代替 SizedBox 的固定高度：行高由内容决定，
    // 内容比预算高时（字体度量误差等）行会自己撑开，而不是溢出被裁掉。
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: itemHeight),
      key: ValueKey<String>('lyric_$lyricIndex'),
      child: Center(
        child: isCurrent
            ? _buildKaraokeLyricLine(lyric, themeColor, isActuallyPlaying)
            : _buildNormalLyricLine(lyric, themeColor, isCurrent),
      ),
    );
  }

  /// 构建卡拉OK样式的歌词行（当前歌词）
  Widget _buildKaraokeLyricLine(LyricLine lyric, Color? themeColor, bool isActuallyPlaying) {
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, child) {
        final player = PlayerService();
        // 只有正在播放的歌词才显示填充效果，手动选择的显示静态高亮
        final fillProgress = isActuallyPlaying ? _calculateFillProgress(lyric, player.position) : 0.0;
        final isSelected = _isManualMode && !isActuallyPlaying;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: _spec.horizontalTextPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 原文歌词 - 卡拉OK效果
              _buildKaraokeText(
                text: lyric.text,
                fontSize: _spec.currentFontSize,
                fillProgress: fillProgress,
                themeColor: themeColor,
                isSelected: isSelected,
                lyric: lyric,
                currentPosition: player.position,
              ),

              // 翻译歌词（根据开关显示）- 普通高亮
              if (widget.showTranslation && lyric.translation != null && lyric.translation!.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: _spec.translationGap),
                  child: Text(
                    lyric.translation!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _getAdaptiveLyricColor(themeColor, false).withOpacity(0.75),
                      fontSize: _spec.currentTranslationFontSize,
                      // 显式声明行高，保证测量与渲染同源（普通行由 AnimatedDefaultTextStyle
                      // 继承 1.4，当前行没有那层默认样式，必须在这里补上）。
                      height: _spec.lineHeightFactor,
                      fontFamily: LyricFontService().currentFontFamily,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 构建普通歌词行（非当前歌词）
  Widget _buildNormalLyricLine(LyricLine lyric, Color? themeColor, bool isCurrent) {
    // 获取自适应颜色
    final lyricColor = _getAdaptiveLyricColor(themeColor, isCurrent);
    final translationColor = _getAdaptiveLyricColor(
      themeColor,
      false, // 翻译始终使用非当前行的颜色
    ).withOpacity(isCurrent ? 0.75 : 0.5);

    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      style: TextStyle(
        color: lyricColor,
        fontSize: _spec.otherFontSize,
        fontWeight: FontWeight.normal,
        height: _spec.lineHeightFactor,
        fontFamily: LyricFontService().currentFontFamily,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _spec.horizontalTextPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 原文歌词
            Text(
              lyric.text,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 翻译歌词（根据开关显示）
            if (widget.showTranslation && lyric.translation != null && lyric.translation!.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: _spec.translationGap),
                child: Text(
                  lyric.translation!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: translationColor,
                    fontSize: _spec.otherTranslationFontSize,
                    fontFamily: LyricFontService().currentFontFamily,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 构建卡拉OK文字效果
  /// 支持两种模式：
  /// 1. 有逐字歌词数据时：每个字单独渲染并高亮
  /// 2. 无逐字歌词数据时：回退到整行渐变填充
  ///
  /// 高度说明：两种模式都用 `height: spec.lineHeightFactor` 的 `maxLines: 1` 文本，
  /// 双层 `Stack`（描边层 + 填充层）不额外增高，所以单层/双层的高度需求一致，可与
  /// 普通行共用同一套测量。逐字模式的 `Wrap` 若因文字过长折行会更高，此时由行的
  /// `minHeight` + 外层滚动兜底承接，不会硬溢出。
  Widget _buildKaraokeText({
    required String text,
    required double fontSize,
    required double fillProgress,
    required Color? themeColor,
    bool isSelected = false,
    LyricLine? lyric,
    Duration? currentPosition,
  }) {
    final baseColor = _getAdaptiveLyricColor(themeColor, false);
    final highlightColor = _getAdaptiveLyricColor(themeColor, true);

    // 如果有逐字歌词数据，使用逐字填充模式
    if (lyric != null && lyric.hasWordByWord && lyric.words != null && currentPosition != null && !isSelected) {
      return _buildWordByWordKaraokeText(
        lyric: lyric,
        currentPosition: currentPosition,
        fontSize: fontSize,
        baseColor: baseColor,
        highlightColor: highlightColor,
      );
    }

    // 回退到整行填充模式
    return Stack(
      children: [
        // 底层：未填充的文字（半透明）
        Text(
          text,
          style: TextStyle(
            color: baseColor,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            fontFamily: LyricFontService().currentFontFamily,
            height: _spec.lineHeightFactor,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        // 上层：填充的文字（高亮色或选中色）
        ClipRect(
          clipper: _DesktopKaraokeClipper(isSelected ? 1.0 : fillProgress),
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.orange : highlightColor,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              fontFamily: LyricFontService().currentFontFamily,
              height: _spec.lineHeightFactor,
              // 添加发光效果
              shadows: [
                Shadow(
                  color: isSelected
                      ? Colors.orange.withOpacity(0.6)
                      : highlightColor.withOpacity(0.5),
                  blurRadius: isSelected ? 12 : 8,
                  offset: const Offset(0, 0),
                ),
              ],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 构建逐字填充的卡拉OK效果
  Widget _buildWordByWordKaraokeText({
    required LyricLine lyric,
    required Duration currentPosition,
    required double fontSize,
    required Color baseColor,
    required Color highlightColor,
  }) {
    final words = lyric.words!;

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: List.generate(words.length, (index) {
        final word = words[index];

        // 计算这个字的填充进度
        double wordProgress;
        if (currentPosition < word.startTime) {
          // 还没开始唱这个字
          wordProgress = 0.0;
        } else if (currentPosition >= word.endTime) {
          // 这个字已经唱完
          wordProgress = 1.0;
        } else {
          // 正在唱这个字，计算内部进度
          final wordElapsed = currentPosition - word.startTime;
          wordProgress = (wordElapsed.inMilliseconds / word.duration.inMilliseconds).clamp(0.0, 1.0);
        }

        return _KaraokeWordWidget(
          text: word.text,
          progress: wordProgress,
          fontSize: fontSize,
          baseColor: baseColor,
          highlightColor: highlightColor,
        );
      }),
    );
  }

  /// 计算填充进度（0.0 - 1.0）
  /// 支持逐字歌词的精确时间同步
  double _calculateFillProgress(LyricLine lyric, Duration currentPosition) {
    if (lyric.startTime == null) return 0.0;

    // 检查是否有逐字歌词数据
    if (lyric.hasWordByWord && lyric.words != null) {
      // 使用逐字歌词计算精确进度
      return _calculateWordByWordProgress(lyric, currentPosition);
    }

    // 否则使用平均时间计算（原有逻辑）
    final startMs = lyric.startTime!.inMilliseconds;
    final currentMs = currentPosition.inMilliseconds;

    // 如果还没开始，返回0
    if (currentMs < startMs) return 0.0;

    // 计算歌词行的持续时间（到下一行开始或3秒默认）
    final nextLyricIndex = widget.currentLyricIndex + 1;
    Duration endTime;

    if (nextLyricIndex < widget.lyrics.length && widget.lyrics[nextLyricIndex].startTime != null) {
      endTime = widget.lyrics[nextLyricIndex].startTime!;
    } else {
      // 最后一行或下一行没有时间戳，使用3秒默认持续时间
      endTime = lyric.startTime! + const Duration(seconds: 3);
    }

    final endMs = endTime.inMilliseconds;
    final durationMs = endMs - startMs;

    if (durationMs <= 0) return 1.0; // 避免除零

    final elapsedMs = currentMs - startMs;
    final progress = (elapsedMs / durationMs).clamp(0.0, 1.0);

    return progress;
  }

  /// 计算逐字歌词的精确进度（基于时间占比）
  double _calculateWordByWordProgress(LyricLine lyric, Duration currentPos) {
    final words = lyric.words!;
    if (words.isEmpty) return 0.0;

    // 计算总持续时间
    final Duration totalDuration;
    if (lyric.lineDuration != null && lyric.lineDuration!.inMilliseconds > 0) {
      totalDuration = lyric.lineDuration!;
    } else {
      final lastWord = words.last;
      totalDuration = lastWord.endTime - words.first.startTime;
    }

    if (totalDuration.inMilliseconds == 0) return 0.0;

    final elapsedFromLineStart = currentPos - lyric.startTime!;

    if (elapsedFromLineStart.inMilliseconds < 0) {
      return 0.0;
    }

    if (elapsedFromLineStart >= totalDuration) {
      return 1.0;
    }

    // 基于时间占比计算进度
    double accumulatedProgress = 0.0;

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final wordTimeRatio = word.duration.inMilliseconds / totalDuration.inMilliseconds;

      if (currentPos >= word.startTime && currentPos < word.endTime) {
        final wordElapsed = currentPos - word.startTime;
        final wordInternalProgress = (wordElapsed.inMilliseconds / word.duration.inMilliseconds).clamp(0.0, 1.0);
        accumulatedProgress += wordInternalProgress * wordTimeRatio;
        return accumulatedProgress.clamp(0.0, 1.0);
      } else if (currentPos >= word.endTime) {
        accumulatedProgress += wordTimeRatio;
      } else {
        return accumulatedProgress.clamp(0.0, 1.0);
      }
    }

    return 1.0;
  }

  /// 构建桌面端时间胶囊组件
  Widget _buildDesktopTimeCapsule() {
    if (_selectedLyricIndex == null ||
        _selectedLyricIndex! < 0 ||
        _selectedLyricIndex! >= widget.lyrics.length) {
      return const SizedBox.shrink();
    }

    final selectedLyric = widget.lyrics[_selectedLyricIndex!];
    final timeText = selectedLyric.startTime != null
        ? _formatDuration(selectedLyric.startTime!)
        : '00:00';

    return FadeTransition(
      opacity: _timeCapsuleFadeAnimation!,
      child: Center(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: _seekToSelectedLyric,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 时间显示
                  Text(
                    timeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // 跳转提示
                  const Text(
                    '点击跳转',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 格式化时间显示
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 根据背景色亮度判断应该使用深色还是浅色文字
  bool _shouldUseDarkText(Color backgroundColor) {
    final luminance = backgroundColor.computeLuminance();
    return luminance > 0.5;
  }

  /// 获取自适应的歌词颜色
  Color _getAdaptiveLyricColor(Color? themeColor, bool isCurrent) {
    final color = themeColor ?? Colors.grey[700]!;
    final useDarkText = _shouldUseDarkText(color);

    if (useDarkText) {
      // 亮色背景，使用深色文字
      return isCurrent
          ? Colors.black87
          : Colors.black54;
    } else {
      // 暗色背景，使用浅色文字
      return isCurrent
          ? Colors.white
          : Colors.white.withOpacity(0.45);
    }
  }
}

/// 桌面端卡拉OK样式的自定义裁剪器
class _DesktopKaraokeClipper extends CustomClipper<Rect> {
  final double progress;

  _DesktopKaraokeClipper(this.progress);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      0,
      0,
      size.width * progress, // 根据进度裁剪宽度
      size.height,
    );
  }

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) {
    return true; // 总是重新裁剪以实现动画效果
  }
}

/// 单个字的卡拉OK填充组件
/// 使用 Stack + ClipRect 实现从左到右的填充效果
class _KaraokeWordWidget extends StatelessWidget {
  final String text;
  final double progress; // 0.0 - 1.0
  final double fontSize;
  final Color baseColor;
  final Color highlightColor;

  const _KaraokeWordWidget({
    required this.text,
    required this.progress,
    required this.fontSize,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: [
          // 底层：未填充的暗色文字
          Text(
            text,
            style: TextStyle(
              color: baseColor,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              fontFamily: LyricFontService().currentFontFamily,
              height: LyricLayoutSpec.standard.lineHeightFactor,
            ),
          ),

          // 上层：填充的亮色文字（通过 ClipRect 裁剪）
          ClipRect(
            clipper: _DesktopKaraokeClipper(progress),
            child: Text(
              text,
              style: TextStyle(
                color: highlightColor,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                fontFamily: LyricFontService().currentFontFamily,
                height: LyricLayoutSpec.standard.lineHeightFactor,
                // 添加发光效果
                shadows: [
                  Shadow(
                    color: highlightColor.withOpacity(0.5),
                    blurRadius: 8,
                    offset: const Offset(0, 0),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
