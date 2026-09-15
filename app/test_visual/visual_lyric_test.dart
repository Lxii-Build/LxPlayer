import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/models/lyric_line.dart';
import 'package:lxplayer/pages/player_components/player_lyrics_panel.dart';

/// 当前歌词窗口的视觉基线。
///
/// 用固定歌词 + 固定当前行（索引 4）构造，观察「8 行居中、当前行放大加粗、
/// 翻译行小字」的排版。`PlayerLyricsPanel` 只读 `PlayerService().themeColorNotifier`
/// （一个 `ValueNotifier<Color?>`，默认 null），不触发任何平台/网络调用，
/// 因此渲染可重复。
List<LyricLine> _sampleLyrics() => <LyricLine>[
      for (int i = 0; i < 12; i++)
        LyricLine(
          startTime: Duration(seconds: i * 5),
          text: '第 $i 行歌词示例文本',
          translation: i.isEven ? 'Lyric line $i translation' : null,
        ),
    ];

void main() {
  testWidgets('当前歌词窗口', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SizedBox(
            width: 440,
            height: 360,
            child: PlayerLyricsPanel(
              lyrics: _sampleLyrics(),
              currentLyricIndex: 4,
              showTranslation: true,
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(PlayerLyricsPanel),
      matchesGoldenFile('goldens/lyric_window.png'),
    );
  });
}
