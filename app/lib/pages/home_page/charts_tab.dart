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
import 'swipe_recommend_card.dart';
import 'toplist_detail.dart';
import '../../widgets/lx_surface.dart';
import '../../widgets/oculus/oculus_home_widgets.dart';
import '../../widgets/skeleton_loader.dart';

class ChartsTab extends StatelessWidget {
  final List<Track> cachedRandomTracks;
  final Future<void> Function() checkLoginStatus;
  final Future<List<Track>>? guessYouLikeFuture;
  final VoidCallback onRefresh;

  const ChartsTab({
    super.key,
    required this.cachedRandomTracks,
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
              padding: const EdgeInsets.only(top: 16, bottom: 40),
              child: Text(
                '音乐榜单',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),

            // 1. 顶部 BENTO GRID
            Padding(
              padding: const EdgeInsets.only(bottom: 56),
              child: _buildFeaturedSection(context, constraints),
            ),

            // 2. 历史与推荐 (Quick Access)
            Padding(
              padding: const EdgeInsets.only(bottom: 56),
              child: _buildQuickAccessSection(context, isWide),
            ),

            // 3. 榜单列表 (更具表现力的间距)
            ...MusicService().toplists.map((toplist) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 64.0),
                child: _ToplistSection(
                  toplist: toplist,
                  checkLoginStatus: checkLoginStatus,
                ),
              );
            }),
            
             SizedBox(height: MediaQuery.of(context).padding.bottom + 80),
          ],
        );
      },
    );
  }

  Widget _buildFeaturedSection(BuildContext context, BoxConstraints constraints) {
    if (cachedRandomTracks.isEmpty) return const SizedBox.shrink();

    // 桌面端与窄屏共用同一张卡。此前桌面端是 Bento 三宫格、窄屏是一大两窄的
    // 轮播，两种观感都跟「每日推荐」对不上，统一成三层扇形封面 + 离散跳变滑动。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Text(
            '每日推荐',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
        SwipeRecommendCard(
          tracks: cachedRandomTracks,
          onPlay: (track) async {
            await checkLoginStatus();
            PlayerService().playTrack(track);
          },
        ),
      ],
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
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: toplist.tracks.take(12).length,
              separatorBuilder: (c, i) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                return _ToplistTrackCard(
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
        const SizedBox(height: 24),
        SizedBox(
          height: 220, // 增加高度以容纳更美观的卡片
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: toplist.tracks.take(12).length,
            separatorBuilder: (c, i) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              return _ToplistTrackCard(
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
}

class _ToplistTrackCard extends StatefulWidget {
  final Track track;
  final int rank;
  final Future<void> Function() checkLoginStatus;

  const _ToplistTrackCard({
    required this.track,
    required this.rank,
    required this.checkLoginStatus,
  });

  @override
  State<_ToplistTrackCard> createState() => _ToplistTrackCardState();
}

class _ToplistTrackCardState extends State<_ToplistTrackCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = 160.0; // 宽度略微增加
    final borderRadius = BorderRadius.circular(24); // 圆角增加

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
          width: width,
          // 表面统一交给 LxSurface（替换原先的 `Container(color: transparent)`：
          // 榜单卡此前是"裸卡"，没有任何表面，正是首页上下割裂的来源之一）。
          //
          // 高度预算复核（外层是 `SizedBox(height: 220)`）：固定高度部分 =
          // 上下内边距 24 + 间距 12 + 标题约 20 + 副标题约 16 ≈ 72，
          // 剩下约 148 全部归 Expanded 的封面，不会溢出。封面走 BoxFit.cover，
          // 尺寸从 160×172 收到约 136×148，只会多裁一点，不会被压变形。
          // 原先贴在两行文字上的 `horizontal: 4` 内边距由表面的 12 接管，去掉后
          // 文字与封面依然左对齐。
          child: LxSurface(
            borderRadius: _surfaceRadius,
            padding: const EdgeInsets.all(_surfacePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: borderRadius,
                        child: AnimatedScale(
                          scale: _isHovering ? 1.05 : 1.0,
                          duration: const Duration(milliseconds: 200),
                          child: CachedNetworkImage(
                            imageUrl: widget.track.picUrl,
                            httpHeaders: getImageHeaders(widget.track.picUrl),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        left: 4,
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
                const SizedBox(height: 12),
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
        ),
      ),
    );
  }

  /// 与首页推荐卡（`swipe_recommend_card.dart`）一致的统一圆角。
  static const double _surfaceRadius = 28;

  /// 表面内边距。榜单卡是横向列表里的窄卡（160 宽），用 12 而不是推荐卡的 20：
  /// 20 会把 160 的封面挤到 120，封面明显变小；12 既能露出表面边框又不吃掉封面。
  static const double _surfacePadding = 12;
}
