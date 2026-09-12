import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/models/lyric_line.dart';
import 'package:lxplayer/pages/player_components/player_karaoke_lyrics_panel.dart';

/// `PlayerKaraokeLyricsPanel` 的行高模型回归测试。
///
/// ⚠️ 为什么这份测试必须存在：`LyricStyle.defaultStyle` 分支（见
/// `player_page.dart` 的 `_buildLyricPanel`）返回的正是这个卡拉OK面板，它是**生产
/// 实际使用的组件**。而 `test/lyric_panel_overflow_test.dart` 钉的是零引用的
/// `PlayerLyricsPanel` —— 只测那个面板会给出「CI 全绿但用户仍看到黄黑条纹」的假象，
/// 这正是历史缺陷能漏到线上的原因。所以这里把同一套高度契约钉在真正的生产组件上。
///
/// 起因（与普通面板完全相同）：旧实现把容器高度**硬切八等分**
/// （`constraints.maxHeight / 8`）再用 `SizedBox(height:)` 死死约束每一行，而开启译文
/// 的一行要装「原文 + 间距 + 译文」，在 280px 可用高度下需要 46.4px、只分到 35px，
/// 必然 `RenderFlex overflowed`。
///
/// 这里钉住的是**修复后的高度契约**，而不是某张截图：
///   1. 开启译文时任何面板高度都不能溢出；
///   2. 关闭译文时的排版必须与旧实现逐像素一致（8 行、行高 35）；
///   3. 空行占位与歌词行永远等高，否则滚动会整块跳动；
///   4. 当前行的双层 Text（描边层 + 填充层）不额外增高，与普通行共用同一行高。
///
/// 面板只读 `PlayerService().themeColorNotifier`（默认 null）与
/// `LyricFontService().currentFontFamily`，不触发平台/网络调用。

/// 与共享排版参数 `LyricLayoutSpec.standard` 保持一致（两个面板共用同一份）。
const double _kLineHeightFactor = 1.4;
const double _kCurrentFontSize = 18.0;
const double _kOtherFontSize = 15.0;
const double _kCurrentTranslationFontSize = 13.0;
const double _kOtherTranslationFontSize = 12.0;
const double _kTranslationGap = 2.0;

/// 面板为跨平台字体度量舍入预留的冗余（`lineHeightSlack`）。
const double _kLineHeightSlack = 1.0;

/// 面板自身的上下 padding（`EdgeInsets.symmetric(vertical: 40)`）合计。
const double _kVerticalPadding = 80.0;

/// 窗口最多显示的行数。
const int _kMaxVisibleLines = 8;

/// 单行内容需要的高度。两段文字都是 `maxLines: 1` 且显式指定了 `height: 1.4`，
/// 行高恒等于 `fontSize * 1.4`，与具体字体无关，所以这是精确值而非估算。
double _requiredLineExtent({required bool withTranslation}) {
  double lineOf(double textSize, double translationSize) {
    final double extent = textSize * _kLineHeightFactor;
    if (!withTranslation) {
      return extent + _kLineHeightSlack;
    }
    return extent +
        _kTranslationGap +
        translationSize * _kLineHeightFactor +
        _kLineHeightSlack;
  }

  final double currentLine =
      lineOf(_kCurrentFontSize, _kCurrentTranslationFontSize);
  final double otherLine = lineOf(_kOtherFontSize, _kOtherTranslationFontSize);
  return currentLine > otherLine ? currentLine : otherLine;
}

/// 12 行歌词，偶数行带译文（与视觉基线用例同构）。
List<LyricLine> _sampleLyrics() => <LyricLine>[
      for (int i = 0; i < 12; i++)
        LyricLine(
          startTime: Duration(seconds: i * 5),
          text: '第 $i 行歌词示例文本',
          translation: i.isEven ? 'Lyric line $i translation' : null,
        ),
    ];

