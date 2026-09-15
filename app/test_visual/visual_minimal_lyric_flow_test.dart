import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/models/lyric_line.dart';
import 'package:lxplayer/pages/player_components/minimal_lyric_flow_layout.dart';
import 'package:lxplayer/pages/player_components/player_karaoke_lyrics_panel.dart';

/// `MinimalLyricFlowLayout`（极简歌词流）的视觉基线。
///
/// 只读 `PlayerService()` 的默认状态（无封面、主题色 null），因此不触发网络/平台调用，
/// 封面会渲染成主题色占位块。`PlayerKaraokeLyricsPanel` 只读
/// `PlayerService().themeColorNotifier` 与 `LyricFontService().currentFontFamily`，
/// 同样无副作用。
///
/// 两张基线分别覆盖：
///   - `minimal_lyric_flow_phone.png`   ：手机竖屏（390×844）下的「上半屏封面 + 下半屏歌词」；
///   - `minimal_lyric_flow_desktop.png` ：桌面大窗口（1280×800），用于人工审阅
///     「封面占上半屏」在宽屏下是否合理（宽屏时封面自动收为居中的正方形，不拉成横幅）。
List<LyricLine> _sampleLyrics() => <LyricLine>[
      for (int i = 0; i < 12; i++)
        LyricLine(
          startTime: Duration(seconds: i * 5),
          text: '第 $i 行歌词示例文本',
          translation: i.isEven ? 'Lyric line $i translation' : null,
        ),
    ];

Widget _host({required Size size, required bool showTranslation}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF1B1B1B),
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: MinimalLyricFlowLayout(
          lyrics: _sampleLyrics(),
          currentLyricIndex: 4,
          showTranslation: showTranslation,
          lyricsPanel: PlayerKaraokeLyricsPanel(
            lyrics: _sampleLyrics(),
            currentLyricIndex: 4,
            showTranslation: showTranslation,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('极简歌词流 · 手机竖屏', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(size: const Size(390, 844), showTranslation: true),
    );

    await expectLater(
      find.byType(MinimalLyricFlowLayout),
      matchesGoldenFile('goldens/minimal_lyric_flow_phone.png'),
    );
  });

  testWidgets('极简歌词流 · 桌面大窗口', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host(size: const Size(1280, 800), showTranslation: true),
    );

    await expectLater(
      find.byType(MinimalLyricFlowLayout),
      matchesGoldenFile('goldens/minimal_lyric_flow_desktop.png'),
    );
  });
}
