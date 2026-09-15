import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/image_utils.dart';
import '../../models/track.dart';
import '../../models/toplist.dart';
import '../../services/player_service.dart';
import '../../services/music_service.dart';
import '../../utils/theme_manager.dart';
import 'home_widgets.dart';
import 'fluid_strip_carousel.dart';
import 'toplist_detail.dart';
import '../../widgets/lx_surface.dart';
import '../../widgets/oculus/oculus_home_widgets.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/lx_image_fallback.dart';

/// 首页区块的纵向节奏。
///
/// 参考实现的节奏是「区块标题→内容 16、区块之间 36–40」。原先每个区块各写一个
/// 魔数（24 / 56 / 56 / 64），越看越不齐；这里收敛成一组常量，只调间距，不动
/// 区块顺序。
const double _kSectionTitleGap = 16;
const double _kSectionGap = 40;

class ChartsTab extends StatelessWidget {
  final Future<void> Function() checkLoginStatus;
  final Future<List<Track>>? guessYouLikeFuture;
  final VoidCallback onRefresh;

  const ChartsTab({
    super.key,
    required this.checkLoginStatus,
    this.guessYouLikeFuture,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isIOS || Platform.isAndroid;
    
    if (MusicService().isLoading) {
      // 移动端使用移动端专用骨架屏
      if (isMobile) {
        return const MobileChartsTabSkeleton();
      }
      // Fluent UI 桌面端使用桌面端骨架屏
      if (ThemeManager().isFluentFramework) {
        return const ChartsTabSkeleton();
      }
      // 其他桌面端也使用桌面端骨架屏
      return const ChartsTabSkeleton();
    }

    if (MusicService().errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载失败\n${MusicService().errorMessage}'),
              const SizedBox(height: 16),
              if (ThemeManager().isFluentFramework)
                fluent.Button(
                  onPressed: onRefresh,
                  child: const Text('重试'),
                )
              else
                ElevatedButton(
                  onPressed: onRefresh,
                  child: const Text('重试'),
                ),
            ],
          ),
        ),
      );
    }

    if (MusicService().toplists.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('暂无榜单数据')));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 0. Expressive Page Title
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: _kSectionGap),
              child: Text(
                '音乐榜单',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),

            // 1. 历史与推荐 (Quick Access)
            Padding(
              padding: const EdgeInsets.only(bottom: _kSectionGap),
              child: _buildQuickAccessSection(context, isWide),
            ),

            // 2. 榜单列表（与上方保持同一节奏）
            // 注：原先这里还有一张「每日推荐」SwipeRecommendCard（`_buildFeaturedSection`），
            // 它与「为你推荐」页顶部的同款卡片重复（home_for_you_tab.dart:291），
            // 已按用户要求从榜单页移除，榜单页只保留榜单与个人向内容。
            ...MusicService().toplists.map((toplist) {
              return Padding(
                padding: const EdgeInsets.only(bottom: _kSectionGap),
                child: _ToplistSection(
                  toplist: toplist,
                  checkLoginStatus: checkLoginStatus,
                ),
              );
            }),
            
             SizedBox(height: MediaQuery.of(context).padding.bottom + 48),
          ],
        );
      },
    );
  }

  Widget _buildQuickAccessSection(BuildContext context, bool isWide) {
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(child: HistorySection()),
          const SizedBox(width: 24),
          Expanded(
            child: GuessYouLikeSection(
              guessYouLikeFuture: guessYouLikeFuture,
            ),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          const HistorySection(),
          const SizedBox(height: 16),
          GuessYouLikeSection(
            guessYouLikeFuture: guessYouLikeFuture,
          ),
        ],
      );
    }
  }
}

class _ToplistSection extends StatelessWidget {
  final Toplist toplist;
  final Future<void> Function() checkLoginStatus;

  const _ToplistSection({
    required this.toplist,
    required this.checkLoginStatus,
  });

  @override
  Widget build(BuildContext context) {
    if (ThemeManager().isOculusFramework) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OculusSectionHeader(
            title: toplist.name,
            onMoreTap: () => showToplistDetail(context, toplist),
            moreLabel: '全部',
          ),
          const SizedBox(height: _kSectionTitleGap),
          SizedBox(
            height: ToplistTrackCard.cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: toplist.tracks.take(12).length,
              separatorBuilder: (c, i) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                return ToplistTrackCard(
                  track: toplist.tracks[index],
                  rank: index,
                  checkLoginStatus: checkLoginStatus,
                );
              },
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  toplist.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            
            if (ThemeManager().isFluentFramework)
              fluent.HyperlinkButton(
                onPressed: () => showToplistDetail(context, toplist),
                child: const Text('查看全部'),
              )
            else
              TextButton(
                onPressed: () => showToplistDetail(context, toplist),
                child: const Text('查看全部'),
              ),
          ],
        ),
        const SizedBox(height: _kSectionTitleGap),
        // 榜单区块改用流体条带（与「歌单榜」同一套左右滑动效果）：
        // 当前卡是完整方形封面 + 左下角名次 + 底部歌名/歌手，两侧被压成竖条，
        // 竖条上以竖排文字标出歌名。
        FluidStripCarousel(
          itemCount: toplist.tracks.take(12).length,
          coverBuilder: (context, index, compressed) => _ToplistStripCover(
            track: toplist.tracks[index],
            rank: index,
            compressed: compressed,
          ),
          onTapItem: (index) async {
            await checkLoginStatus();
            PlayerService().playTrack(toplist.tracks[index]);
          },
        ),
      ],
    );
  }
}