Future<void> _pumpPanel(
  WidgetTester tester, {
  required double panelHeight,
  required bool showTranslation,
  int currentLyricIndex = 4,
  List<LyricLine>? lyrics,
  double panelWidth = 440,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: panelWidth,
            height: panelHeight,
            child: PlayerKaraokeLyricsPanel(
              lyrics: lyrics ?? _sampleLyrics(),
              currentLyricIndex: currentLyricIndex,
              showTranslation: showTranslation,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 浮点比较容差。行高由除法算出，不能用 `==`。
const double _kTolerance = 1e-6;

/// 窗口里的所有槽位（歌词行 `lyric_i` + 空行占位 `empty_i`）。
Finder get _slots => find.byWidgetPredicate((Widget w) {
      final Key? key = w.key;
      return key is ValueKey<String> &&
          (key.value.startsWith('lyric_') || key.value.startsWith('empty_'));
    });

/// 窗口内的一个槽位。
class _Slot {
  const _Slot(this.key, this.top, this.height);

  final String key;
  final double top;
  final double height;

  @override
  String toString() => '$key(top=$top, height=$height)';
}

/// 按**上屏顺序**（从上到下）取出槽位，这样索引就等于窗口内的行号。
List<_Slot> _slotLayout(WidgetTester tester) {
  final List<_Slot> slots = <_Slot>[];
  for (final Element element in _slots.evaluate()) {
    final ValueKey<String> key = element.widget.key! as ValueKey<String>;
    final Finder finder = find.byKey(key);
    slots.add(_Slot(
      key.value,
      tester.getTopLeft(finder).dy,
      tester.getSize(finder).height,
    ));
  }
  slots.sort((_Slot a, _Slot b) => a.top.compareTo(b.top));
  return slots;
}

void main() {
  group('卡拉OK歌词面板行高模型', () {
    testWidgets('开启译文时，各种面板高度都不再溢出', (WidgetTester tester) async {
      // 360 是视觉基线用例的高度（可用 280，旧实现在这里溢出 5.0px）；
      // 后面几个是「面板偏矮」的边界，最矮的连一行都放不下。
      const List<double> heights = <double>[600, 520, 443, 400, 360, 300, 240, 180, 140, 110];

      for (final double height in heights) {
        await _pumpPanel(
          tester,
          panelHeight: height,
          showTranslation: true,
        );

        expect(
          tester.takeException(),
          isNull,
          reason: '卡拉OK面板高 $height 时开启译文不应有任何渲染异常（含 RenderFlex overflowed）',
        );
      }
    });

    testWidgets('开启译文时，每行高度都不小于「原文 + 译文」需要的高度', (WidgetTester tester) async {
      const List<double> heights = <double>[600, 443, 360, 300, 240];
      final double required = _requiredLineExtent(withTranslation: true);

      for (final double height in heights) {
        await _pumpPanel(
          tester,
          panelHeight: height,
          showTranslation: true,
        );

        final List<_Slot> layout = _slotLayout(tester);
        expect(layout, isNotEmpty, reason: '面板高 $height 时至少要显示一行');

        for (final _Slot slot in layout) {
          expect(
            slot.height,
            greaterThanOrEqualTo(required - _kTolerance),
            reason: '面板高 $height 的槽位 ${slot.key} 只有 ${slot.height}，'
                '装不下译文需要的 $required —— 译文会被裁掉',
          );
        }
      }
    });

    testWidgets('译文文本真实上屏，不是被藏起来', (WidgetTester tester) async {
      await _pumpPanel(tester, panelHeight: 360, showTranslation: true);

      // 当前行（索引 4，偶数所以有译文）的译文必须真的渲染出来。
      expect(find.text('Lyric line 4 translation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('关闭译文时排版与旧实现逐像素一致：8 行、行高 35、当前行在第 4 行',
        (WidgetTester tester) async {
      const double panelHeight = 360.0;
      // 可用高度 = 360 - 80 = 280；旧实现固定 280 / 8 = 35。
      const double available = panelHeight - _kVerticalPadding;
      await _pumpPanel(tester, panelHeight: panelHeight, showTranslation: false);

      final List<_Slot> layout = _slotLayout(tester);
      expect(layout.length, _kMaxVisibleLines, reason: '不开译文时仍应显示 8 行');

      for (final _Slot slot in layout) {
        expect(
          slot.height,
          closeTo(available / _kMaxVisibleLines, _kTolerance),
          reason: '不开译文的路径必须与旧实现完全一致（35px），槽位 ${slot.key}',
        );
      }

      // 当前歌词（索引 4）仍落在第 4 行（窗口内索引 3）。
      expect(layout[3].key, 'lyric_4');
      expect(tester.takeException(), isNull);
    });

    testWidgets('空行占位与歌词行等高，滚动时窗口不跳动', (WidgetTester tester) async {
      // 当前行是第一句：窗口前几个槽位是空行占位。
      await _pumpPanel(
        tester,
        panelHeight: 600,
        showTranslation: true,
        currentLyricIndex: 0,
      );

      final List<_Slot> layout = _slotLayout(tester);
      final List<String> emptyKeys = layout
          .where((_Slot s) => s.key.startsWith('empty_'))
          .map((_Slot s) => s.key)
          .toList();
      expect(emptyKeys, isNotEmpty, reason: '当前行是第一句时，上方应有空行占位');

      final double first = layout.first.height;
      for (final _Slot slot in layout) {
        expect(
          slot.height,
          closeTo(first, _kTolerance),
          reason: '空行占位与歌词行必须等高，否则滚动会整块跳动'
              '（${slot.key}=${slot.height} vs $first）',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('当前行（双层 Text）与普通行等高，Stack 不额外增高',
        (WidgetTester tester) async {
      // 当前行索引 4 用的是「描边层 + 填充层」双 Text 的 Stack，普通行是单层
      // AnimatedDefaultTextStyle。若双层结构更高，行高模型就会失效 —— 这里直接钉住。
      await _pumpPanel(tester, panelHeight: 600, showTranslation: true);

      final List<_Slot> layout = _slotLayout(tester);
      final _Slot current = layout.firstWhere((_Slot s) => s.key == 'lyric_4');
      final _Slot other = layout.firstWhere((_Slot s) => s.key == 'lyric_5');

      expect(
        current.height,
        closeTo(other.height, _kTolerance),
        reason: '当前行（双层）与普通行（单层）必须等高，'
            '否则「当前行字更大」的行高模型会与实测不符',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('面板够高时：开译文仍是 8 行，当前行仍在第 4 行', (WidgetTester tester) async {
      // 单行带译文需要 18*1.4 + 2 + 13*1.4 + 1 = 46.4；
      // 8 行 = 371.2，加上下 80 padding → 451.2，600 绰绰有余。
      await _pumpPanel(tester, panelHeight: 600, showTranslation: true);

      final List<_Slot> layout = _slotLayout(tester);
      expect(layout.length, _kMaxVisibleLines, reason: '空间够时行数不应减少');
      expect(
        layout.indexWhere((_Slot s) => s.key == 'lyric_4'),
        3,
        reason: '当前歌词仍固定在第 4 行，视觉行为与旧实现一致',
      );
      // 520 可用高度均分给 8 行 = 65，远大于内容需要的 46.4。
      for (final _Slot slot in layout) {
        expect(slot.height, closeTo(520.0 / 8, _kTolerance));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('面板偏矮时：减少行数而不是压缩行高，当前行保持略高于正中',
        (WidgetTester tester) async {
      // 可用 280，单行带译文需要 46.4 → 只放得下 floor(280 / 46.4) = 6 行，
      // 行高回填为 280 / 6 = 46.67（≥ 46.4，所以不可能溢出）。
      await _pumpPanel(tester, panelHeight: 360, showTranslation: true);

      final List<_Slot> layout = _slotLayout(tester);
      expect(
        layout.length,
        6,
        reason: '280px 只装得下 6 行带译文的歌词，应减少行数而不是把译文挤掉',
      );
      for (final _Slot slot in layout) {
        expect(
          slot.height,
          closeTo(280.0 / 6, _kTolerance),
          reason: '行数定下来后可用高度应均分回每行，窗口仍铺满面板',
        );
      }
      expect(
        layout.indexWhere((_Slot s) => s.key == 'lyric_4'),
        2,
        reason: '6 行时当前行落在索引 2（略高于正中），与 8 行时的索引 3 同构',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('无歌词时仍给提示，不受行高模型影响', (WidgetTester tester) async {
      await _pumpPanel(
        tester,
        panelHeight: 360,
        showTranslation: true,
        lyrics: const <LyricLine>[],
      );

      expect(find.text('暂无歌词'), findsOneWidget);
      expect(_slots, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
