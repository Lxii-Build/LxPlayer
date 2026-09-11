import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/pages/home_page/mobile_newsong_list.dart';
import 'package:lxplayer/widgets/lx_surface.dart';

/// 首页表面统一改造的回归断言。
///
/// 背景：上一轮只把最上面那张推荐卡换成了 `LxSurface`，下方区块（新歌列表、
/// 私人FM、歌单网格、榜单卡）还留着各自手写的容器与写死配色，真机上看是
/// 一张新卡压着一堆旧卡。这一轮把下方区块也收敛到 `LxSurface`。
///
/// 这里**刻意只断言不渲染网络封面的路径**：歌单网格 / 私人FM / 榜单卡的内容里
/// 都有 `CachedNetworkImage`，它的 `DefaultCacheManager` 要走 `path_provider`
/// 平台通道，在纯 widget 测试里拿不到，断言它们的渲染只会得到一个与本次改造
/// 无关的失败。那几块的表面一致性由 `test_visual/` 的视觉基线 + `flutter analyze`
/// 覆盖。
const double _kSurfaceRadius = 28;

void main() {
  group('新歌列表', () {
    testWidgets('空数据只出文案，不留空卡壳', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: MobileNewsongList(list: [])),
      ));

      expect(find.text('暂无数据'), findsOneWidget);
      expect(find.byType(LxSurface), findsNothing);
    });
  });

  group('LxSurface 裁剪行为', () {
    // 玻璃分支的外壳是 GlassContainer、Fluent 分支是 fluent.Card，两者都没有
    // clipBehavior 入参。改造前 LxSurface 只把 clipBehavior 交给实心分支的
    // Container，另两支被**静默忽略**——列表首尾行、齐边封面会压出圆角。
    // 新歌列表 / 歌单网格都要靠这个参数，所以把它钉住。

    testWidgets('默认 Clip.none 不插入裁剪节点（既有调用点保持原样）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LxSurface(child: Text('内容'))),
      ));

      expect(
        find.descendant(
          of: find.byType(LxSurface),
          matching: find.byType(ClipRRect),
        ),
        findsNothing,
      );
    });

    testWidgets('Fluent 分支的 clipBehavior 真的生效，且圆角与表面一致', (tester) async {
      await tester.pumpWidget(fluent.FluentApp(
        home: const LxSurface(
          borderRadius: _kSurfaceRadius,
          clipBehavior: Clip.antiAlias,
          child: Text('内容'),
        ),
      ));

      // 不取 `.first`：`fluent.Card` 自己内部也可能有裁剪节点，按「圆角等于表面
      // 圆角」来认我们插入的那一层，避免撞上 Card 的内部实现。
      final clips = tester
          .widgetList<ClipRRect>(find.descendant(
            of: find.byType(LxSurface),
            matching: find.byType(ClipRRect),
          ))
          .where((c) => c.borderRadius == BorderRadius.circular(_kSurfaceRadius))
          .toList();

      expect(
        clips,
        isNotEmpty,
        reason: 'Fluent 分支必须补上裁剪，否则 clipBehavior 会被静默忽略',
      );
      expect(clips.first.clipBehavior, Clip.antiAlias);
    });
  });
}
