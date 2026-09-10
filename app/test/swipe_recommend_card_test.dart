import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/pages/home_page/swipe_recommend_card.dart';

/// 首页推荐卡的滑动判定与扇形封面参数。
///
/// 这些数值决定卡片手感与观感，改动等于改产品外观，所以逐项钉住。
void main() {
  group('SwipeGesturePolicy', () {
    test('低于激活阈值不做任何事', () {
      expect(SwipeGesturePolicy.decide(11, 0), SwipeDecision.ignore);
      expect(SwipeGesturePolicy.decide(-11, 0), SwipeDecision.ignore);
    });

    test('到达激活阈值进入待定', () {
      expect(SwipeGesturePolicy.decide(12, 0), SwipeDecision.pending);
    });

    test('纵向占主导时让位给页面滚动', () {
      expect(SwipeGesturePolicy.decide(8, 24), SwipeDecision.failToVertical);
    });

    test('横向占主导即便有纵向漂移也保留手势', () {
      // 斜着滑但横向为主时不该让位，否则卡片几乎滑不动。
      expect(SwipeGesturePolicy.decide(-50, 26), SwipeDecision.commitNext);
    });

    test('左滑越过提交阈值为下一张', () {
      expect(SwipeGesturePolicy.decide(-36, 0), SwipeDecision.commitNext);
    });

    test('右滑越过提交阈值为上一张', () {
      expect(SwipeGesturePolicy.decide(36, 0), SwipeDecision.commitPrev);
    });

    test('略低于提交阈值仍为待定', () {
      expect(SwipeGesturePolicy.decide(-35, 0), SwipeDecision.pending);
    });

    test('下标循环回绕', () {
      expect(SwipeGesturePolicy.wrapIndex(2, 1, 3), 0);
      expect(SwipeGesturePolicy.wrapIndex(0, -1, 3), 2);
      expect(SwipeGesturePolicy.wrapIndex(0, 1, 3), 1);
    });

    test('空列表下标恒为 0', () {
      expect(SwipeGesturePolicy.wrapIndex(0, 1, 0), 0);
    });

    test('未提交时方向为 0', () {
      expect(SwipeGesturePolicy.directionOf(SwipeDecision.ignore), 0);
      expect(SwipeGesturePolicy.directionOf(SwipeDecision.pending), 0);
      expect(SwipeGesturePolicy.directionOf(SwipeDecision.failToVertical), 0);
      expect(SwipeGesturePolicy.directionOf(SwipeDecision.commitNext), 1);
      expect(SwipeGesturePolicy.directionOf(SwipeDecision.commitPrev), -1);
    });

    test('阈值与入场参数与参考交互一致', () {
      expect(SwipeGesturePolicy.activateThreshold, 12);
      expect(SwipeGesturePolicy.failVerticalThreshold, 24);
      expect(SwipeGesturePolicy.commitThreshold, 36);
      expect(SwipeGesturePolicy.enterDuration.inMilliseconds, 260);
      expect(SwipeGesturePolicy.enterOffset, 40);
    });
  });

  group('扇形封面参数', () {
    test('定义三层', () {
      expect(fanCoverLayerSpecs.length, 3);
      expect(
        fanCoverLayerSpecs.map((e) => e.name).toList(),
        ['back', 'mid', 'front'],
      );
    });

    test('尺寸与参考布局一致', () {
      expect(fanCoverLayerSpecs[0].width, 112);
      expect(fanCoverLayerSpecs[0].height, 144);
      expect(fanCoverLayerSpecs[1].width, 120);
      expect(fanCoverLayerSpecs[1].height, 160);
      expect(fanCoverLayerSpecs[2].width, 128);
      expect(fanCoverLayerSpecs[2].height, 176);
    });

    test('偏移与参考布局一致', () {
      expect(fanCoverLayerSpecs[0].offsetRight, 1);
      expect(fanCoverLayerSpecs[0].offsetTop, 9);
      expect(fanCoverLayerSpecs[1].offsetRight, 18);
      expect(fanCoverLayerSpecs[1].offsetTop, 4);
      expect(fanCoverLayerSpecs[2].offsetRight, 36);
      expect(fanCoverLayerSpecs[2].offsetTop, 0);
    });

    test('旋转方向交替，扇形才有张开感', () {
      expect(fanCoverLayerSpecs[0].rotationDegrees, 12);
      expect(fanCoverLayerSpecs[1].rotationDegrees, 5);
      // 前层反向倾斜；同向会看成整叠歪掉。
      expect(fanCoverLayerSpecs[2].rotationDegrees, -4);
    });

    test('越靠前越实', () {
      final opacities = fanCoverLayerSpecs.map((e) => e.opacity).toList();
      expect(opacities, [0.35, 0.65, 1]);
      for (var i = 0; i < opacities.length - 1; i++) {
        expect(opacities[i + 1] > opacities[i], isTrue);
      }
    });

    test('越靠前越大', () {
      final widths = fanCoverLayerSpecs.map((e) => e.width).toList();
      final heights = fanCoverLayerSpecs.map((e) => e.height).toList();
      for (var i = 0; i < widths.length - 1; i++) {
        expect(widths[i + 1] > widths[i], isTrue);
        expect(heights[i + 1] > heights[i], isTrue);
      }
    });

    test('每层各露出一条边而不是完全重合', () {
      final offsets = fanCoverLayerSpecs.map((e) => e.offsetRight).toList();
      for (var i = 0; i < offsets.length - 1; i++) {
        expect(offsets[i + 1] > offsets[i], isTrue);
      }
      expect(offsets.toSet().length, 3);
    });

    test('堆叠区能容纳最大的一层', () {
      final widest = fanCoverLayerSpecs
          .map((e) => e.width + e.offsetRight)
          .reduce((a, b) => a > b ? a : b);
      final tallest = fanCoverLayerSpecs
          .map((e) => e.height + e.offsetTop)
          .reduce((a, b) => a > b ? a : b);
      expect(widest <= fanStackWidth + 4, isTrue);
      expect(tallest <= fanStackHeight, isTrue);
    });
  });
}
