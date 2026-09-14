import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../utils/image_utils.dart';
import '../../widgets/lx_image_fallback.dart';
import 'fluid_strip_carousel.dart';

/// 「歌单榜」流体轮播段（#8）。
///
/// 用 [FluidStripCarousel] 展示推荐歌单：
///   - 当前卡是完整尺寸的方形封面，歌单名 + 描述叠在底部渐变上；
///   - 两侧的卡被压成竖条，**歌单名以竖排文字显示**（与用户给的参考图一致），
///     这样即使只剩一条窄边也能认出是哪张。
///
/// 点当前卡打开歌单详情，点侧卡把它滑到中间。
class PlaylistChartCarousel extends StatelessWidget {
  const PlaylistChartCarousel({
    super.key,
    required this.playlists,
    this.onTap,
    this.title = '歌单榜',
  });

  final List<Map<String, dynamic>> playlists;
  final void Function(int id)? onTap;
  final String title;

  /// 压扁卡上的竖排标题。
  Widget _verticalTitle(String name) {
    if (name.isEmpty) return const SizedBox.shrink();
    return Center(
      child: RotatedBox(
        quarterTurns: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              shadows: <Shadow>[
                Shadow(color: Colors.black54, blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 当前卡底部的歌单名 + 描述（叠在渐变上）。
  Widget _bottomInfo(String name, String desc) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0x00000000), Color(0xB3000000)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (desc.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  desc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context, int index, bool compressed) {
    final p = playlists[index];
    final pic = (p['picUrl'] ?? p['coverImgUrl'] ?? '').toString();
    final name = p['name']?.toString() ?? '';
    final desc = (p['description'] ?? p['copywriter'] ?? '').toString();

    final Widget overlay =
        compressed ? _verticalTitle(name) : _bottomInfo(name, desc);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (pic.isNotEmpty)
          CachedNetworkImage(
            imageUrl: pic,
            httpHeaders: getImageHeaders(pic),
            fit: BoxFit.cover,
            errorWidget: (c, u, e) => const LxImageFallback(iconSize: 32),
          )
        else
          const LxImageFallback(iconSize: 32),
        overlay,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        FluidStripCarousel(
          itemCount: playlists.length,
          coverBuilder: _buildCover,
          onTapItem: (i) {
            final idVal = playlists[i]['id'];
            final id = int.tryParse(idVal?.toString() ?? '');
            if (id != null) onTap?.call(id);
          },
        ),
      ],
    );
  }
}
