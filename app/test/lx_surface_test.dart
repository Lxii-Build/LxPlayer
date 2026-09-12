import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/pages/home_page/swipe_recommend_card.dart';
import 'package:lxplayer/widgets/lx_surface.dart';

/// 推荐卡的**纯逻辑**断言：表面框架分支、播放键三态、动画常量。
///
/// 这些是不依赖渲染的纯函数，放在单独文件里，避免动到既有的
/// `style_geometry_test.dart` / `swipe_recommend_card_test.dart` 的断言。
void main() {
  group('LxSurface 框架分支', () {
    test('Cupertino / Oculus 走液态玻璃', () {
      expect(
        resolveLxSurfaceStyle(
            isCupertino: true, isOculus: false, hasFluentTheme: false),
        LxSurfaceStyle.glass,
      );
      expect(
        resolveLxSurfaceStyle(
            isCupertino: false, isOculus: true, hasFluentTheme: false),
        LxSurfaceStyle.glass,
      );
      // 即便同时挂着 FluentTheme，移动端玻璃分支也优先，不会掉到实心。
      expect(
        resolveLxSurfaceStyle(
            isCupertino: true, isOculus: true, hasFluentTheme: true),
        LxSurfaceStyle.glass,
      );
    });

    test('挂着 FluentTheme 祖先走 Fluent 卡', () {
      expect(
        resolveLxSurfaceStyle(
            isCupertino: false, isOculus: false, hasFluentTheme: true),
        LxSurfaceStyle.fluent,
      );
    });

    test('其余（Material，含无 FluentTheme 的测试宿主）走实心卡', () {
      expect(
        resolveLxSurfaceStyle(
            isCupertino: false, isOculus: false, hasFluentTheme: false),
        LxSurfaceStyle.solid,
      );
    });
  });

  group('播放键三态', () {
    test('不是当前曲目 → idle（点击播放）', () {
      expect(
        resolvePlayButtonState(
            currentTrackId: null,
            trackId: '1',
            isPlaying: false,
            isPaused: false),
        PlayButtonState.idle,
      );
      expect(
        resolvePlayButtonState(
            currentTrackId: '2',
            trackId: '1',
            isPlaying: true,
            isPaused: false),
        PlayButtonState.idle,
      );
    });

    test('是当前曲目、正在播放 → playingCurrent（点击暂停）', () {
      expect(
        resolvePlayButtonState(
            currentTrackId: '1',
            trackId: '1',
            isPlaying: true,
            isPaused: false),
        PlayButtonState.playingCurrent,
      );
    });

    test('是当前曲目、已暂停 → pausedCurrent（点击继续）', () {
      expect(
        resolvePlayButtonState(
            currentTrackId: '1',
            trackId: '1',
            isPlaying: false,
            isPaused: true),
        PlayButtonState.pausedCurrent,
      );
    });

    test('是当前曲目、既没播也没暂停（加载中） → idle', () {
      expect(
        resolvePlayButtonState(
            currentTrackId: '1',
            trackId: '1',
            isPlaying: false,
            isPaused: false),
        PlayButtonState.idle,
      );
    });
  });

  group('动画常量', () {
    test('新增动效用库里最高频的一套数值', () {
      expect(SwipeAnimations.cancelDuration, const Duration(milliseconds: 180));
      expect(SwipeAnimations.pressDuration, const Duration(milliseconds: 120));
      expect(SwipeAnimations.pressScale, 0.97);
      expect(SwipeAnimations.cancelCurve, Curves.easeOut);
      expect(SwipeAnimations.stateDuration, const Duration(milliseconds: 200));
      expect(SwipeAnimations.stateCurve, Curves.easeOutCubic);
    });

    test('既有入场 260ms/40dp 与阈值 12/24/36 保持原值', () {
      expect(
        SwipeGesturePolicy.enterDuration,
        const Duration(milliseconds: 260),
      );
      expect(SwipeGesturePolicy.enterOffset, 40);
      expect(SwipeGesturePolicy.activateThreshold, 12);
      expect(SwipeGesturePolicy.failVerticalThreshold, 24);
      expect(SwipeGesturePolicy.commitThreshold, 36);
    });
  });
}