/// 榜单条带里的单张卡：封面 + 名次角标 + 歌名/歌手叠层。
///
/// 压扁（非当前卡）时只保留封面与竖排歌名，避免窄条上塞两行文字糊成一团。
class _ToplistStripCover extends StatelessWidget {
  const _ToplistStripCover({
    required this.track,
    required this.rank,
    required this.compressed,
  });

  final Track track;
  final int rank;
  final bool compressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Widget overlay;
    if (compressed) {
      overlay = track.name.isEmpty
          ? const SizedBox.shrink()
          : Center(
              child: RotatedBox(
                quarterTurns: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    } else {
      overlay = Positioned(
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
            padding: const EdgeInsets.fromLTRB(12, 22, 12, 12),
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
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                if (track.artists.isNotEmpty)
                  Text(
                    track.artists,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CachedNetworkImage(
          imageUrl: track.picUrl,
          httpHeaders: getImageHeaders(track.picUrl),
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => const LxImageFallback(),
        ),
        // 名次角标在最上层：压扁后仍要能看出这是第几名。
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: rank < 3
                  ? Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.5),
                      width: 1.5,
                    )
                  : Border.all(color: Colors.white10, width: 1),
            ),
            child: Text(
              '#${rank + 1}',
              style: TextStyle(
                color: rank < 3
                    ? theme.colorScheme.primary
                    : Colors.white.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        overlay,
      ],
    );
  }
}

class ToplistTrackCard extends StatefulWidget {
  final Track track;
  final int rank;
  final Future<void> Function() checkLoginStatus;

  const ToplistTrackCard({
    super.key,
    required this.track,
    required this.rank,
    required this.checkLoginStatus,
  });

  /// 卡宽。横向榜单列表用它算高度预算（见 [cardHeight]）。
  static const double cardWidth = 160;

  /// 卡高（含封面与下方两行文字）。
  ///
  /// 封面靠 `Expanded` 吃掉剩余空间，所以这个值决定封面实际多大：
  /// 220 − 间距 10 − 标题约 20 − 歌手约 16 − 底部留白 4 ≈ 170，
  /// 也就是封面约 160×170，接近方形。
  static const double cardHeight = 220;

  @override
  State<ToplistTrackCard> createState() => _ToplistTrackCardState();
}

class _ToplistTrackCardState extends State<ToplistTrackCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        // 原先靠 `Container(color: Colors.transparent)` 兜住命中测试；换成 LxSurface 后
        // 玻璃分支的外壳是 GlassContainer，命中行为不再由我们控制，这里显式声明
        // opaque 保证整张卡照旧可点（写法与 `swipe_recommend_card.dart:338` 一致）。
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await widget.checkLoginStatus();
          PlayerService().playTrack(widget.track);
        },
        child: SizedBox(
          width: ToplistTrackCard.cardWidth,
          // 封面直接作为卡片本体：表面内边距为 0，只靠表面的圆角裁剪。
          //
          // 上一版这里给了 12 的内边距，结果封面四周多出一圈底色，看起来像给封面
          // 套了个框——参考实现里没有这种效果。归零后封面从 136 宽长到 160 宽，
          // 同样的占地里封面更大，且圆角与框架分支（玻璃/实心）仍由 LxSurface 负责，
          // 不丢失「表面统一」本身。
          child: LxSurface(
            borderRadius: _surfaceRadius,
            clipBehavior: Clip.antiAlias,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 不再套 ClipRRect：封面已经贴到表面边缘，圆角由表面的裁剪给出，
                      // 再套一层会形成内外两道圆角。
                      AnimatedScale(
                        scale: _isHovering ? 1.05 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: CachedNetworkImage(
                          imageUrl: widget.track.picUrl,
                          httpHeaders: getImageHeaders(widget.track.picUrl),
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const LxImageFallback(),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12),
                            border: widget.rank < 3
                                ? Border.all(color: theme.colorScheme.primary.withOpacity(0.5), width: 1.5)
                                : Border.all(color: Colors.white10, width: 1),
                          ),
                          child: Text(
                            '#${widget.rank + 1}',
                            style: TextStyle(
                              color: widget.rank < 3 ? theme.colorScheme.primary : Colors.white.withOpacity(0.9),
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),
                      if (_isHovering)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 24,
                              color: Colors.black,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 文字区自带左右内边距（表面已无内边距，否则文字会顶到卡边）。
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        widget.track.artists,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 与首页推荐卡（`swipe_recommend_card.dart`）一致的统一圆角。
  static const double _surfaceRadius = 28;
}
