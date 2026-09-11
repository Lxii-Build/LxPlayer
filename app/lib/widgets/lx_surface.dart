import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../utils/theme_manager.dart';

/// 卡片 / 面板表面的风格。
enum LxSurfaceStyle {
  /// Cupertino / Oculus：液态玻璃。
  glass,

  /// 桌面 Fluent：`fluent.Card`。
  fluent,

  /// 其余（Material 等）：实心 `surfaceContainerHigh`。
  solid,
}

/// 把框架判定映射到表面风格（纯函数，便于单测，不依赖 BuildContext / 平台）。
///
/// - Cupertino / Oculus → 玻璃
/// - 有 FluentTheme 祖先 → Fluent 卡
/// - 其余 → 实心卡
///
/// 用「有没有 `FluentTheme` 祖先」而不是 `ThemeManager().isFluentFramework` 判定
/// Fluent，与底座既有写法一致（`album_detail_page.dart:55`、`artist_detail_page.dart:51`、
/// `qr_login_dialog.dart:13` 都用 `FluentTheme.maybeOf(context) != null`）。这样
/// `flutter test`（MaterialApp 宿主、树里没有 FluentTheme）会稳定落在实心分支，
/// 不会误进需要 FluentTheme 祖先的分支。
LxSurfaceStyle resolveLxSurfaceStyle({
  required bool isCupertino,
  required bool isOculus,
  required bool hasFluentTheme,
}) {
  if (isCupertino || isOculus) return LxSurfaceStyle.glass;
  if (hasFluentTheme) return LxSurfaceStyle.fluent;
  return LxSurfaceStyle.solid;
}

/// 全应用统一的「卡片 / 面板」表面。
///
/// 四套框架（Material / Fluent / Cupertino / Oculus）的唯一分支入口：
/// 业务组件只描述内容，具体表面样式由这里决定，避免在业务组件里散写
/// `Platform.isXXX` 分支。
class LxSurface extends StatelessWidget {
  const LxSurface({
    super.key,
    required this.child,
    this.borderRadius = 28,
    this.padding,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final double borderRadius;

  /// 内容内边距。三种风格共用同一份 padding，保证跨框架盒模型一致。
  final EdgeInsetsGeometry? padding;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final style = resolveLxSurfaceStyle(
      isCupertino: themeManager.isCupertinoFramework,
      isOculus: themeManager.isOculusFramework,
      hasFluentTheme: fluent.FluentTheme.maybeOf(context) != null,
    );

    switch (style) {
      case LxSurfaceStyle.glass:
        return _buildGlass(context);
      case LxSurfaceStyle.fluent:
        return _buildFluent();
      case LxSurfaceStyle.solid:
        return _buildSolid(context);
    }
  }

  /// 液态玻璃表面。折射参数逐字抄底座先例 `mini_player.dart:504-523`，
  /// 不新造视觉语言。
  Widget _buildGlass(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassContainer(
      shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: LiquidGlassSettings(
        thickness: isDark ? 35 : 20,
        blur: isDark ? 4 : 3,
        chromaticAberration: 0.3,
        refractiveIndex: 1.5,
        saturation: isDark ? 0.7 : 0.5,
        lightIntensity: isDark ? 0.6 : 0.4,
        ambientStrength: 1.0,
        specularSharpness: GlassSpecularSharpness.medium,
        glassColor: isDark ? const Color(0x3DFFFFFF) : const Color(0x1AFFFFFF),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
  }

  /// 桌面 Fluent：沿用底座一致的 `fluent.Card`。
  Widget _buildFluent() {
    return fluent.Card(
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );
  }

  /// 其余框架：实心卡（与卡片改造前的观感一致）。
  Widget _buildSolid(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: clipBehavior,
      padding: padding,
      child: child,
    );
  }
}
