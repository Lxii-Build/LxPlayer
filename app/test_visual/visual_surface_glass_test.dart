import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// LxSurface 的**玻璃分支**视觉基线（尽力而为）。
///
/// ⚠️ 重要说明——它**不代表真机像素**：
/// `LxSurface.build` 用 `lxSurfaceStyleOf(context)` 选分支，而玻璃分支只在
/// Cupertino / Oculus（`Platform.isIOS || Platform.isAndroid` 且非平板）下命中。
/// `flutter test` 跑在 Linux 主机上，平台判定恒为假，因此**无法**通过真实
/// `LxSurface` 触发玻璃分支。
///
/// 为了仍然留下「当前玻璃参数长什么样」的可审阅图片，这里用
/// `LxSurface._buildGlass` 同一套**公共 API 与参数**直接构造玻璃面板：
/// 参数逐字镜像 `app/lib/widgets/lx_surface.dart` 的 `_glassSettings`（light 分支）。
/// 改动 lx_surface.dart 的玻璃参数时，**必须同步本文件**，否则这张图会漂移。
///
/// 玻璃渲染依赖 GPU / 着色器，headless 环境下的结果仅供参考；CI 上该 job
/// `continue-on-error: true`，本文件失败也不会阻断流水线。
void main() {
  setUpAll(() async {
    // 与 main.dart 一致：使用玻璃组件前先初始化。若在 headless 环境下初始化失败，
    // 本文件整体报错——只影响这一张图，其它视觉基线文件不受牵连。
    TestWidgetsFlutterBinding.ensureInitialized();
    await LiquidGlassWidgets.initialize();
  });

  testWidgets('LxSurface 玻璃分支视觉基线', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          // 给玻璃一个有色背景，才能看出折射/高光，否则一片透明无从审阅。
          backgroundColor: const Color(0xFF5B6CFF),
          body: Center(
            child: SizedBox(
              width: 320,
              child: GlassContainer(
                shape: LiquidRoundedSuperellipse(borderRadius: 28),
                useOwnLayer: true,
                quality: GlassQuality.standard,
                // 镜像 lx_surface.dart `_glassSettings` 的 light 分支。
                settings: LiquidGlassSettings(
                  thickness: 20,
                  blur: 3,
                  chromaticAberration: 0.3,
                  refractiveIndex: 1.5,
                  saturation: 0.5,
                  lightIntensity: 0.4,
                  ambientStrength: 1.0,
                  specularSharpness: GlassSpecularSharpness.medium,
                  glassColor: const Color(0x1AFFFFFF),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('玻璃卡 LxSurface'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await expectLater(
      find.byType(GlassContainer),
      matchesGoldenFile('goldens/lx_surface_glass.png'),
    );
  });
}
