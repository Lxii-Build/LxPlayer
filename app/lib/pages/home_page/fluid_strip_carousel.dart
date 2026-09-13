import 'package:flutter/material.dart';

/// 「今日推荐」条带轮播：中间大卡 + 两侧被横向压扁的竖条。
///
/// 这版的观感**不是**普通轮播（各卡等宽、整体平移），而是：
///   - 当前卡是完整尺寸（近正方、圆角、歌名歌手叠在卡内左下角）
///   - 两侧的卡**高度不变、只有宽度被压缩**成竖条，且越远越窄
///   - 滑动时宽度**连续插值**，所以看起来像被拉扯/流动
///
/// 几何是从用户提供的录屏里逐帧量化出来的（画面宽 640 时）：
///   [大卡 249px] [间隙48] [69px] [15] [40px] [10] [13px…]
///   宽度比 ≈ 1.0 / 0.28 / 0.16 / 0.09
///
/// 用户确认：是「整卡非均匀位移缩放」，**不做网格顶点级形变**（不切分网格）。
///
/// 实现要点：宽度与间隙都由「到当前卡的距离」d（实数，滑动中连续变化）查表插值得到，
/// 所以形变是连续的，不会有跳变。
class FluidStripCarousel extends StatefulWidget {
  const FluidStripCarousel({
    super.key,
    required this.itemCount,
    required this.coverBuilder,
    this.onTapItem,
    this.height = 236,
    this.horizontalPadding = 18,
    this.itemGap = 16,
  });

  final int itemCount;
  final int initialIndex = 0;

  /// 封面构建器：`compressed` 表示这张卡正被压扁（用于决定是否显示文字）。
  final Widget Function(BuildContext context, int index, bool compressed) coverBuilder;

  final ValueChanged<int>? onTapItem;

  final double height;
  final double horizontalPadding;
  final double itemGap;

  @override
  State<FluidStripCarousel> createState() => _FluidStripCarouselState();
}

/// 宽度系数：索引 = 到当前卡的距离（整数处取值，之间线性插值）。
/// 与录屏量化结果一致：1.0 / 0.28 / 0.16 / 0.09，再往后继续衰减。
const List<double> _kWidthFactors = <double>[1.0, 0.28, 0.16, 0.09, 0.05];

/// 间隙系数：同样随距离衰减（录屏里量到 48 / 15 / 10）。
const List<double> _kGapFactors = <double>[1.0, 0.32, 0.22, 0.16, 0.12];

double _factorAt(List<double> table, double d) {
  if (d <= 0) return table.first;
  final int i = d.floor();
  if (i >= table.length - 1) return table.last;
  final double t = d - i;
  return table[i] + (table[i + 1] - table[i]) * t;
}

class _FluidStripCarouselState extends State<FluidStripCarousel>
    with SingleTickerProviderStateMixin {
  /// 当前卡的位置（实数）。滑动/动画期间会在两个整数之间连续变化。
  late double _position;
  int _target = 0;

  double _dragStart = 0;
  double _positionAtDragStart = 0;

  late final AnimationController _settle;
  late Animation<double> _settleAnim;

  @override
  void initState() {
    super.initState();
    _position = 0;
    _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _settleAnim = Tween<double>(begin: 0, end: 0)
        .animate(CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic))
      ..addListener(() {
        if (!mounted) return;
        setState(() => _position = _settleAnim.value);
      });

    if (widget.itemCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(widget.initialIndex, animate: false));
    }
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _goTo(int index, {bool animate = true}) {
    final int clamped = index.clamp(0, widget.itemCount - 1);
    _target = clamped;
    if (!animate) {
      _position = clamped.toDouble();
      setState(() {});
      return;
    }
    _settleAnim = Tween<double>(begin: _position, end: clamped.toDouble())
        .animate(CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic));
    _settle
      ..reset()
      ..forward();
  }

  /// 一屏能放下几张（含当前卡）。用于手势里把「像素位移」换算成「卡数位移」。
  double get _unit => 160.0;

  void _onHorizontalDragStart(DragStartDetails d) {
    _settle.stop();
    _dragStart = d.globalPosition.dx;
    _positionAtDragStart = _position;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    if (widget.itemCount <= 1) return;
    final double delta = (d.globalPosition.dx - _dragStart) / _unit;
    final double next = (_positionAtDragStart - delta).clamp(0, widget.itemCount - 1.0);
    setState(() => _position = next);
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    if (widget.itemCount <= 1) return;
    // 速度补偿：快速滑动时多带一屏，之后吸附到最近的一张。
    final double velocity = -(d.primaryVelocity ?? 0.0);
    final double projected = _position + velocity / 2600.0;
    final int snapped = projected.round().clamp(0, widget.itemCount - 1);
    _goTo(snapped);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double stripWidth = constraints.maxWidth - widget.horizontalPadding * 2;
        if (stripWidth <= 0) return const SizedBox.shrink();

        // 当前卡宽度：取条带的 45%（录屏里 249 / 554 ≈ 45%）。
        final double baseWidth = stripWidth * 0.45;

        final List<Widget> children = <Widget>[];
        double x = 0;
        for (int i = 0; i < widget.itemCount; i++) {
          final double d = (_position - i).abs();
          final double w = baseWidth * _factorAt(_kWidthFactors, d);
          // 越靠后的卡，它左侧的间隙也越小。
          final double gap = d > 0.5
              ? widget.itemGap * _factorAt(_kGapFactors, d)
              : widget.itemGap;
          x += gap;
          if (x + w > stripWidth && d > 0.5) {
            // 超出可视区域就不再摆（避免无意义地堆很多几乎看不见的竖条）。
            break;
          }
          children.add(Positioned(
            left: x,
            top: 0,
            bottom: 0,
            width: w,
            child: _CarouselItem(
              index: i,
              width: w,
              isActive: d < 0.5,
              onTap: () {
                if (d < 0.5) {
                  widget.onTapItem?.call(i);
                } else {
                  _goTo(i);
                }
              },
              child: widget.coverBuilder(context, i, d >= 0.5),
            ),
          ));
          x += w;
        }

        return SizedBox(
          height: widget.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            child: Stack(clipBehavior: Clip.none, children: children),
          ),
        );
      },
    );
  }
}

class _CarouselItem extends StatelessWidget {
  const _CarouselItem({
    required this.index,
    required this.width,
    required this.isActive,
    required this.onTap,
    required this.child,
  });

  final int index;
  final double width;
  final bool isActive;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        // 压得越窄，圆角也要跟着收，否则竖条上会出现奇怪的大圆角。
        borderRadius: BorderRadius.circular(width < 64 ? 12 : 28),
        child: child,
      ),
    );
  }
}
