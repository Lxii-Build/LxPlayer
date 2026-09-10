import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/track.dart';
import '../../utils/image_utils.dart';

/// 一次拖动的判定结果。
enum SwipeDecision {
  /// 位移没到激活阈值，什么都不做。
  ignore,

  /// 纵向先越界，手势让位给页面滚动。
  failToVertical,

  /// 已激活但没到提交阈值。
  pending,

  /// 左滑提交：下一张。
  commitNext,

  /// 右滑提交：上一张。
  commitPrev,
}

/// 滑动判定。
///
/// 交互刻意不用 PageView：参考手感是「拖动时卡片静止，松手越过阈值后整卡换一张」，
/// PageView 给的是跟手滚动的另一种手感。
///
/// 阈值取自参考实现实测：横向 12 激活、纵向 24 让位、横向 36 提交（只看位移，不看速度）。
class SwipeGesturePolicy {
  static const double activateThreshold = 12;
  static const double failVerticalThreshold = 24;
  static const double commitThreshold = 36;

  /// 松手后的入场动画时长。
  static const Duration enterDuration = Duration(milliseconds: 260);

  /// 入场动画的初始横向偏移，方向与滑动方向一致。
  static const double enterOffset = 40;

  static SwipeDecision decide(double dx, double dy) {
    final absX = dx.abs();
    final absY = dy.abs();

    // 纵向先越界就让位给页面滚动，否则卡片会吃掉整页的上下滑。
    if (absY >= failVerticalThreshold && absY > absX) {
      return SwipeDecision.failToVertical;
    }
    if (absX < activateThreshold) return SwipeDecision.ignore;
    if (absX < commitThreshold) return SwipeDecision.pending;
    return dx < 0 ? SwipeDecision.commitNext : SwipeDecision.commitPrev;
  }

  /// 循环换算下标，越界回绕。
  static int wrapIndex(int current, int direction, int size) {
    if (size <= 0) return 0;
    return (current + direction) % size;
  }

  static int directionOf(SwipeDecision decision) {
    switch (decision) {
      case SwipeDecision.commitNext:
        return 1;
      case SwipeDecision.commitPrev:
        return -1;
      default:
        return 0;
    }
  }
}

/// 扇形封面堆叠的一层参数。数值来自参考交互实测。
class FanLayerSpec {
  const FanLayerSpec({
    required this.name,
    required this.width,
    required this.height,
    required this.offsetRight,
    required this.offsetTop,
    required this.opacity,
    required this.rotationDegrees,
  });

  final String name;
  final double width;
  final double height;
  final double offsetRight;
  final double offsetTop;
  final double opacity;
  final double rotationDegrees;
}

/// 三层扇形封面的设计参数，测试直接核对这份清单。
const List<FanLayerSpec> fanCoverLayerSpecs = [
  FanLayerSpec(
    name: 'back',
    width: 112,
    height: 144,
    offsetRight: 1,
    offsetTop: 9,
    opacity: 0.35,
    rotationDegrees: 12,
  ),
  FanLayerSpec(
    name: 'mid',
    width: 120,
    height: 160,
    offsetRight: 18,
    offsetTop: 4,
    opacity: 0.65,
    rotationDegrees: 5,
  ),
  FanLayerSpec(
    name: 'front',
    width: 128,
    height: 176,
    offsetRight: 36,
    offsetTop: 0,
    opacity: 1,
    rotationDegrees: -4,
  ),
];

const double fanStackWidth = 160;
const double fanStackHeight = 192;
const double _fanCoverRadius = 24;

/// 首页推荐卡：单卡 + 三层扇形封面 + 离散跳变式左右滑动。
///
/// 滑动语义：默认只浏览；若当前播放的曲目就在这批推荐里，滑动同时切换队列
/// ——按稳定 id 判定而非下标，随机播放打乱顺序后也不会切错歌。
class SwipeRecommendCard extends StatefulWidget {
  const SwipeRecommendCard({
    super.key,
    required this.tracks,
    this.onPlay,
    this.onIndexChanged,
    this.initialIndex = 0,
    this.animateEntrance = true,
  });

  final List<Track> tracks;

  /// 点播放胶囊。
  final void Function(Track track)? onPlay;

  /// 换页回调，带上新的下标与方向（1 前进 / -1 后退）。
  final void Function(int index, int direction)? onIndexChanged;

  final int initialIndex;

  /// 关掉入场动画，供测试拿到稳定尺寸。
  final bool animateEntrance;

  @override
  State<SwipeRecommendCard> createState() => _SwipeRecommendCardState();
}

