import 'package:flutter/material.dart';

/// 网络图片加载失败时的**统一兜底**。
///
/// 全应用所有 `CachedNetworkImage.errorWidget` / `Image.network.errorBuilder`
/// 都返回本组件，避免出现「图挂了以后整块空白」或「占位转圈永远不停」。
///
/// 颜色一律取自 [ColorScheme]，因此深色 / 浅色两套主题下都保持可读——
/// 这也是把它抽成公共组件的原因：同样的兜底逻辑散落 50 处，下次只会被改到
/// 其中几处。
class LxImageFallback extends StatelessWidget {
  const LxImageFallback({
    super.key,
    this.icon = Icons.music_note,
    this.iconSize = 28,
  });

  /// 兜底图标，默认音符（与 `track_list_tile.dart` 既有写法一致）。
  final IconData icon;

  /// 图标尺寸。封面越小可传得越小。
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(icon, color: cs.onSurfaceVariant, size: iconSize),
    );
  }
}
