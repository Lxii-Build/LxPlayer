import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/player_service.dart';
import '../../services/playlist_queue_service.dart';
import '../../utils/image_utils.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/lx_surface.dart';
import '../../widgets/lx_image_fallback.dart';
import 'newsong_item.dart';

/// 新歌列表（移动端）。
///
/// 字段解析统一交给 [NewsongItem.fromJson]（旧式 `album`/`artists`、新式
/// `al`/`ar`、已拍平、缺字段回落顶层 `picUrl` 都覆盖），本组件只负责排版与播放。
/// 封面走 `CachedNetworkImage` + `getImageHeaders`，与全项目其它封面一致——
/// 此前这里是全项目唯一用裸 `Image.network`、不传网易云 UA 的封面位。
class MobileNewsongList extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const MobileNewsongList({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;

    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);

    // 解析成展示模型：字段缺失逐级回落，绝不因缺键抛异常（旧实现缺 `al` 会崩整行）。
    final items = list.map(NewsongItem.fromJson).toList(growable: false);

    // 表面（背景 / 圆角 / 投影）统一交给 LxSurface 按框架决定，业务组件只描述列表内容。
    // clipBehavior 保留：首尾行不能压出圆角。
    return LxSurface(
      borderRadius: 28,
      clipBehavior: Clip.antiAlias,
      child: isCupertino ? _buildCupertinoList(context, items) : _buildMaterialList(context, items),
    );
  }

  /// Cupertino 行样式：整行可点、右侧带播放图标（Cupertino 触感反馈）。
  Widget _buildCupertinoList(BuildContext context, List<NewsongItem> items) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => Divider(
        height: 0.5,
        color: isDark
            ? CupertinoColors.systemGrey.withOpacity(0.3)
            : CupertinoColors.systemGrey.withOpacity(0.2),
      ),
      itemBuilder: (context, i) {
        final item = items[i];
        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _playSong(item),
          child: _NewsongRow(item: item, trailing: Icon(
            CupertinoIcons.play_circle,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          )),
        );
      },
    );
  }

  /// Material / Fluent 行样式：`InkWell` 提供点击水波反馈。
  Widget _buildMaterialList(BuildContext context, List<NewsongItem> items) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final item = items[i];
        return InkWell(
          onTap: () => _playSong(item),
          child: _NewsongRow(item: item, trailing: Icon(
            Icons.play_circle_outline,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          )),
        );
      },
    );
  }

  /// 播放单曲。
  ///
  /// 与桌面版新歌卡片（`newsong_cards.dart` 的 `NewsongCard`）保持同一套行为：
  /// 把解析出的 [NewsongItem] 转成 `Track`，设为队列后再播放。
  Future<void> _playSong(NewsongItem item) async {
    final track = item.toTrack();
    PlaylistQueueService().setQueue([track], 0, QueueSource.search);
    await PlayerService().playTrack(track);
  }
}

/// 单行：封面 + 歌名 + 歌手 +（可选）尾部操作图标。
///
/// 三个框架分支共用同一份行内容，只有外层的点击反馈与尾部图标不同，
/// 避免此前「Cupertino 一套行、Material 另一套行」导致的行为分叉。
class _NewsongRow extends StatelessWidget {
  final NewsongItem item;
  final Widget trailing;

  const _NewsongRow({required this.item, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _NewsongCover(picUrl: item.picUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    // 交由主题决定前景色，不再写死黑白。
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

/// 48×48 圆角封面。
///
/// 与全项目封面一致：`CachedNetworkImage` + `getImageHeaders`（126.net / 163.com
/// 需要网易云 UA），失败时才回落到 [LxImageFallback] 音符占位。
class _NewsongCover extends StatelessWidget {
  final String picUrl;

  const _NewsongCover({required this.picUrl});

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: picUrl,
        httpHeaders: getImageHeaders(picUrl),
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorWidget: (context, url, error) => const LxImageFallback(iconSize: 22),
      ),
    );
  }
}
