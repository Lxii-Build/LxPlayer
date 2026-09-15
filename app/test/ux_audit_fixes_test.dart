import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/models/track.dart';
import 'package:lxplayer/pages/home_page/mobile_personal_fm.dart';
import 'package:lxplayer/pages/home_page/newsong_cards.dart';
import 'package:lxplayer/pages/mini_player_window_page.dart';
import 'package:lxplayer/widgets/lx_image_fallback.dart';

/// 体验缺陷修复（A 组）的回归测试。
///
/// 只钉**不依赖网络 / 平台通道**的部分：
///   - A1：图片失败兜底组件的渲染；
///   - A2：卡片底色取自主题（`surfaceContainerHigh`）；
///   - A4：私人 FM 信息列在大字号下不溢出、正常字号高度不变；
///   - A5：迷你播放器控制按钮的触控目标 ≥44×44；
///   - A6：播放队列弹窗内容区（`MiniPlayerQueueDialogBody`）渲染真实队列。
///
/// A3（写死浅灰占位改主题色）落在 `CachedNetworkImage` 的 placeholder 里，其宿主
/// 页面还要走 `netease_recommend_service` 拉数据，纯 widget 测试里拿不到——
/// 与 `home_surface_consistency_test.dart` 中的取舍一致，由 `flutter analyze` +
/// `test_visual/` 兜底。

