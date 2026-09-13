import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../models/netease_song_mapper.dart';
import '../../utils/image_utils.dart';
import '../../widgets/lx_image_fallback.dart';
import 'fluid_strip_carousel.dart';

/// 「今日推荐」流体轮播段（#1）。
///
/// 用 [FluidStripCarousel] 展示日推歌曲：当前卡完整尺寸 + 歌名歌手叠在底部渐变上，
/// 两侧卡压成竖条只露封面。点当前卡播放，点侧卡切到那张。
class DailyRecommendCarousel extends StatelessWidget {
  const DailyRecommendCarousel({
    super.key,
    required this.songs,
    this.onPlay,
    this.onOpenDetail,
  });

  final List<Map<String, dynamic>> songs;
  final void Function(Track track)? onPlay;
  final VoidCallback? onOpenDetail;

  Widget _buildCover(BuildContext context, int index, bool compressed) {
    final song = songs[index];
    final track = neteaseSongToTrack(song);
    final picUrl = track.picUrl;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (picUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: picUrl,
            httpHeaders: getImageHeaders(picUrl),
            fit: BoxFit.cover,
            errorWidget: (c, u, e) =>
                const LxImageFallback(iconSize: 32),
          )
        else
          const LxImageFallback(iconSize: 32),
        if (!compressed)
          Positioned(
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
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (track.artists.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        track.artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
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
          child: Row(
            children: <Widget>[
              const Text(
                '今日推荐',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (onOpenDetail != null)
                GestureDetector(
                  onTap: onOpenDetail,
                  child: const Text(
                    '查看全部',
                    style: TextStyle(fontSize: 13, color: Colors.blue),
                  ),
                ),
            ],
          ),
        ),
        FluidStripCarousel(
          itemCount: songs.length,
          coverBuilder: _buildCover,
          onTapItem: (i) => onPlay?.call(neteaseSongToTrack(songs[i])),
        ),
      ],
    );
  }
}

/// 「歌单榜」流体轮播段（#8）。
///
/// 用同一个 [FluidStripCarousel] 展示推荐歌单：当前卡完整尺寸 + 歌单名/描述叠在底部，
/// 两侧卡压成竖条。点当前卡打开歌单详情，点侧卡切到那张。
class PlaylistChartCarousel extends StatelessWidget {
  const PlaylistChartCarousel({
    super.key,
    required this.playlists,
    this.onTap,
  });

  final List<Map<String, dynamic>> playlists;
  final void Function(int id)? onTap;

  Widget _buildCover(BuildContext context, int index, bool compressed) {
    final p = playlists[index];
    final pic = (p['picUrl'] ?? p['coverImgUrl'] ?? '').toString();
    final name = p['name']?.toString() ?? '';
    final desc = (p['description'] ?? p['copywriter'] ?? '').toString();

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (pic.isNotEmpty)
          CachedNetworkImage(
            imageUrl: pic,
            httpHeaders: getImageHeaders(pic),
            fit: BoxFit.cover,
            errorWidget: (c, u, e) =>
                const LxImageFallback(iconSize: 32),
          )
        else
          const LxImageFallback(iconSize: 32),
        if (!compressed)
          Positioned(
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
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 4, 18, 10),
          child: Text(
            '歌单榜',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
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
