import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/player_service.dart';
import '../../models/lyric_line.dart';
import '../player_components/lyric_window_metrics.dart';

/// 移动端卡拉OK样式歌词组件
/// 支持从左到右的填充效果、上下滚动和手动滑动选择
class MobilePlayerKaraokeLyric extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final VoidCallback onTap;
  final bool showTranslation;

  /// 是否铺满父级给到的全部高度。
  ///
  /// - `false`（默认，旧行为）：固定三行高度，用于经典布局里的 300px 占位分支；
  /// - `true`：用共享的 [resolveLyricWindowMetrics] 按**可用高度反推行数与行高**，
  ///   把歌词铺满到容器底部（供极简歌词流布局使用）。行数不足时行高自动回填，
  ///   数学上不可能溢出，与桌面端 `PlayerKaraokeLyricsPanel` 同一套高度契约。
  final bool fillHeight;

  const MobilePlayerKaraokeLyric({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.onTap,
    required this.showTranslation,
    this.fillHeight = false,
  });

  @override
  State<MobilePlayerKaraokeLyric> createState() => _MobilePlayerKaraokeLyricState();
}

class _MobilePlayerKaraokeLyricState extends State<MobilePlayerKaraokeLyric> with TickerProviderStateMixin {
  /// 铺满模式下的排版参数：与桌面端 `LyricLayoutSpec.standard` 同源（仅字号按移动端略调），
  /// 保证「测量」和「渲染」用的是同一份行高系数 `1.4`，不会因为字体度量差异而算错。
  static const LyricLayoutSpec _fillSpec = LyricLayoutSpec(
    maxVisibleLines: 8,
    currentFontSize: 20,
    otherFontSize: 16,
    currentTranslationFontSize: 13,
    otherTranslationFontSize: 12,
  );

  int? _selectedLyricIndex; // 手动选择的歌词索引
  bool _isManualMode = false; // 是否处于手动模式
  Timer? _autoResetTimer; // 自动回退定时器
  AnimationController? _timeCapsuleAnimationController;
  Animation<double>? _timeCapsuleFadeAnimation;
  