void main() {
  group('A1 图片失败兜底组件', () {
    testWidgets('默认渲染音乐图标，且不吃异常', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
        home: const Scaffold(body: Center(child: LxImageFallback())),
      ));

      expect(find.byType(LxImageFallback), findsOneWidget);
      final Icon icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.music_note);
      expect(icon.size, 28);
      expect(tester.takeException(), isNull);
    });

    testWidgets('图标与尺寸可覆盖（供不同位置的兜底复用）', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: LxImageFallback(icon: Icons.broken_image_outlined, iconSize: 40),
          ),
        ),
      ));

      final Icon icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.broken_image_outlined);
      expect(icon.size, 40);
    });
  });

  group('A2 卡片底色取自主题', () {
    testWidgets('新歌卡片底色 = colorScheme.surfaceContainerHigh（不再写死深/白）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
        home: Scaffold(
          body: NewsongCard(
            song: const <String, dynamic>{
              'name': '测试歌曲',
              'al': <String, dynamic>{'picUrl': 'https://example.com/cover.jpg'},
              'ar': <dynamic>[
                <String, dynamic>{'name': '测试歌手'},
              ],
            },
          ),
        ),
      ));

      final BuildContext context = tester.element(find.byType(NewsongCard));
      final ColorScheme cs = Theme.of(context).colorScheme;

      final AnimatedContainer card = tester.widget<AnimatedContainer>(
        find
            .descendant(of: find.byType(NewsongCard), matching: find.byType(AnimatedContainer))
            .first,
      );
      expect((card.decoration as BoxDecoration).color, cs.surfaceContainerHigh);
    });
  });

  group('A4 私人 FM 信息列高度自适应', () {
    // 高度契约：正常字号恒为 120（与改造前逐像素一致），放大字号时按标题字号
    // 的缩放比线性增高。
    test('heightFor：正常字号 120，2× 字号 240，缩小字号不缩容器', () {
      expect(FmInfoColumn.heightFor(TextScaler.noScaling), 120);
      expect(FmInfoColumn.heightFor(TextScaler.linear(1.0)), 120);
      expect(FmInfoColumn.heightFor(TextScaler.linear(2.0)), 240);
      // 系统「缩小字号」时容器不跟着缩，保证内容区不会先于文字变紧。
      expect(FmInfoColumn.heightFor(TextScaler.linear(0.8)), 120);
    });

    Future<void> pumpColumn(WidgetTester tester, double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 640),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  child: FmInfoColumn(
                    title: '很长的歌曲标题' * 3,
                    subtitle: '很长的歌手名字' * 4,
                    isPlaying: false,
                    onSkip: () {},
                    onPlayPause: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('正常字号下容器高度是 120（观感与改造前一致）', (WidgetTester tester) async {
      await pumpColumn(tester, 1.0);

      expect(tester.getSize(find.byType(FmInfoColumn)).height, 120);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2× 字号下不溢出（旧实现的固定高 120 会 RenderFlex overflow）',
        (WidgetTester tester) async {
      await pumpColumn(tester, 2.0);

      expect(tester.getSize(find.byType(FmInfoColumn)).height, 240);
      expect(
        tester.takeException(),
        isNull,
        reason: '2× 字号下容器应随之增高，绝不能出现 RenderFlex overflowed',
      );
    });

    testWidgets('更大的 3× 字号同样不溢出', (WidgetTester tester) async {
      await pumpColumn(tester, 3.0);

      expect(tester.takeException(), isNull);
    });
  });

  group('A5 迷你播放器控制按钮触控目标', () {
    Future<void> pumpButton(WidgetTester tester, {VoidCallback? onPressed}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: MiniPlayerControlButton(
              icon: Icons.play_arrow_rounded,
              onPressed: onPressed ?? () {},
              size: 20,
            ),
          ),
        ),
      ));
    }

    testWidgets('可点状态下触控目标不小于 44×44', (WidgetTester tester) async {
      await pumpButton(tester);

      final Size size = tester.getSize(find.byType(MiniPlayerControlButton));
      expect(size.width, greaterThanOrEqualTo(MiniPlayerControlButton.minTapTarget));
      expect(size.height, greaterThanOrEqualTo(MiniPlayerControlButton.minTapTarget));
      expect(MiniPlayerControlButton.minTapTarget, 44);
    });

    testWidgets('禁用态（onPressed 为 null）也保持同样的触控目标', (WidgetTester tester) async {
      await pumpButton(tester, onPressed: null);

      final Size size = tester.getSize(find.byType(MiniPlayerControlButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('A6 播放队列弹窗内容区', () {
    // 「更多」按钮原本 onPressed 为空；`_showQueueDialog` 是完整实现却从未被引用。
    // 该弹窗是本 `State` 的私有方法、且依赖 `PlayerService` + `window_manager`，
    // 单测里无法直接调用。因此把内容区抽成独立 widget 直接构建、断言它确实渲染出
    // 队列内容——这比只断言「不抛异常」更强。
    List<Track> fixture() => <Track>[
          Track(id: '1', name: '歌曲甲', artists: '歌手A', album: '', picUrl: ''),
          Track(id: '2', name: '歌曲乙', artists: '歌手B', album: '', picUrl: ''),
        ];

    Future<void> pumpBody(
      WidgetTester tester, {
      required List<Track> queue,
      required int currentIndex,
      ValueChanged<Track>? onTrackTap,
    }) async {
      await tester.pumpWidget(fluent.FluentApp(
        home: Center(
          child: MiniPlayerQueueDialogBody(
            queue: queue,
            currentIndex: currentIndex,
            width: 360,
            height: 400,
            currentColor: Colors.blue,
            dividerColor: Colors.grey,
            onTrackTap: onTrackTap ?? (_) {},
          ),
        ),
      ));
    }

    testWidgets('渲染队列里的每首歌（歌名 + 歌手）', (WidgetTester tester) async {
      await pumpBody(tester, queue: fixture(), currentIndex: 0);

      expect(find.text('歌曲甲'), findsOneWidget);
      expect(find.text('歌曲乙'), findsOneWidget);
      expect(find.text('歌手A'), findsOneWidget);
      expect(find.text('歌手B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('当前播放项高亮：仅它带等高线图标', (WidgetTester tester) async {
      await pumpBody(tester, queue: fixture(), currentIndex: 1);

      expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);
    });

    testWidgets('点击某一行回调携带对应 Track', (WidgetTester tester) async {
      Track? tapped;
      await pumpBody(
        tester,
        queue: fixture(),
        currentIndex: 0,
        onTrackTap: (t) => tapped = t,
      );

      await tester.tap(find.text('歌曲乙'));
      // fluent 的 HoverButton 在点击后会留一个 ~100ms 的悬停定时器；pump 足够时长
      // 让它落地，否则测试结束时会因残留 pending timer 触发断言。
      await tester.pump(const Duration(milliseconds: 200));

      expect(tapped, isNotNull);
      expect(tapped!.name, '歌曲乙');
    });

    testWidgets('空队列显示占位文案且不抛异常', (WidgetTester tester) async {
      await pumpBody(tester, queue: const <Track>[], currentIndex: -1);

      expect(find.text('无播放队列'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
