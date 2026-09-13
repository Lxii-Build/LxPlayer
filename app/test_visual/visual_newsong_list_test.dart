import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/pages/home_page/mobile_newsong_list.dart';

/// 「个性化新歌」列表（移动端）修复后的视觉基线。
///
/// 为什么单独建：这个列表此前用裸 `Image.network`（不传网易云 UA）导致封面全挂、
/// 只剩音符占位，用户截图里就是「一排空盒子」。修好之后用一张图钉住观感——
/// 图里应该能看到每行的封面位（测试环境走 `LxImageFallback`）、歌名与歌手两行文字。
///
/// 与 `visual_toplist_card_test.dart` 一致，必须 mock `path_provider`，
/// 否则 `CachedNetworkImage` 的默认缓存管理器抛 `MissingPluginException` 把用例打红。

/// 真实 `/personalized/newsong` 的返回样例（实测：嵌套 song 用旧式 artists/album）。
List<Map<String, dynamic>> _realList() => <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 3425638996,
        'type': 4,
        'name': '互删 (我走以后)',
        'picUrl':
            'http://p1.music.126.net/nfDVr6WopOJax11vq5brPQ==/109951173820334666.jpg',
        'song': <String, dynamic>{
          'name': '互删 (我走以后)',
          'id': 3425638996,
          'artists': <dynamic>[
            <String, dynamic>{'name': '江辰'},
          ],
          'album': <String, dynamic>{
            'name': '互删 (我走以后)',
            'picUrl':
                'http://p1.music.126.net/nfDVr6WopOJax11vq5brPQ==/109951173820334666.jpg',
          },
        },
      },
      <String, dynamic>{
        'id': 2,
        'type': 4,
        'name': '第二首歌名比较长用来验证省略号',
        'picUrl': 'http://p1.music.126.net/xxx==/2.jpg',
        'song': <String, dynamic>{
          'name': '第二首歌名比较长用来验证省略号',
          'id': 2,
          'artists': <dynamic>[
            <String, dynamic>{'name': '歌手甲'},
            <String, dynamic>{'name': '歌手乙'},
          ],
          'album': <String, dynamic>{
            'name': '专辑',
            'picUrl': 'http://p1.music.126.net/xxx==/2.jpg',
          },
        },
      },
    ];

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    return Directory.systemTemp.createTempSync('lxplayer_newsong_golden_').path;
  });
}

void main() {
  setUpAll(_mockPathProvider);

  testWidgets('个性化新歌列表（含封面兜底、歌名、歌手）', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: MobileNewsongList(list: _realList()),
          ),
        ),
      ),
    );
    // 图片走 errorWidget 是异步的，多 pump 一次让兜底落地。
    await tester.pump(const Duration(milliseconds: 100));

    await expectLater(
      find.byType(MobileNewsongList),
      matchesGoldenFile('goldens/newsong_list.png'),
    );
  });
}
