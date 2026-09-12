import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/lyric_line.dart';

/// 歌词窗口的排版参数。
///
/// 这些常量同时被「测量」和「渲染」使用，**必须同源**：一旦渲染用的字号/行高与这里
/// 不一致，行高预算就会算错，溢出会以黄黑条纹的形式跑回来。
///
/// 之所以把参数与推导逻辑抽成这个共享文件，而不是在两个面板里各写一份：历史缺陷正是
/// 「同一套写法散在两处、只有一份被修」——`PlayerLyricsPanel` 修好了，生产实际使用的
/// `PlayerKaraokeLyricsPanel` 却没人动。共用一份实现可以从根上杜绝这种漂移。
@immutable
class LyricLayoutSpec {
  const LyricLayoutSpec({
    this.maxVisibleLines = 8,
    this.lineHeightFactor = 1.4,
    this.currentFontSize = 18,
    this.otherFontSize = 15,
    this.currentTranslationFontSize = 13,
    this.otherTranslationFontSize = 12,
    this.translationGap = 2,
    this.lineHeightSlack = 1,
    this.horizontalTextPadding = 16,
  });

  /// 窗口最多显示的行数；空间不够时会自动少显示几行。
  final int maxVisibleLines;

  /// 行高系数。
  ///
  /// 它会被**显式**写进 `TextStyle.height`，从而保证行高恒等于 `fontSize * factor`，
  /// 与具体字体无关 —— 这一点是跨平台（本地 vs CI）稳定的前提，不能改成依赖字体度量。
  final double lineHeightFactor;

  final double currentFontSize;
  final double otherFontSize;
  final double currentTranslationFontSize;
  final double otherTranslationFontSize;

  /// 原文与译文之间的间距。
  final double translationGap;

  /// 行高预算的冗余像素。
  ///
  /// 行高本身是精确算出来的（见 [requiredLineExtent]），这 1px 只是为了吸收不同
  /// 平台/字体的度量舍入差异，避免窗口在边界高度上变得「差一点点就要滚动」。
  /// 它不是溢出的防线 —— 防线是每行用 `minHeight` 而非固定高度。
  final double lineHeightSlack;

  /// 歌词文字的水平内边距（不影响高度测量，仅作为同源约定供渲染使用）。
  final double horizontalTextPadding;

  /// 标准排版参数：普通面板与卡拉OK面板共用同一份。
  static const LyricLayoutSpec standard = LyricLayoutSpec();
}

/// 歌词窗口的最终规格。
@immutable
class LyricWindowMetrics {
  const LyricWindowMetrics({
    required this.visibleLines,
    required this.currentLinePosition,
    required this.itemHeight,
  });

  /// 窗口里显示的行数（含越界时的空行占位）。
  final int visibleLines;

  /// 当前歌词落在窗口的第几行（0 基）。
  final int currentLinePosition;

  /// 每行的高度预算，保证不小于该行内容真正需要的高度；空行占位用同一个值。
  final double itemHeight;
}

/// 这首歌在当前开关下是否真的会渲染译文。
///
/// 用**整首歌**判断而不是逐行判断：行高预算若随窗口滑动而变，歌词块会上下抖动。
bool hasTranslationContent({
  required List<LyricLine> lyrics,
  required bool showTranslation,
}) {
  if (!showTranslation) {
    return false;
  }
  return lyrics.any(
    (LyricLine line) => line.translation != null && line.translation!.isNotEmpty,
  );
}

/// 单行内容需要的高度：原文一行（有译文时再加间距和译文一行）。
///
/// 两段文字都是 `maxLines: 1` 且显式指定了 `height: spec.lineHeightFactor`，
/// 行高等于 `fontSize * height`，与具体字体无关，所以这里算出来的是精确值而非估算。
double requiredLineExtent({
  required double textFontSize,
  double? translationFontSize,
  LyricLayoutSpec spec = LyricLayoutSpec.standard,
}) {
  double extent = textFontSize * spec.lineHeightFactor;
  if (translationFontSize != null) {
    extent += spec.translationGap + translationFontSize * spec.lineHeightFactor;
  }
  return extent + spec.lineHeightSlack;
}

/// 由「内容需要多高」推导窗口规格，而不是把容器高度硬切成固定份数。
///
/// 原来的缺陷实现是 `constraints.maxHeight / 8` 得到固定行高、再用 `SizedBox` 死约束
/// 每一行；开启译文的一行要装「原文 + 间距 + 译文」，在 280px 可用高度下需要 39.8px
/// 却只分到 35px，必然 `RenderFlex overflowed`。
LyricWindowMetrics resolveLyricWindowMetrics({
  required double availableHeight,
  required bool withTranslation,
  LyricLayoutSpec spec = LyricLayoutSpec.standard,
}) {
  // 统一行高取两种行型的较大值：当前行字号更大，且窗口滑动时哪一行是当前行会变，
  // 行高必须与之无关才不会抖动。
  final double minItemHeight = math.max(
    requiredLineExtent(
      textFontSize: spec.currentFontSize,
      translationFontSize:
          withTranslation ? spec.currentTranslationFontSize : null,
      spec: spec,
    ),
    requiredLineExtent(
      textFontSize: spec.otherFontSize,
      translationFontSize:
          withTranslation ? spec.otherTranslationFontSize : null,
      spec: spec,
    ),
  );

  // 能放下几行就显示几行：放不下 maxVisibleLines 行时减少行数，而不是压缩行高把译文挤掉。
  // 高度无界时（父级不给约束）退回最大行数，由调用方按内容收缩。
  final int fittingLines = availableHeight.isFinite
      ? (availableHeight / minItemHeight).floor()
      : spec.maxVisibleLines;
  final int visibleLines = fittingLines.clamp(1, spec.maxVisibleLines);

  // 行数定下来后再把剩余空间均分回每一行，保持原来「歌词铺满面板」的观感；因为
  // visibleLines 是向下取整来的，均分结果一定不小于内容需要的高度，数学上不可能再溢出。
  final double itemHeight = availableHeight.isFinite
      ? math.max(minItemHeight, availableHeight / visibleLines)
      : minItemHeight;

  return LyricWindowMetrics(
    visibleLines: visibleLines,
    // 当前行略高于正中（8 行时为索引 3），行数减少时按同样比例上移。
    currentLinePosition: (visibleLines - 1) ~/ 2,
    itemHeight: itemHeight,
  );
}
