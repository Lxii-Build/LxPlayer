import 'package:flutter/material.dart';

import '../../models/lyric_line.dart';
import '../../services/player_service.dart';
import 'lyric_window_metrics.dart';

/// 播放器歌词面板
/// 显示歌词和翻译，支持自适应颜色和滚动动画
class PlayerLyricsPanel extends StatelessWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;

  const PlayerLyricsPanel({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
  });

  // ---- 排版参数 ----
  //
  // 测量与渲染必须用同一份参数，所以这里不再重复声明字号/行高，而是引用共享的
  // [LyricLayoutSpec]（见 lyric_window_metrics.dart）。卡拉OK面板用的是同一份 ——
  // 这正是把行高推导抽成共享文件的目的：避免「同一套写法散在两处、只有一处被修」。
  static const LyricLayoutSpec _spec = LyricLayoutSpec.standard;
  static const String _fontFamily = 'Microsoft YaHei';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: lyrics.isEmpty ? _buildNoLyric() : _buildLyricList(),
    );
  }

  /// 构建无歌词提示
  Widget _buildNoLyric() {
    return ValueListenableBuilder<Color?>(
      valueListenable: PlayerService().themeColorNotifier,
      builder: (context, themeColor, child) {
        final textColor =
            _getAdaptiveLyricColor(themeColor, false).withOpacity(0.5);
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
        lyrics: lyrics,
        showTranslation: showTranslation,
      );

  /// 构建歌词列表（行高随内容自适应，当前歌词固定在窗口靠中位置，丝滑滚动）
  Widget _buildLyricList() {
    // 使用 RepaintBoundary 隔离歌词区域的重绘
    return RepaintBoundary(
      child: ValueListenableBuilder<Color?>(
        valueListenable: PlayerService().themeColorNotifier,
        builder: (context, themeColor, child) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final double availableHeight = constraints.maxHeight;
              final LyricWindowMetrics metrics = resolveLyricWindowMetrics(
                availableHeight: availableHeight,
                withTranslation: _hasTranslationContent,
                spec: _spec,
              );

              final int startIndex =
                  currentLyricIndex - metrics.currentLinePosition;

              final List<Widget> lyricWidgets = <Widget>[
                for (int i = 0; i < metrics.visibleLines; i++)
                  _buildRow(
                    slot: i,
                    lyricIndex: startIndex + i,
                    itemHeight: metrics.itemHeight,
                    themeColor: themeColor,
                  ),
              ];

              final Widget window = _buildAnimatedWindow(lyricWidgets);

              // 高度无界时（父级不给约束）本就无从谈起「铺满」，直接按内容收缩；
              // 也不能套滚动视图，否则会命中「Vertical viewport was given
              // unbounded height」断言。
              if (!availableHeight.isFinite) {
                return window;
              }

              // 上面的行数/行高推导已经保证「窗口高度 == 面板高度」，正常情况下这个
              // 滚动视图是**不会滚动**的（内容与视口等高），只负责一件事：面板矮到连
              // 一行都放不下时（极端窗口尺寸）给内容一个不受硬约束的空间。
              // 那种情况下用户可以滚动看全，而不是被裁掉半行译文。
              //
              // `minHeight` 让窗口在面板内撑满并居中（`_buildAnimatedWindow` 里的
              // `Stack` 是 `Alignment.center`），保持与原固定行高实现一致的观感。
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
  Widget _buildAnimatedWindow(List<Widget> lyricWidgets) {
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
        // 向上滑动的过渡效果（无淡入淡出）
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
      // `mainAxisSize: min` 是这次修复的关键之一：Column 按内容取高，配合上面
      // `layoutBuilder` 里 `Alignment.center` 的 Stack 完成居中。原来用 `max`
      // 会把 Column 钉死在父级高度上，再把内容硬塞进等分的格子里。
      child: Column(
        key: ValueKey<int>(currentLyricIndex), // 关键：当索引变化时触发动画
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
    required double itemHeight,
    required Color? themeColor,
  }) {
    if (lyricIndex < 0 || lyricIndex >= lyrics.length) {
      // 空行占位：与歌词行共用同一个行高，滚动时窗口不会跳动。
      return SizedBox(
        height: itemHeight,
        key: ValueKey<String>('empty_$slot'),
      );
    }

    final LyricLine lyric = lyrics[lyricIndex];
    final bool isCurrent = lyricIndex == currentLyricIndex;
    final bool hasTranslation = showTranslation &&
        lyric.translation != null &&
        lyric.translation!.isNotEmpty;

    // 获取自适应颜色
    final Color lyricColor = _getAdaptiveLyricColor(themeColor, isCurrent);
    final Color translationColor = _getAdaptiveLyricColor(
      themeColor,
      false, // 翻译始终使用非当前行的颜色
    ).withOpacity(isCurrent ? 0.75 : 0.5);

    // 用 ConstrainedBox 的**最小**高度代替 SizedBox 的固定高度：行高由内容决定，
    // 内容比预算高时（字体度量误差等）行会自己撑开，而不是溢出被裁掉。
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: itemHeight),
      key: ValueKey<String>('lyric_$lyricIndex'),
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: TextStyle(
            color: lyricColor,
            fontSize: isCurrent ? _spec.currentFontSize : _spec.otherFontSize,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            height: _spec.lineHeightFactor,
            fontFamily: _fontFamily, // 使用微软雅黑字体
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _spec.horizontalTextPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // 原文歌词
                Text(
                  lyric.text,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // 翻译歌词（根据开关显示）
                if (hasTranslation)
                  Padding(
                    padding: EdgeInsets.only(top: _spec.translationGap),
                    child: Text(
                      lyric.translation!,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: translationColor,
                        fontSize: isCurrent
                            ? _spec.currentTranslationFontSize
                            : _spec.otherTranslationFontSize,
                        fontFamily: _fontFamily, // 使用微软雅黑字体
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 根据背景色亮度判断应该使用深色还是浅色文字
  /// 返回 true 表示背景亮，应该用深色文字；返回 false 表示背景暗，应该用浅色文字
  bool _shouldUseDarkText(Color backgroundColor) {
    // 计算颜色的相对亮度 (0.0 - 1.0)
    // 使用 W3C 推荐的计算公式
    final luminance = backgroundColor.computeLuminance();

    // 如果亮度大于 0.5，认为是亮色背景，应该用深色文字
    return luminance > 0.5;
  }

  /// 获取自适应的歌词颜色
  Color _getAdaptiveLyricColor(Color? themeColor, bool isCurrent) {
    final color = themeColor ?? Colors.grey[700]!;
    final useDarkText = _shouldUseDarkText(color);

    if (useDarkText) {
      // 亮色背景，使用深色文字
      return isCurrent ? Colors.black87 : Colors.black54;
    } else {
      // 暗色背景，使用浅色文字
      return isCurrent ? Colors.white : Colors.white.withOpacity(0.45);
    }
  }
}
