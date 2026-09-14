import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lxplayer/pages/home_page/mobile_newsong_list.dart';
import 'package:lxplayer/pages/home_page/newsong_item.dart';

/// 「个性化新歌」字段解析的回归测试。
///
/// 这一组的唯一目的是**钉死「又变成空盒子」**：用真实的
/// `/personalized/newsong` 返回样例断言解析出的歌名 / 歌手 / 封面 URL 都不为空。
///
/// 真实样例取自直连 `music.163.com/api/personalized/newsong` 的实测返回：
/// 每一项形如 `{id, type, name, picUrl, song: {name, artists:[...], album:{...}}}`——
/// **嵌套 `song` 用的是旧式 `artists` / `album` 键**（不是新式的 `ar` / `al`），
/// 且外层与内层都带 `picUrl`（`http://`，明文）。

/// 与真实接口一致的单曲项。
Map<String, dynamic> _realNewsongItem() => <String, dynamic>{
      'id': 3425638996,
      'type': 4,
      'name': '互删 (我走以后)',
      'picUrl':
          'http://p1.music.126.net/nfDVr6WopOJax11vq5brPQ==/109951173820334666.jpg',
      'canDislike': false,
      'song': <String, dynamic>{
        'name': '互删 (我走以后)',
        'id': 3425638996,
        'artists': <dynamic>[
          <String, dynamic>{'name': '江辰', 'id': 12641765},
        ],
        'album': <String, dynamic>{
          'name': '互删 (我走以后)',
          'picUrl':
              'http://p1.music.126.net/nfDVr6WopOJax11vq5brPQ==/109951173820334666.jpg',
        },
      },
    };

/// 让 `CachedNetworkImage` 的默认缓存管理器拿到临时目录。
///
/// 不 mock 会抛 `MissingPluginException`（测试环境没有 `path_provider` 平台实现），
/// 与 `test_visual/visual_toplist_card_test.dart` 的取舍一致。
void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    return Directory.systemTemp.createTempSync('lxplayer_newsong_').path;
  });
}

