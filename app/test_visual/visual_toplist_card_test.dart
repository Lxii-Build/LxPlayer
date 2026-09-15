import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/models/track.dart';
import 'package:lxplayer/pages/home_page/charts_tab.dart';

/// 榜单卡（`ToplistTrackCard`）的视觉基线。
///
/// 为什么单独建这个文件：榜单卡此前没有任何视觉覆盖——它内含
/// `CachedNetworkImage`，测试环境拿不到网络图片，所以 `visual_home_sections_test.dart`
/// 刻意避开了真实业务卡。但「封面外那圈底」恰恰是只有看图才能判断的问题，
/// 不截图就等于没验证。
///
/// 做法：用 `picUrl: ''` 构造曲目，让图片走 `errorWidget`（`LxImageFallback`）。
/// 兜底组件占的是**同一块几何区域**，所以卡宽卡高、圆角、封面占比、文字位置、
/// 有没有多余那圈底，全都能从截图上看出来——只是封面内容是灰底音符而不是真实封面。
///
/// 另外必须 mock `path_provider`：`CachedNetworkImage` 的默认缓存管理器要拿临时目录，
/// 测试环境没有平台实现，会抛 `MissingPluginException` 把用例打红（截图仍会生成，
/// 但红的测试不能留）。
Track _stubTrack(int id) => Track(
      id: id,
      name: '示例曲目名称 $id',
      artists: '示例歌手 · 示例歌手二',
      album: '示例专辑',
      picUrl: '',
    );

Future<void> _noop() async {}

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    // 所有查询（临时目录/支持目录/缓存目录…）都回同一个可写目录即可，
    // 本用例只关心布局，不关心缓存实际落在哪里。
    return Directory.systemTemp.createTempSync('lxplayer_golden_').path;
  });
}

void main() {
  setUpAll(_mockPathProvider);

  testWidgets('榜单卡单卡（含排名角标与文字）', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(220, 280));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: ToplistTrackCard(
              track: _stubTrack(1),
              rank: 0, // 前三名：角标带主题色描边
              checkLoginStatus: _noop,
            ),
          ),
        ),
      ),
    );
    // 图片走 errorWidget 是异步的，多 pump 一次让兜底落地。
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(ToplistTrackCard),
      matchesGoldenFile('goldens/toplist_track_card.png'),
    );
  });

  testWidgets('榜单卡横排（含间距与前三名/普通名次对比）', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 260));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final rank in [0, 1, 3])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: ToplistTrackCard(
                      track: _stubTrack(rank + 1),
                      rank: rank,
                      checkLoginStatus: _noop,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(Row),
      matchesGoldenFile('goldens/toplist_track_row.png'),
    );
  });
}
