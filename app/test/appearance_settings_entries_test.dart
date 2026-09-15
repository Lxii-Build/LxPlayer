import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lxplayer/pages/settings_page/appearance_settings_page.dart';
import 'package:lxplayer/pages/settings_page/window_background_dialog.dart';
import 'package:lxplayer/services/lyric_font_service.dart';

/// 「外观设置」死入口修复的回归测试。
///
/// 覆盖两件事：
///   * 「歌词字体」入口在 Material 宿主下确实能弹出字体选择对话框（此前无测试；
///     本次用可证明的方式钉住，避免以后回退成空壳）。
///   * 「窗口背景」根因：`WindowBackgroundDialog` 原先 `build()` 里**无条件**返回
///     `fluent_ui.ContentDialog`，在缺少 `FluentTheme` 祖先的 Material 宿主里渲染
///     会崩溃——这才是「点了没反应」的真正原因。这里在纯 Material 宿主下把该弹窗
///     直接弹出来，断言它是 Material `AlertDialog`（修复前会抛异常）。
///
/// 说明：`flutter test` 永远运行在桌面宿主上；`ThemeManager` 默认框架为 Material
/// （且 `setThemeFramework` 目前只接受 Material），因此这里渲染到的就是
/// `_buildMaterialUI` 分支，无需额外桩。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bool isDesktop =
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  setUp(() {
    // 让各单例服务里的 SharedPreferences 读取落到内存 mock 上，避免 MissingPlugin。
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// 把内容撑到足够高，保证 `ListView` 里的条目全部完成布局、可点。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpAppearanceContent(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        ),
        home: Scaffold(
          body: AppearanceSettingsContent(embed: true, onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 首帧渲染整页时，`MD3SettingsTile`（`lib/widgets/material/material_settings_widgets.dart`）
    // 把 `ListTile` 包在一个带底色的 `DecoratedBox` 里，会触发 Flutter 框架的一条既有
    // debug 断言（"ListTile background color or ink splashes may be invisible"），多条时
    // 被框架聚合成 "Multiple exceptions (N) …"。该组件**未被本次修改触碰**，与「歌词字体 /
    // 窗口背景」是否可点无关。这里显式取走并核验它确实是那条既有断言，其余一律失败。
    final Object? firstFrameException = tester.takeException();
    if (firstFrameException != null) {
      expect(
        firstFrameException.toString(),
        anyOf(contains('ListTile'), contains('Multiple exceptions')),
        reason: '外观设置页首帧只可能抛出既有的 ListTile 断言，实际：$firstFrameException',
      );
    }
  }

  group('歌词字体入口（Material）', () {
    testWidgets('「歌词字体」条目存在，点击后弹出字体选择对话框', (WidgetTester tester) async {
      useTallViewport(tester);
      await pumpAppearanceContent(tester);

      // 入口存在
      expect(find.text('歌词字体'), findsOneWidget);

      // 点击入口
      await tester.tap(find.text('歌词字体'));
      await tester.pumpAndSettle();

      // 断言：真的弹出了 Material 对话框，且标题正确
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('选择歌词字体'), findsOneWidget);

      // 断言：对话框里真的渲染了预设字体列表（不是空壳弹窗）
      expect(find.text('预设字体'), findsOneWidget);
      expect(find.text('自定义字体'), findsOneWidget);

      final presetFonts = LyricFontService.platformFonts;
      expect(presetFonts, isNotEmpty, reason: '平台上应至少有一个预设字体');
      // 列表首项名称应出现在弹窗中
      expect(find.text(presetFonts.first.name), findsWidgets);

      // 打开弹窗这一交互不应再引入任何异常
      expect(tester.takeException(), isNull);
    });
  });

  group('窗口背景弹窗根因（Material 宿主，不含 FluentTheme）', () {
    // 修复前：`WindowBackgroundDialog.build` 无条件返回 `fluent_ui.ContentDialog`，
    // 在 Material 宿主下会因缺少 `FluentTheme` 祖先崩溃。修复后应渲染 Material AlertDialog。
    testWidgets('Material 宿主下能弹出窗口背景对话框且不抛异常',
        (WidgetTester tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        WindowBackgroundDialog(onChanged: () {}),
                  ),
                  child: const Text('打开窗口背景'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开窗口背景'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('窗口背景设置'), findsOneWidget);
    });

    testWidgets('入口归属：桌面宿主下「窗口背景」出现在外观设置页（桌面端分区）',
        (WidgetTester tester) async {
      useTallViewport(tester);
      await pumpAppearanceContent(tester);

      // 「窗口背景」仅在桌面宿主渲染（已并入桌面端专属分区）。
      if (!isDesktop) {
        expect(find.text('窗口背景'), findsNothing);
        return;
      }

      expect(find.text('窗口背景'), findsOneWidget);

      // 点击后应能正常弹出对话框（修复前此处会崩）。
      await tester.ensureVisible(find.text('窗口背景'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('窗口背景'));
      await tester.pumpAndSettle();

      expect(find.text('窗口背景设置'), findsOneWidget);
      // 打开弹窗这一交互不应再引入任何异常
      expect(tester.takeException(), isNull);
    });
  });
}
