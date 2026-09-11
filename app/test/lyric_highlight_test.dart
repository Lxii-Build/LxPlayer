import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/models/lyric_line.dart';
import 'package:lxplayer/pages/mobile_player_components/mobile_player_karaoke_lyric.dart';

/// 当前歌词窗口的渲染级断言。
///
/// 上一版钉的是 `MobilePlayerCurrentLyric`——那个组件在生产代码里零引用，
/// App 真正上屏的是 `MobilePlayerKaraokeLyric`（经典卡拉OK布局）。钉一个没人用的
/// 组件等于什么都没测：把它删掉、真组件改坏了，这里照样绿。
/// 现在改成钉真正渲染的组件，并且**用它的真实渲染方式**做断言：
///   当前行 = `_buildKaraokeText` 的 Stack（底层半透明 + 上层高亮裁剪，两层都是
///  显式 bold 的 Text，高亮层带发光阴影），**不是** `AnimatedDefaultTextStyle`；
///   非当前行才走 `AnimatedDefaultTextStyle`（字号更小、字重 normal、半透明）。
///
/// 组件只依赖 `PlayerService()` 这个单例，而它的构造函数是空的（音频播放器延迟
/// 初始化），所以可以安全 pump，不需要起任何插件。
///
/// 不用 golden 图：基准 PNG 必须在本地跑 `flutter test --update-goldens` 生成并提交，
/// 在这个环境里无法产出，硬写只会得到一个永远失败的测试。

/// 与组件内的窗口规格保持一致（`mobile_player_karaoke_lyric.dart:122-126`）。
const int _visibleLines = 3;
const double _lineHeight = 30.0;
/// 组件为字体度量误差预留的少量冗余高度。
const double _heightSlack = 2.0;

LyricLine _line(int second, String text) =>
    LyricLine(startTime: Duration(seconds: second), text: text);

List<LyricLine> _fourLines() => [
      _line(0, '第一句'),
      _line(5, '第二句'),
      _line(10, '第三句'),
      _line(15, '第四句'),
    ];

Future<void> _pump(
  WidgetTester tester, {
  required int currentIndex,
  List<LyricLine>? lyrics,
}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MobilePlayerKaraokeLyric(
        lyrics: lyrics ?? _fourLines(),
        currentLyricIndex: currentIndex,
        onTap: () {},
        showTranslation: false,
      ),
    ),
  ));
}

/// 只在歌词组件内部找，避免撞上 Material/Scaffold 自带的同类 widget。
Finder _inComponent(Finder matching) => find.descendant(
      of: find.byType(MobilePlayerKaraokeLyric),
      matching: matching,
    );

/// 三行槽位：有歌词的行键为 `lyric_i`，越界的槽位键为 `empty_i`。
Finder get _slots => find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> &&
          (key.value.startsWith('lyric_') || key.value.startsWith('empty_'));
    });

/// 当前行的两层样式：karaoke 填充的两层都是显式 `bold` 的 Text。
List<TextStyle> _karaokeLayerStyles(WidgetTester tester) => tester
    .widgetList<Text>(_inComponent(find.byType(Text)))
    .where((t) => t.style?.fontWeight == FontWeight.bold)
    .map((t) => t.style!)
    .toList();

/// 非当前行的样式：走 `AnimatedDefaultTextStyle`。
List<TextStyle> _plainLayerStyles(WidgetTester tester) => tester
    .widgetList<AnimatedDefaultTextStyle>(
      _inComponent(find.byType(AnimatedDefaultTextStyle)),
    )
    .map((e) => e.style)
    .toList();

Size _slotSize(WidgetTester tester, String key) =>
    tester.getSize(find.byKey(ValueKey(key)));