void main() {
  setUpAll(_mockPathProvider);

  group('NewsongItem 解析', () {
    test('真实接口项（嵌套 song + 旧式 album/artists）：歌名/歌手/封面都非空', () {
      final item = NewsongItem.fromJson(_realNewsongItem());

      expect(item.name, '互删 (我走以后)');
      expect(item.artists, '江辰');
      expect(item.album, '互删 (我走以后)');
      expect(item.picUrl, isNotEmpty);
      expect(item.picUrl, contains('p1.music.126.net'));
      expect(item.id, 3425638996);

      // 播放用的 Track 也必须带上封面，否则播放器 / 通知栏还是空封面。
      final track = item.toTrack();
      expect(track.name, '互删 (我走以后)');
      expect(track.artists, '江辰');
      expect(track.picUrl, isNotEmpty);
    });

    test('新式键（al/ar）也认', () {
      final item = NewsongItem.fromJson(<String, dynamic>{
        'song': <String, dynamic>{
          'id': 1,
          'name': '歌A',
          'al': <String, dynamic>{'name': '专辑A', 'picUrl': 'https://cdn/a.jpg'},
          'ar': <dynamic>[
            <String, dynamic>{'name': '歌手A'},
          ],
        },
      });

      expect(item.name, '歌A');
      expect(item.artists, '歌手A');
      expect(item.album, '专辑A');
      expect(item.picUrl, 'https://cdn/a.jpg');
    });

    test('已拍平（无 song 包裹）也认', () {
      final item = NewsongItem.fromJson(<String, dynamic>{
        'id': 2,
        'name': '歌B',
        'al': <String, dynamic>{'picUrl': 'https://cdn/b.jpg'},
        'ar': <dynamic>[
          <String, dynamic>{'name': '歌手B'},
        ],
      });

      expect(item.name, '歌B');
      expect(item.artists, '歌手B');
      expect(item.picUrl, 'https://cdn/b.jpg');
    });

    test('缺 album/al 不再抛 TypeError，歌名仍在（旧实现会整行崩）', () {
      late NewsongItem item;
      expect(
        () => item = NewsongItem.fromJson(<String, dynamic>{
          'id': 3,
          'name': '歌C',
          'ar': <dynamic>[
            <String, dynamic>{'name': '歌手C'},
          ],
        }),
        returnsNormally,
        reason: '旧实现 (song["al"] ?? song["album"] ?? {}) as Map<String, dynamic> '
            '里的 {} 是 Map<dynamic,dynamic>，缺键时抛 _TypeError，整行渲染失败',
      );
      expect(item.name, '歌C');
      expect(item.artists, '歌手C');
      expect(item.picUrl, '');
    });

    test('内层缺 name/pic 时回落到顶层', () {
      final item = NewsongItem.fromJson(<String, dynamic>{
        'name': '顶层歌名',
        'picUrl': 'https://cdn/top.jpg',
        'song': <String, dynamic>{
          'id': 4,
          'artists': <dynamic>[
            <String, dynamic>{'name': '歌手D'},
          ],
        },
      });

      expect(item.name, '顶层歌名');
      expect(item.picUrl, 'https://cdn/top.jpg');
      expect(item.artists, '歌手D');
    });

    test('多歌手以 / 连接，空字符串歌手被丢弃', () {
      final item = NewsongItem.fromJson(<String, dynamic>{
        'song': <String, dynamic>{
          'name': '歌E',
          'ar': <dynamic>[
            <String, dynamic>{'name': '甲'},
            <String, dynamic>{'name': ''},
            <String, dynamic>{'name': '乙'},
          ],
        },
      });

      expect(item.artists, '甲 / 乙');
    });

    test('完全空的项不抛异常、hasData 为 false', () {
      final item = NewsongItem.fromJson(<String, dynamic>{});
      expect(item.name, '');
      expect(item.artists, '');
      expect(item.picUrl, '');
      expect(item.hasData, isFalse);
      expect(item.toTrack().name, '');
    });
  });

  group('MobileNewsongList 渲染（真实样例）', () {
    testWidgets('歌名与歌手真的上屏，且不抛异常', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MobileNewsongList(list: <Map<String, dynamic>>[_realNewsongItem()]),
        ),
      ));
      // 图片失败走 errorWidget 是异步的，多 pump 一次让兜底落地。
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('互删 (我走以后)'), findsOneWidget);
      expect(find.text('江辰'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('缺 album 的项也不再整行崩（旧实现此行会抛 _TypeError）',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MobileNewsongList(list: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 3,
              'name': '无专辑的歌',
              'ar': <dynamic>[
                <String, dynamic>{'name': '某歌手'},
              ],
            },
          ]),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('无专辑的歌'), findsOneWidget);
      expect(find.text('某歌手'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('封面改用带请求头的 CachedNetworkImage，整行不再只剩空盒子',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MobileNewsongList(list: <Map<String, dynamic>>[_realNewsongItem()]),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));

      // 这里**不**断言 LxImageFallback 真的渲染出来，因为在 widget 测试里
      // CachedNetworkImage 会一直停在下载态、**走不到 errorWidget**（实测等 2
      // 秒仍然是 0 个）。强行断言只会得到一条永远失败的测试。
      //
      // 改为钉住「图片问题」的修复本身：封面必须走 CachedNetworkImage ——
      // 旧实现是裸 Image.network，是全项目唯一不传 getImageHeaders() 的封面位，
      // 126.net 因此拒绝返回图片。这条断言能防住有人改回裸 Image.network。
      expect(find.byType(CachedNetworkImage), findsOneWidget);

      // 并且无论图片能否加载，整行都不能塌成空盒子：文字必须在、且不能抛异常。
      expect(find.text('互删 (我走以后)'), findsOneWidget);
      expect(find.text('江辰'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
