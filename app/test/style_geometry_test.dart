import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/models/track.dart';
import 'package:lxplayer/pages/home_page/swipe_recommend_card.dart';

/// 扇形封面与推荐卡的**渲染级**断言。
///
/// 为什么要有这一层：以前的测试只比对常量（`fanCoverLayerSpecs[0].width == 112`）。
/// 那种写法在有人直接改 build 里的布局、却没动常量时全绿，界面却已经走形——
/// 常量与「真的画成这样」之间没有任何约束。这里改成真的把 widget 渲染出来、
/// 量它落在屏幕上的盒子，把两边钉死。
///
/// 不用 golden 图：基准 PNG 必须在本地跑 `flutter test --update-goldens` 生成并提交，
/// 在这个环境里无法产出，硬写只会得到一个永远失败的测试。
Track _track(int id) => Track(
      id: id,
      name: '曲 $id',
      artists: '艺术家 $id',
      album: '专辑 $id',
      // 空封面走占位分支，测试里不会发起任何网络请求。
      picUrl: '',
    );

List<Track> _tracks(int count) => [for (var i = 0; i < count; i++) _track(i)];

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

/// 只在扇形堆叠内部找，避免撞上 Material/Scaffold 自带的同类 widget。
Finder _inStack(Finder matching) =>
    find.descendant(of: find.byType(FanCoverStack), matching: matching);

Finder _layerAt(int index) => _inStack(find.byType(Opacity)).at(index);

void main() {
  group('扇形封面真的画出来了', () {
    testWidgets('堆叠区尺寸等于规格值', (tester) async {
      await tester.pumpWidget(_wrap(FanCoverStack(tracks: _tracks(3), featuredIndex: 0)));

      expect(
        tester.getSize(find.byType(FanCoverStack)),
        const Size(fanStackWidth, fanStackHeight),
      );
      // 顺带把常量的字面值也钉住，防止有人改了常量还以为规格没变。
      expect(const Size(fanStackWidth, fanStackHeight), const Size(160, 192));
    });

    testWidgets('三层都渲染出来了，且尺寸与规格逐一相符', (tester) async {
      await tester.pumpWidget(_wrap(FanCoverStack(tracks: _tracks(3), featuredIndex: 0)));

      expect(_inStack(find.byType(Opacity)), findsNWidgets(3));

      for (var i = 0; i < fanCoverLayerSpecs.length; i++) {
        final spec = fanCoverLayerSpecs[i];
        expect(
          tester.getSize(_layerAt(i)),
          Size(spec.width, spec.height),
          reason: '第 $i 层（${spec.name}）渲染尺寸应等于规格',
        );
      }
    });

    testWidgets('三层彼此错开，而不是叠成一摞', (tester) async {
      await tester.pumpWidget(_wrap(FanCoverStack(tracks: _tracks(3), featuredIndex: 0)));

      // 取 Opacity 的坐标而不是它下面 Transform 的：Transform 在它下层，
      // localToGlobal 会把旋转算进去，量到的是转过的角点，不是布局位置。
      final tops = [
        for (var i = 0; i < fanCoverLayerSpecs.length; i++) tester.getTopLeft(_layerAt(i)),
      ];

      for (var i = 0; i < tops.length - 1; i++) {
        expect(
          tops[i].dx > tops[i + 1].dx,
          isTrue,
          reason: '越靠前的层应越靠左，否则扇形不会露出边（$tops）',
        );
        expect(
          tops[i].dy > tops[i + 1].dy,
          isTrue,
          reason: '越靠前的层应越靠上（$tops）',
        );
      }

      // 三层横向位置必须互不相同，否则就是完全重合。
      expect(tops.map((e) => e.dx).toSet().length, 3);
    });

    testWidgets('封面圆角确实被裁出来', (tester) async {
      await tester.pumpWidget(_wrap(FanCoverStack(tracks: _tracks(3), featuredIndex: 0)));

      final rounded = tester
          .widgetList<Container>(
            _inStack(find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).borderRadius != null,
            )),
          )
          .toList();

      expect(rounded.length, 3, reason: '三层封面都该带圆角');
      for (final container in rounded) {
        final radius = (container.decoration! as BoxDecoration).borderRadius;
        expect(radius, isA<BorderRadius>());
        expect(
          (radius! as BorderRadius).topLeft.x,
          24,
          reason: '圆角半径是和参考实现对齐过的观感值',
        );
      }
    });

    testWidgets('只有最前一层带投影', (tester) async {
      await tester.pumpWidget(_wrap(FanCoverStack(tracks: _tracks(3), featuredIndex: 0)));

      final shadowed = tester.widgetList<Container>(
        _inStack(find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).boxShadow != null,
        )),
      );

      // 后两层也加投影会糊成一片，扇形就分不出层次了。
      expect(shadowed.length, 1);
    });

    testWidgets('没有歌时整块收起来，不留下空盒子', (tester) async {
      await tester.pumpWidget(_wrap(const FanCoverStack(tracks: [], featuredIndex: 0)));

      expect(_inStack(find.byType(Opacity)), findsNothing);
      expect(tester.getSize(find.byType(FanCoverStack)), Size.zero);
    });
  });

  group('推荐卡', () {
    testWidgets('卡片里真的嵌着扇形堆叠，且尺寸稳定', (tester) async {
      await tester.pumpWidget(_wrap(
        SwipeRecommendCard(
          tracks: _tracks(3),
          // 关掉入场动画，拿到的才是稳定尺寸。
          animateEntrance: false,
        ),
      ));

      expect(find.byType(FanCoverStack), findsOneWidget);
      expect(
        tester.getSize(find.byType(FanCoverStack)),
        const Size(fanStackWidth, fanStackHeight),
      );
    });

    testWidgets('左滑越过提交阈值切到下一张', (tester) async {
      final changes = <List<int>>[];
      await tester.pumpWidget(_wrap(
        SwipeRecommendCard(
          tracks: _tracks(3),
          animateEntrance: false,
          onIndexChanged: (index, direction) => changes.add([index, direction]),
        ),
      ));

      await tester.drag(find.byType(SwipeRecommendCard), const Offset(-120, 0));
      await tester.pump();

      expect(changes, isNotEmpty, reason: '越过 36 的提交阈值就该换一张');
      expect(changes.first, [1, 1]);
    });

    testWidgets('没到提交阈值的欠拖不会换张', (tester) async {
      final changes = <List<int>>[];
      await tester.pumpWidget(_wrap(
        SwipeRecommendCard(
          tracks: _tracks(3),
          animateEntrance: false,
          onIndexChanged: (index, direction) => changes.add([index, direction]),
        ),
      ));

      await tester.drag(find.byType(SwipeRecommendCard), const Offset(-20, 0));
      await tester.pump();

      expect(changes, isEmpty, reason: '20 只够激活（12），不够提交（36）');
    });
  });
}
