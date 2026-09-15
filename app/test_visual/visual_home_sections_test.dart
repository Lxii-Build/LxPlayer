import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/widgets/lx_surface.dart';

/// 首页**推荐卡下方区块**所用表面的视觉基线。
///
/// 为什么加这一组：上一轮只有最上面那张推荐卡换成了 `LxSurface`，下方区块还是
/// 各自手写的容器，真机上看是「一张新卡压着一堆旧卡」。这一轮把下方也收敛到
/// 同一个表面组件，这里留下可审阅的图。
///
/// 这里渲染的是**表面本身 + 齐边铺满的内容**，而不是具体业务区块：
/// 首页下方四个区块（新歌列表 / 歌单网格 / 私人FM / 榜单卡）的内容都要加载图片
/// （`Image.network` / `CachedNetworkImage`），headless 环境下取不到图片、
/// 也没有 `path_provider` 平台通道，硬渲染只会得到与视觉无关的报错。
/// 它们「外层确实是同一个表面」由 `app/test/home_surface_consistency_test.dart`
/// 断言，观感则靠这张图 + 真机审阅。
///
/// 与本目录其它文件一致：固定画布尺寸 + `pump` 后立刻截图，保证可重复。
void main() {
  testWidgets('统一表面 + 裁剪（列表 / 封面型内容齐边铺满）', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 220));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 内容齐边铺满时，表面圆角必须把内容裁进轮廓里。改造前 `clipBehavior` 只在
    // 实心分支生效、玻璃 / Fluent 分支被静默忽略，这张图钉住修好后的形态。
    // 用纯色块而不是真实业务内容：形态一样，但完全不依赖图片加载。
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: LxSurface(
                borderRadius: 28,
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(height: 56, color: const Color(0xFF5B6CFF)),
                    const Divider(height: 1),
                    Container(height: 56, color: const Color(0xFF8E7BFF)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(LxSurface),
      matchesGoldenFile('goldens/lx_surface_clipped.png'),
    );
  });
}
