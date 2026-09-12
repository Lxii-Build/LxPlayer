import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/models/track.dart';
import 'package:lxplayer/pages/home_page/swipe_recommend_card.dart';

/// 首页推荐卡与扇形封面的视觉基线。
///
/// 刻意用**空封面**（`picUrl: ''`）构造曲目：这样扇形封面走的是占位形态
/// （灰色底 + 音符图标），既能看到三层堆叠的几何关系，又完全不触发网络请求，
/// 图片因此可重复。
///
/// 推荐卡关掉入场动画（`animateEntrance: false`），`pump` 一帧即稳定尺寸。
Track _stubTrack(int id) => Track(
      id: id,
      name: '示例曲目 $id',
      artists: '示例歌手 · 示例歌手二',
      album: '示例专辑',
      picUrl: '',
    );

void main() {
  testWidgets('扇形封面堆叠（空封面占位形态）', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(220, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: FanCoverStack(
              tracks: [_stubTrack(1), _stubTrack(2), _stubTrack(3)],
              featuredIndex: 0,
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(FanCoverStack),
      matchesGoldenFile('goldens/fan_cover_stack_empty.png'),
    );
  });

  testWidgets('首页推荐卡整体', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(440, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: SwipeRecommendCard(
                tracks: [_stubTrack(1), _stubTrack(2), _stubTrack(3)],
                onPlay: (_) {},
                onOpenDetail: () {},
                animateEntrance: false,
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(SwipeRecommendCard),
      matchesGoldenFile('goldens/recommend_card.png'),
    );
  });
}