  // 滑动相关
  double _accumulatedDelta = 0.0; // 累积的滑动距离
  static const double _scrollSensitivity = 15.0; // 滑动敏感度

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  @override
  void dispose() {
    _autoResetTimer?.cancel();
    _timeCapsuleAnimationController?.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        // 计算容器高度：3行主歌词；开启译文时为 主行+译文 的总高度
        const int totalVisibleLines = 3;
        const double lineHeight = 30.0;
        const double translationHeight = 22.0;
        final double fixedItemHeight = lineHeight + (widget.showTranslation ? translationHeight : 0);
        final double fixedContainerHeight = totalVisibleLines * fixedItemHeight + 2.0; // 轻微冗余，避免字体度量导致的溢出

        // 铺满模式：容器直接吃满父级约束高度，行数/行高改由可用高度反推
        // （见 _buildKaraokeLyricStream）。旧模式保持固定三行不变。
        final bool fill = widget.fillHeight && constraints.maxHeight.isFinite;
        final double containerHeight = fill ? constraints.maxHeight : fixedContainerHeight;

        return Stack(
          children: [
            // 主要歌词区域
            GestureDetector(
              onTap: widget.onTap,
              onVerticalDragStart: (details) {
                if (widget.lyrics.isEmpty) return;
                
                // 开始滑动时，如果还没有手动选择，使用当前播放索引作为起点
                if (!_isManualMode) {
                  _startManualMode(widget.currentLyricIndex);
                }
                _accumulatedDelta = 0.0;
              },
              onVerticalDragUpdate: (details) {
                if (widget.lyrics.isEmpty || !_isManualMode) return;
                
                // 累积滑动距离
                _accumulatedDelta += details.delta.dy;
                
                // 计算应该移动的行数
                final linesToMove = (_accumulatedDelta / _scrollSensitivity).floor();
                
                if (linesToMove.abs() >= 1) {
                  final currentIndex = _selectedLyricIndex ?? widget.currentLyricIndex;
                  int newIndex;
                  
                  if (linesToMove > 0) {
                    // 向下滑动，选择更前面的歌词
                    newIndex = (currentIndex - linesToMove).clamp(0, widget.lyrics.length - 1);
                  } else {
                    // 向上滑动，选择更后面的歌词
                    newIndex = (currentIndex - linesToMove).clamp(0, widget.lyrics.length - 1);
                  }
                  
                  if (newIndex != currentIndex) {
                    setState(() {
                      _selectedLyricIndex = newIndex;
                    });
                    
                    // 重置累积距离和定时器
                    _accumulatedDelta = 0.0;
                    _resetAutoTimer();
                  }
                }
              },
              onVerticalDragEnd: (details) {
                // 滑动结束时重置累积距离
                _accumulatedDelta = 0.0;
              },
              child: Container(
                // 固定区域高度以容纳三行（带或不带译文）；铺满模式下即为父级可用高度
                height: containerHeight,
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
                child: widget.lyrics.isEmpty
                    ? _buildNoLyric(screenWidth)
                    : (fill
                        ? _buildKaraokeLyricStream(screenWidth, containerHeight)
                        : _buildKaraokeLyricLines(screenWidth)),
              ),
            ),
            
            // 时间胶囊组件
            if (_isManualMode && _selectedLyricIndex != null)
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: _buildTimeCapsule(),
              ),
          ],
        );
      },
    );
  }

  /// 构建无歌词提示
  Widget _buildNoLyric(double screenWidth) {
    final lyricFontSize = (screenWidth * 0.038).clamp(14.0, 16.0);
    
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        final textColor = _getAdaptiveLyricColor(themeColor, false).withOpacity(0.5);
        
        return Center(
          child: Text(
            '暂无歌词',
            style: TextStyle(
              color: textColor,
              fontSize: lyricFontSize,
              fontFamily: 'Microsoft YaHei',
            ),
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }

  /// 构建卡拉OK样式的3行歌词显示
  Widget _buildKaraokeLyricLines(double screenWidth) {
    const int totalVisibleLines = 3; // 总共显示3行
    const int currentLinePosition = 1; // 当前歌词在第2行（索引1）
    // 使用 flex 比例代替固定像素高度，避免轻微的度量误差造成溢出
    const int mainFlex = 100; // 近似 30
    const int transFlex = 73; // 近似 22，对应比例 30:22 ≈ 100:73
    
    final lyricFontSize = (screenWidth * 0.038).clamp(14.0, 16.0);
    final smallFontSize = lyricFontSize * 0.85;
    final showTrans = widget.showTranslation;
    
    // 使用手动选择的索引或当前播放索引
    final displayIndex = _selectedLyricIndex ?? widget.currentLyricIndex;
    
    // 计算显示范围
    int startIndex = displayIndex - currentLinePosition;
    
    List<Widget> rows = [];
    for (int i = 0; i < totalVisibleLines; i++) {
      final int lyricIndex = startIndex + i;
      final int lineFlex = showTrans ? (mainFlex + transFlex) : mainFlex;
      if (lyricIndex < 0 || lyricIndex >= widget.lyrics.length) {
        // 空行
        rows.add(
          Expanded(
            key: ValueKey('empty_$i'),
            flex: lineFlex,
            child: const SizedBox.shrink(),
          ),
        );
        continue;
      }
      final lyric = widget.lyrics[lyricIndex];
      final isCurrent = lyricIndex == displayIndex;
      final isActuallyPlaying = lyricIndex == widget.currentLyricIndex;
      rows.add(
        Expanded(
          key: ValueKey('lyric_$lyricIndex'),
          flex: lineFlex,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                flex: mainFlex,
                child: Center(
                  child: isCurrent
                      ? _buildKaraokeLyricLine(lyric, lyricFontSize, isActuallyPlaying)
                      : _buildNormalLyricLine(lyric, smallFontSize, false),
                ),
              ),
              if (showTrans)
                Expanded(
                  flex: transFlex,
                  child: Center(
                    child: (lyric.translation != null && lyric.translation!.trim().isNotEmpty)
                        ? _buildTranslationLine(lyric.translation!, smallFontSize * 0.95)
                        : const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (Widget child, Animation<double> animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.0, 0.3),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ));
        return SlideTransition(position: offsetAnimation, child: child);
      },
      child: Column(
        key: ValueKey(displayIndex),
        mainAxisAlignment: MainAxisAlignment.center,
        children: rows,
      ),
    );
  }

  /// 铺满高度模式：把可用高度交给共享的 [resolveLyricWindowMetrics]，
  /// **由内容所需行高反推能显示几行**，再把剩余空间均分回每一行。
  ///
  /// 与桌面端 `PlayerKaraokeLyricsPanel` 用的是同一套高度契约：行数向下取整，
  /// 因此 `visibleLines * itemHeight <= availableHeight` 恒成立，不会有黄黑条纹。
  Widget _buildKaraokeLyricStream(double screenWidth, double availableHeight) {
    final bool withTranslation = hasTranslationContent(
      lyrics: widget.lyrics,
      showTranslation: widget.showTranslation,
    );
    final LyricWindowMetrics metrics = resolveLyricWindowMetrics(
      availableHeight: availableHeight,
      withTranslation: withTranslation,
      spec: _fillSpec,
    );

    final int displayIndex = _selectedLyricIndex ?? widget.currentLyricIndex;
    final int startIndex = displayIndex - metrics.currentLinePosition;

    final double currentFontSize = _fillSpec.currentFontSize;
    final double otherFontSize = _fillSpec.otherFontSize;

    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < metrics.visibleLines; i++) {
      final int lyricIndex = startIndex + i;
      if (lyricIndex < 0 || lyricIndex >= widget.lyrics.length) {
        // 空行占位：与歌词行共用同一行高，滚动时窗口不跳动。
        rows.add(
          ConstrainedBox(
            key: ValueKey('empty_$i'),
            constraints: BoxConstraints(minHeight: metrics.itemHeight),
            child: const SizedBox(width: double.infinity, height: 0),
          ),
        );
        continue;
      }

      final LyricLine lyric = widget.lyrics[lyricIndex];
      final bool isCurrent = lyricIndex == displayIndex;
      final bool isActuallyPlaying = lyricIndex == widget.currentLyricIndex;
      final bool hasTranslation =
          widget.showTranslation &&
          lyric.translation != null &&
          lyric.translation!.trim().isNotEmpty;

      rows.add(
        ConstrainedBox(
          key: ValueKey('lyric_$lyricIndex'),
          constraints: BoxConstraints(minHeight: metrics.itemHeight),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                isCurrent
                    ? _buildKaraokeLyricLine(lyric, currentFontSize, isActuallyPlaying)
                    : _buildNormalLyricLine(lyric, otherFontSize, false),
                if (hasTranslation)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _buildTranslationLine(
                      lyric.translation!,
                      isCurrent
                          ? _fillSpec.currentTranslationFontSize
                          : _fillSpec.otherTranslationFontSize,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (Widget child, Animation<double> animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0.0, 0.12),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ));
        return SlideTransition(position: offsetAnimation, child: child);
      },
      child: Column(
        key: ValueKey(displayIndex),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: rows,
      ),
    );
  }

  /// 构建卡拉OK样式的歌词行（当前歌词）
  Widget _buildKaraokeLyricLine(LyricLine lyric, double fontSize, bool isActuallyPlaying) {
    final text = lyric.text.trim().isEmpty ? '♪' : lyric.text;
    
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        return AnimatedBuilder(
          animation: PlayerService(),
          builder: (context, child) {
            final player = PlayerService();
            // 只有正在播放的歌词才显示填充效果，手动选择的显示静态高亮
            final fillProgress = isActuallyPlaying ? _calculateFillProgress(lyric, player.position) : 0.0;
            final isSelected = _isManualMode && !isActuallyPlaying;
            
            return Center(
              child: _buildKaraokeText(
                text: text,
                fontSize: fontSize,
                fillProgress: fillProgress,
                themeColor: themeColor,
                isSelected: isSelected,
                lyric: lyric,
                currentPosition: player.position,
              ),
            );
          },
        );
      },
    );
  }

  /// 构建普通歌词行（非当前歌词）
  Widget _buildNormalLyricLine(LyricLine lyric, double fontSize, bool isCurrent) {
    final text = lyric.text.trim().isEmpty ? '♪' : lyric.text;
    
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        final lyricColor = _getAdaptiveLyricColor(themeColor, isCurrent);
        
        return Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              color: lyricColor,
              fontSize: fontSize,
              fontWeight: FontWeight.normal,
              fontFamily: 'Microsoft YaHei',
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }

  /// 构建翻译行
  Widget _buildTranslationLine(String translation, double fontSize) {
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        final baseColor = _getAdaptiveLyricColor(themeColor, false).withOpacity(0.75);
        return Center(
          child: Text(
            translation,
            style: TextStyle(
              color: baseColor,
              fontSize: fontSize,
              fontWeight: FontWeight.normal,
              fontFamily: 'Microsoft YaHei',
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  /// 构建卡拉OK文字效果
  /// 支持两种模式：有逐字歌词时使用逐字填充，否则回退到整行填充
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
            fontFamily: 'Microsoft YaHei',
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        
        // 上层：填充的文字（高亮色或选中色）
        ClipRect(
          clipper: _KaraokeClipper(isSelected ? 1.0 : fillProgress),
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.orange : highlightColor,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              fontFamily: 'Microsoft YaHei',
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
          wordProgress = 0.0;
        } else if (currentPosition >= word.endTime) {
          wordProgress = 1.0;
        } else {
          final wordElapsed = currentPosition - word.startTime;
          wordProgress = (wordElapsed.inMilliseconds / word.duration.inMilliseconds).clamp(0.0, 1.0);
        }
        
        return _MobileKaraokeWordWidget(
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
  double _calculateFillProgress(LyricLine lyric, Duration currentPosition) {
    if (lyric.startTime == null) return 0.0;
    
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

  /// 构建时间胶囊组件
  Widget _buildTimeCapsule() {
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
        child: GestureDetector(
          onTap: _seekToSelectedLyric,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
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
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                // 跳转提示
                const Text(
                  '点击跳转',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                ),
              ],
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
          : Colors.white.withOpacity(0.5);
    }
  }
}

/// 卡拉OK样式的自定义裁剪器
class _KaraokeClipper extends CustomClipper<Rect> {
  final double progress;

  _KaraokeClipper(this.progress);

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

/// 移动端卡拉OK单个字的填充组件
class _MobileKaraokeWordWidget extends StatelessWidget {
  final String text;
  final double progress;
  final double fontSize;
  final Color baseColor;
  final Color highlightColor;

  const _MobileKaraokeWordWidget({
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
          // 底层暗色文字
          Text(
            text,
            style: TextStyle(
              color: baseColor,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
          
          // 上层亮色文字（通过 ClipRect 裁剪）
          ClipRect(
            clipper: _KaraokeClipper(progress),
            child: Text(
              text,
              style: TextStyle(
                color: highlightColor,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                fontFamily: 'Microsoft YaHei',
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
