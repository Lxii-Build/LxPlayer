import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../services/player_service.dart';
import '../../services/playlist_queue_service.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/lx_surface.dart';
import '../../widgets/lx_image_fallback.dart';
import 'hero_section.dart'; // 复用 convertToTrack 函数

/// 新歌列表（移动端）
class MobileNewsongList extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const MobileNewsongList({super.key, required this.list});

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;

    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);

    // 表面（背景 / 圆角 / 投影）统一交给 LxSurface 按框架决定，业务组件只描述列表内容。
    // 原先 Cupertino 分支手写的容器配色（0xFF1C1C1E / CupertinoColors.white）与投影一并撤掉；
    // 非 Cupertino 分支原本是裸列表，这里也一起获得同一套表面。
    // clipBehavior 保留：首尾行不能压出圆角。
    return LxSurface(
      borderRadius: 28,
      clipBehavior: Clip.antiAlias,
      child: isCupertino ? _buildCupertinoList(context) : _buildMaterialList(),
    );
  }

  /// Cupertino 行样式：整行可点、右侧带 chevron。
  Widget _buildCupertinoList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => Divider(
        height: 0.5,
        color: isDark
            ? CupertinoColors.systemGrey.withOpacity(0.3)
            : CupertinoColors.systemGrey.withOpacity(0.2),
      ),
      itemBuilder: (context, i) {
        final s = list[i];
        final song = (s['song'] ?? s);
        final al = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
        final ar = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
        final pic = (al['picUrl'] ?? '').toString();
        final artists = ar.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join('/');
        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _playSong(song),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(pic, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const LxImageFallback(),),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song['name']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          // 交由主题决定前景色，不再写死黑白。
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: CupertinoColors.systemGrey,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Material / Fluent 行样式：标准 ListTile。
  Widget _buildMaterialList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final s = list[i];
        final song = (s['song'] ?? s);
        final al = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
        final ar = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
        final pic = (al['picUrl'] ?? '').toString();
        final artists = ar.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join('/');
        return ListTile(
          onTap: () => _playSong(song),
          leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(pic, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const LxImageFallback(),)),
          title: Text(song['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(artists, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }

  /// 播放单曲。
  ///
  /// 与桌面版新歌卡片（`newsong_cards.dart` 的 `NewsongCard`）保持同一套行为：
  /// 用 `convertToTrack` 把接口返回的原始 map 构造成 `Track`，设为队列后再播放。
  /// 此前 Cupertino 分支是 `// TODO`、Material 分支整行不可点，点了没反应。
  Future<void> _playSong(Map<String, dynamic> song) async {
    final track = convertToTrack(song);
    PlaylistQueueService().setQueue([track], 0, QueueSource.search);
    await PlayerService().playTrack(track);
  }
}
