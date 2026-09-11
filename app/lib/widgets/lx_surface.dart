import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../utils/theme_manager.dart';

/// 卡片 / 面板 / 控件的表面风格。
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

/// 从 `BuildContext` 解析当前表面风格。
///
/// 所有需要按框架分支的组件都走这一个入口，避免 `Platform.isXXX` 分支散落各处。
LxSurfaceStyle lxSurfaceStyleOf(BuildContext context) {
  final themeManager = ThemeManager();
  return resolveLxSurfaceStyle(
    isCupertino: themeManager.isCupertinoFramework,
    isOculus: themeManager.isOculusFramework,
    hasFluentTheme: fluent.FluentTheme.maybeOf(context) != null,
  );
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
    final style = lxSurfaceStyleOf(context);
    return switch (style) {
      LxSurfaceStyle.glass => _buildGlass(context),
      LxSurfaceStyle.fluent => _buildFluent(),
      LxSurfaceStyle.solid => _buildSolid(context),
    };
  }

  /// 液态玻璃表面。折射参数逐字抄底座先例 `mini_player.dart:504-523`，
  /// 不新造视觉语言。
  Widget _buildGlass(BuildContext context) {
    return GlassContainer(
      shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: _glassSettings(context),
      child: _clipped(Padding(padding: padding ?? EdgeInsets.zero, child: child)),
    );
  }

  /// 桌面 Fluent：沿用底座一致的 `fluent.Card`。
  Widget _buildFluent() {
    // 不裁剪时保持改造前的原样结构（padding 交给 Card 自己），既有 Fluent 渲染
    // 逐像素不变。需要裁剪时才把 padding 挪进来，好让裁剪能包住整块内容。
    if (clipBehavior == Clip.none) {
      return fluent.Card(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      );
    }
    return fluent.Card(
      padding: EdgeInsets.zero,
      child: _clipped(Padding(padding: padding ?? EdgeInsets.zero, child: child)),
    );
  }

  /// 给玻璃 / Fluent 分支补上 [clipBehavior]。
  ///
  /// 只有实心分支能把 [clipBehavior] 直接交给 `Container`；玻璃分支的外壳是
  /// `GlassContainer`、Fluent 分支是 `fluent.Card`，两者都没有 `clipBehavior`
  /// 入参。不补这一层的话，调用方传的 [clipBehavior] 会被**静默忽略**，紧贴
  /// 表面边缘的内容（列表首尾行、齐边封面）就会压出圆角。
  ///
  /// 裁剪位置对齐 `Container` 的语义——裁在 padding **外面**，即整块内容（含
  /// 内边距区域）一起被裁到表面轮廓，而不是只裁 padding 里的那块。
  ///
  /// 玻璃外形是圆角超椭圆（比同半径圆角矩形更"饱满"），用圆角矩形裁会比外形
  /// 略收一点点——宁可少露一丝，也不会溢出到轮廓外。
  ///
  /// [Clip.none]（默认值，也是既有调用点 `swipe_recommend_card.dart` 的取值）
  /// 下不插入任何节点，既有渲染保持逐像素不变。
  Widget _clipped(Widget content) {
    if (clipBehavior == Clip.none) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: clipBehavior,
      child: content,
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

/// 胶囊型底座的内容构建器。
///
/// 底座负责背景（玻璃 / 实心），把最终的**内容前景色**回传给调用方，
/// 这样按钮文字/图标在两种背景上都能保持可读。
typedef LxPillBuilder = Widget Function(
  BuildContext context,
  LxSurfaceStyle style,
  Color foreground,
);

/// 胶囊型「主操作」底座（视觉层，不含手势）。
///
/// 移动端 Cupertino / Oculus 下用液态玻璃底座（替换原先的 Material
/// `FilledButton`），其余框架退化为实心胶囊，保持主操作的可点读性。
/// 玻璃参数与 [LxSurface] 完全一致，不新造视觉语言。
class LxPill extends StatelessWidget {
  const LxPill({
    super.key,
    required this.builder,
    this.enabled = true,
    this.borderRadius = 24,
    this.padding,
  });

  final LxPillBuilder builder;
  final bool enabled;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final style = lxSurfaceStyleOf(context);
    final cs = Theme.of(context).colorScheme;
    final pad = padding ?? const EdgeInsets.symmetric(horizontal: 20);
    return switch (style) {
      LxSurfaceStyle.glass => _glassPill(context, cs, pad),
      LxSurfaceStyle.fluent => _solidPill(context, cs, pad),
      LxSurfaceStyle.solid => _solidPill(context, cs, pad),
    };
  }

  Widget _glassPill(BuildContext context, ColorScheme cs, EdgeInsetsGeometry pad) {
    final foreground = enabled ? cs.primary : cs.onSurfaceVariant;
    return GlassContainer(
      shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: _glassSettings(context),
      child: Padding(
        padding: pad,
        child: builder(context, LxSurfaceStyle.glass, foreground),
      ),
    );
  }

  Widget _solidPill(
    BuildContext context,
    ColorScheme cs,
    EdgeInsetsGeometry pad,
  ) {
    final background =
        enabled ? cs.primaryContainer : cs.surfaceContainerHighest;
    final foreground =
        enabled ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return Container(
      padding: pad,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: builder(context, LxSurfaceStyle.solid, foreground),
    );
  }
}

/// 统一的液态玻璃参数。逐字抄底座先例 `mini_player.dart:504-523`。
LiquidGlassSettings _glassSettings(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return LiquidGlassSettings(
    thickness: isDark ? 35 : 20,
    blur: isDark ? 4 : 3,
    chromaticAberration: 0.3,
    refractiveIndex: 1.5,
    saturation: isDark ? 0.7 : 0.5,
    lightIntensity: isDark ? 0.6 : 0.4,
    ambientStrength: 1.0,
    specularSharpness: GlassSpecularSharpness.medium,
    glassColor: isDark ? const Color(0x3DFFFFFF) : const Color(0x1AFFFFFF),
  );
}