void main() {
  group('当前歌词窗口', () {
    testWidgets('固定显示三行，当前行落在第 2 行', (tester) async {
      await _pump(tester, currentIndex: 1);

      // 三个槽位，且都在组件内。
      expect(_inComponent(_slots), findsNWidgets(_visibleLines));

      // 窗口以当前行为中心：索引 1 时露出 0/1/2 三句。
      expect(find.byKey(const ValueKey('lyric_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('lyric_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('lyric_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('lyric_3')), findsNothing);
      expect(find.text('第四句'), findsNothing);
    });

    testWidgets('当前行以卡拉OK填充高亮，其余行更小、更细、半透明', (tester) async {
      await _pump(tester, currentIndex: 1);

      final karaoke = _karaokeLayerStyles(tester);
      final plain = _plainLayerStyles(tester);

      // 三行里除当前行外，另两行走普通行渲染；当前行是两层卡拉OK文字。
      expect(plain.length, 2,
          reason: '三行中只有当前行走 karaoke 渲染，其余两行是普通行');
      expect(karaoke.length, 2,
          reason: '当前行 = 底层半透明 + 上层高亮，两层都是显式 bold 的 Text');

      final currentSize = karaoke.first.fontSize!;
      final otherSize = plain.first.fontSize!;
      expect(
        currentSize > otherSize,
        isTrue,
        reason: '当前行字号应大于其余行（$currentSize vs $otherSize）',
      );

      expect(karaoke.every((s) => s.fontWeight == FontWeight.bold), isTrue,
          reason: '卡拉OK填充的两层都应是粗体');
      expect(plain.every((s) => s.fontWeight == FontWeight.normal), isTrue,
          reason: '非当前行应是正常字重');

      // 当前行分底色与高亮两层，两者必须不同色，否则填充看不出来。
      final karaokeColors = karaoke.map((s) => s.color).toSet();
      expect(karaokeColors.length, 2,
          reason: '当前行底色与高亮色必须不同，否则卡拉OK填充失效');
      // 非当前行没有高亮层，它的颜色就是当前行的底色。
      expect(karaokeColors.contains(plain.first.color), isTrue,
          reason: '非当前行的处理应与当前行的底色一致，只是没有高亮层');

      // 只有高亮层带发光阴影。
      final withGlow =
          karaoke.where((s) => s.shadows != null && s.shadows!.isNotEmpty).toList();
      expect(withGlow.length, 1, reason: '只有高亮层带发光，底色层不带');
      expect(withGlow.first.color, isNot(plain.first.color),
          reason: '带发光的那层就是被点亮的当前行');
    });

    testWidgets('每行高度一致，三行等分填满固定高度', (tester) async {
      await _pump(tester, currentIndex: 1);

      final box = tester.getSize(find.byType(MobilePlayerKaraokeLyric));
      expect(
        box.height,
        _visibleLines * _lineHeight + _heightSlack,
        reason: '窗口高度写死才能让上下行不被裁切',
      );

      final heights = [
        for (var i = 0; i < _visibleLines; i++) _slotSize(tester, 'lyric_$i').height,
      ];
      expect(heights.toSet().length, 1, reason: '三行等分，滚动窗口才不会跳动');
      expect(heights.first, closeTo(box.height / _visibleLines, 0.5));
    });

    testWidgets('当前行是第一句时，上方空出占位而不是把窗口顶上去', (tester) async {
      await _pump(tester, currentIndex: 0);

      // 首槽是空占位，三行永远在同样的位置，否则滚动时会有整块跳动。
      expect(find.byKey(const ValueKey('empty_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('lyric_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('lyric_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('lyric_2')), findsNothing);
      expect(find.text('第三句'), findsNothing);
    });

    testWidgets('窗口跟着当前行往后走', (tester) async {
      await _pump(tester, currentIndex: 2);

      expect(find.text('第一句'), findsNothing);
      expect(find.byKey(const ValueKey('lyric_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('lyric_2')), findsOneWidget);
      expect(find.byKey(const ValueKey('lyric_3')), findsOneWidget);
    });

    testWidgets('没有歌词时给提示而不是空白', (tester) async {
      await _pump(tester, currentIndex: 0, lyrics: const []);

      expect(find.text('暂无歌词'), findsOneWidget);
      expect(_plainLayerStyles(tester), isEmpty);
      expect(_karaokeLayerStyles(tester), isEmpty);
      expect(find.byKey(const ValueKey('lyric_0')), findsNothing);
    });
  });
}
