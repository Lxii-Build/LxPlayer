import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/pages/home_page/fluid_strip_carousel.dart';

/// 条带轮播的视觉基线。
///
/// 用纯色块代替真实封面：本轮要验的是**几何**（大卡与竖条的宽度比、间隙、圆角），
/// 不是封面内容。参考 `visual_toplist_card_test.dart` 的做法。
/// 注意：字体在测试环境渲染为方块，文字仅用于占位。
Widget _fakeCover(int index, bool compressed) {
  final List<Color> palette = <Color>[
    const Color(0xFF6C7BFF),
    const Color(0xFFFF8A65),
    const Color(0xFF4DB6AC),
    const Color(0xFFBA68C8),
    const Color(0xFFFFD54F),
  ];
  return Container(
    color: palette[index % palette.length],
    alignment: Alignment.bottomLeft,
    padding: const EdgeInsets.all(12),
    child: compressed
        ? const SizedBox.shrink()
        : const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('示例歌名',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text('示例歌手 · 示例专辑',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
  );
}

void main() {
  testWidgets('今日推荐条带轮播（首张为当前卡）', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 340));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 12, 18, 10),
                child: Text('今日推荐',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              FluidStripCarousel(
                itemCount: 5,
                coverBuilder: (BuildContext c, int i, bool compressed) => _fakeCover(i, compressed),
              ),
            ],
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(FluidStripCarousel),
      matchesGoldenFile('goldens/fluid_strip_carousel.png'),
    );
  });

  testWidgets('今日推荐条带轮播（第 2 张为当前卡）', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 340));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final FluidStripCarousel carousel = FluidStripCarousel(
      itemCount: 5,
      coverBuilder: (BuildContext c, int i, bool compressed) => _fakeCover(i, compressed),
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: carousel),
      ),
    );

    // 点第 2 张，让它成为当前卡并触发位移动画。
    // 卡 0 跨 x≈16–216，卡 1 跨 x≈221–277（baseWidth=stripWidth*0.45, 第二张宽=baseWidth*0.28）。
    await tester.tapAt(const Offset(250, 120));
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(FluidStripCarousel),
      matchesGoldenFile('goldens/fluid_strip_carousel_shifted.png'),
    );
  });
}
