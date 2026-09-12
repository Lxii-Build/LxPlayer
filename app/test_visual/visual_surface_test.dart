import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lxplayer/widgets/lx_surface.dart';

/// LxSurface 的**框架分支**视觉基线。
///
/// 这里走真实组件：`LxSurface.build` 通过 `lxSurfaceStyleOf(context)` 判定分支。
/// - 实心分支：Material 宿主（树里没有 FluentTheme）→ `surfaceContainerHigh` 实心卡；
/// - Fluent 分支：`fluent.FluentApp` 宿主（树里有 FluentTheme）→ `fluent.Card`；
/// - 玻璃分支：本文件**不渲染**（`flutter test` 跑在主机上，`ThemeManager` 的平台判定
///   恒为假，玻璃分支无法通过真实 `LxSurface` 触发）。玻璃基线单独放在
///   `visual_surface_glass_test.dart`，并注明它与真机像素的差异。
///
/// 三张图都用固定画布尺寸 + `pumpWidget` 后立刻截图，保证可重复。
void main() {
  testWidgets('LxSurface 实心分支（Material 宿主）', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: LxSurface(
                borderRadius: 28,
                padding: const EdgeInsets.all(20),
                child: const Text('实心卡 LxSurface'),
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(LxSurface),
      matchesGoldenFile('goldens/lx_surface_solid.png'),
    );
  });

  testWidgets('LxSurface Fluent 分支（FluentApp 宿主）', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      fluent.FluentApp(
        debugShowCheckedModeBanner: false,
        home: Center(
          child: SizedBox(
            width: 320,
            child: LxSurface(
              borderRadius: 28,
              padding: const EdgeInsets.all(20),
              child: const Text('Fluent 卡 LxSurface'),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(LxSurface),
      matchesGoldenFile('goldens/lx_surface_fluent.png'),
    );
  });
}