class _SwipeRecommendCardState extends State<SwipeRecommendCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  int _index = 0;
  int _direction = 0;

  double _dx = 0;
  double _dy = 0;
  bool _committed = false;
  bool _abandoned = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _enter = AnimationController(
      vsync: this,
      duration: SwipeGesturePolicy.enterDuration,
      value: 1,
    );
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  void _commit(int direction) {
    setState(() {
      _direction = direction;
      _index = SwipeGesturePolicy.wrapIndex(_index, direction, widget.tracks.length);
    });
    widget.onIndexChanged?.call(_index, direction);
    if (widget.animateEntrance) {
      _enter
        ..value = 0
        ..forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tracks.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final featured = widget.tracks[_index.clamp(0, widget.tracks.length - 1)];

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(20),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          _dx = 0;
          _dy = 0;
          _committed = false;
          _abandoned = false;
        },
        onHorizontalDragUpdate: (details) {
          if (_committed || _abandoned) return;
          _dx += details.delta.dx;
          _dy += details.delta.dy;
          final decision = SwipeGesturePolicy.decide(_dx, _dy);
          if (decision == SwipeDecision.failToVertical) {
            _abandoned = true;
            return;
          }
          // 拖动过程中卡片刻意保持静止——参考手感如此，
          // 跟手位移会变成另一种交互。
          if (decision == SwipeDecision.commitNext ||
              decision == SwipeDecision.commitPrev) {
            _committed = true;
            _commit(SwipeGesturePolicy.directionOf(decision));
          }
        },
        child: AnimatedBuilder(
          animation: _enter,
          builder: (context, child) {
            final t = _enter.value;
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(
                  SwipeGesturePolicy.enterOffset * _direction * (1 - t),
                  0,
                ),
                child: child,
              ),
            );
          },
          child: _CardBody(
            tracks: widget.tracks,
            index: _index,
            featured: featured,
            onPlay: widget.onPlay,
          ),
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.tracks,
    required this.index,
    required this.featured,
    this.onPlay,
  });

  final List<Track> tracks;
  final int index;
  final Track featured;
  final void Function(Track track)? onPlay;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: fanStackHeight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '为你推荐',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    featured.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    featured.artists,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: onPlay == null ? null : () => onPlay!(featured),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('播放'),
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          FanCoverStack(tracks: tracks, featuredIndex: index),
        ],
      ),
    );
  }
}

/// 三层扇形封面。
///
/// 后两层展示队列里接下来的封面，制造「还有更多」的暗示——
/// 这是参考实现用来替代分页指示器的手法：不画圆点，用露出的封面告诉你可以滑。
class FanCoverStack extends StatelessWidget {
  const FanCoverStack({
    super.key,
    required this.tracks,
    required this.featuredIndex,
  });

  final List<Track> tracks;
  final int featuredIndex;

  String? _coverAt(int offset) {
    if (tracks.isEmpty) return null;
    final i = SwipeGesturePolicy.wrapIndex(featuredIndex, offset, tracks.length);
    final url = tracks[i].picUrl;
    if (url.isNotEmpty) return url;
    return tracks[featuredIndex.clamp(0, tracks.length - 1)].picUrl;
  }

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: fanStackWidth,
      height: fanStackHeight,
      child: Stack(
        children: [
          _layer(context, fanCoverLayerSpecs[0], _coverAt(2)),
          _layer(context, fanCoverLayerSpecs[1], _coverAt(1)),
          _layer(context, fanCoverLayerSpecs[2], _coverAt(0), withShadow: true),
        ],
      ),
    );
  }

  Widget _layer(
    BuildContext context,
    FanLayerSpec spec,
    String? url, {
    bool withShadow = false,
  }) {
    return Positioned(
      right: spec.offsetRight,
      top: spec.offsetTop,
      child: Opacity(
        opacity: spec.opacity,
        child: Transform.rotate(
          angle: spec.rotationDegrees * 3.1415926535 / 180,
          child: Container(
            width: spec.width,
            height: spec.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_fanCoverRadius),
              boxShadow: withShadow
                  ? const [
                      BoxShadow(
                        color: Color(0x3817212D),
                        blurRadius: 14,
                        offset: Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_fanCoverRadius),
              child: _cover(context, url),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, String? url) {
    final cs = Theme.of(context).colorScheme;
    if (url == null || url.isEmpty) {
      return Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.music_note_rounded, color: cs.onSurfaceVariant),
      );
    }
    // 与项目其它封面一致：走 CachedNetworkImage 并带上鉴权头，
    // 部分音源的图片 CDN 需要 Referer。
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: getImageHeaders(url),
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: cs.surfaceContainerHighest),
      errorWidget: (_, __, ___) => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.music_note_rounded, color: cs.onSurfaceVariant),
      ),
    );
  }
}
