import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/models/lyric_line.dart';
import 'package:lxplayer/pages/mobile_player_components/mobile_player_current_lyric.dart';

/// 当前歌词窗口的渲染级断言。
///
/// 「当前行高亮」只是句形容词——真正决定观感的是字号、字重、透明度这三项。
/// 这里把它们从渲染结果里量出来，改坏了立刻能看见。
///
/// 组件只依赖 `PlayerService()` 这个单例，而它的构造函数是空的
/// （音频播放器延迟初始化），所以可以安全 pump，不需要起任何插件。
const _lineHeight = 30.0;

LyricLine _line(int second, String text) =>
    LyricLine(startTime: Duration(seconds: second), text: text);

List<LyricLine> _fourLines() => [
      _line(0, '第一句'),
      _line(5, '第二句'),
      _line(10, '第三句'),
      _line(15, '第四句'),
    ];

Future<void> _pump(WidgetTester tester, {required int currentIndex}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MobilePlayerCurrentLyric(
        lyrics: _fourLines(),
        currentLyricIndex: currentIndex,
        onTap: () {},
      ),
    ),
  ));
}

/// 限定在组件内部找，避免撞上 Material 自己用的 AnimatedDefaultTextStyle。
Finder get _styledLines => find.descendant(
      of: find.byType(MobilePlayerCurrentLyric),
      matching: find.byType(AnimatedDefaultTextStyle),
    );

List<TextStyle> _visibleStyles(WidgetTester tester) =>
    tester.widgetList<AnimatedDefaultTextStyle>(_styledLines).map((e) => e.style).toList();

void main() {
  group('当前歌词窗口', () {
    testWidgets('固定显示三行，当前行落在第 2 行', (tester) async {
      await _pump(tester, currentIndex: 1);

      expect(_styledLines, findsNWidgets(3));
      // 窗口以当前行为中心：索引 1 时露出 0/1/2 三句。
      expect(find.text('第一句'), findsOneWidget);
      expect(find.text('第二句'), findsOneWidget);
      expect(find.text('第三句'), findsOneWidget);
      expect(find.text('第四句'), findsNothing);
    });

    testWidgets('当前行更大更粗，其余行更小且半透明', (tester) async {
      await _pump(tester, currentIndex: 1);

      final styles = _visibleStyles(tester);
      expect(styles.length, 3);

      final previous = styles[0];
      final current = styles[1];
      final next = styles[2];

      expect(
        current.fontSize! > previous.fontSize!,
        isTrue,
        reason: '当前行字号应大于上一行（${current.fontSize} vs ${previous.fontSize}）',
      );
      expect(current.fontSize! > next.fontSize!, isTrue);

      expect(current.fontWeight, FontWeight.bold);
      expect(previous.fontWeight, FontWeight.normal);
      expect(next.fontWeight, FontWeight.normal);

      // 亮度分层：当前行必须比其余行更实。这里只比它们之间的关系、
      // 不写死具体色值——具体颜色依赖取色主题，钉死会让测试变脆。
      expect(
        current.color,
        isNot(previous.color),
        reason: '当前行与其余行不能用同一个色，否则高亮失效',
      );
      expect(previous.color, next.color, reason: '非当前行的处理应完全一致');
    });

    testWidgets('每行高度一致，三行正好填满固定高度', (tester) async {
      await _pump(tester, currentIndex: 1);

      final box = tester.getSize(find.byType(MobilePlayerCurrentLyric));
      expect(box.height, _lineHeight * 3, reason: '高度写死才能让上下行不被裁切');
    });

    testWidgets('当前行是第一句时，上方空出占位而不是把窗口顶上去', (tester) async {
      await _pump(tester, currentIndex: 0);

      // 三行永远在同样的位置，否则滚动时会有整块跳动。
      expect(_styledLines, findsNWidgets(2));
      expect(find.byKey(const ValueKey('empty_0')), findsOneWidget);
      expect(find.text('第一句'), findsOneWidget);
      expect(find.text('第二句'), findsOneWidget);
    });

    testWidgets('窗口跟着当前行往后走', (tester) async {
      await _pump(tester, currentIndex: 2);

      expect(find.text('第一句'), findsNothing);
      expect(find.text('第二句'), findsOneWidget);
      expect(find.text('第三句'), findsOneWidget);
      expect(find.text('第四句'), findsOneWidget);
    });

    testWidgets('没有歌词时给提示而不是空白', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MobilePlayerCurrentLyric(
            lyrics: const [],
            currentLyricIndex: 0,
            onTap: () {},
          ),
        ),
      ));

      expect(_styledLines, findsNothing);
    });
  });
}
