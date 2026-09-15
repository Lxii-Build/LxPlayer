import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/theme_manager.dart';
import '../../utils/image_utils.dart';
import '../../widgets/lx_surface.dart';

/// 歌单网格（移动端）
class MobilePlaylistGrid extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  final void Function(int id)? onTap;
  const MobilePlaylistGrid({super.key, required this.list, this.onTap});
  
  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.68,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final p = list[i];
        final pic = (p['picUrl'] ?? p['coverImgUrl'] ?? '').toString();
        final idVal = p['id'];
        final id = int.tryParse(idVal?.toString() ?? '');
        return InkWell(
          onTap: id != null && onTap != null ? () => onTap!(id) : null,
          child: MobileHoverPlaylistCard(
            id: id ?? 0,
            name: p['name']?.toString() ?? '',
            picUrl: pic,
            description: (p['description'] ?? p['copywriter'] ?? '').toString(),
          ),
        );
      },
    );
  }
}

/// 悬停歌单卡片（移动端）
class MobileHoverPlaylistCard extends StatefulWidget {
  final int id;
  final String name;
  final String picUrl;
  final String description;
  const MobileHoverPlaylistCard({super.key, required this.id, required this.name, required this.picUrl, required this.description});

  @override
  State<MobileHoverPlaylistCard> createState() => _MobileHoverPlaylistCardState();
}

class _MobileHoverPlaylistCardState extends State<MobileHoverPlaylistCard> {
  bool _hovering = false;

  /// 与首页推荐卡（`swipe_recommend_card.dart`）一致的统一圆角。
  static const double _surfaceRadius = 28;

  /// 封面裁剪圆角（沿用改造前 Material 分支的观感值）。
  static const double _coverRadius = 24;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          // 悬停投影跟随统一圆角，避免投影轮廓与卡片轮廓错开。
          borderRadius: BorderRadius.circular(_surfaceRadius),
          boxShadow: _hovering
              ? [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        // 表面（背景 / 圆角 / 边框）交给 LxSurface：原先 Cupertino 手写容器与
        // Material `Card` 两条分支收敛为一条，写死的 0xFF1C1C1E / CupertinoColors.white 撤掉。
        child: LxSurface(
          borderRadius: _surfaceRadius,
          clipBehavior: Clip.antiAlias,
          child: _buildContent(cs, isCupertino),
        ),
      ),
    );
  }

  /// 卡片内容：封面（含悬停放大 + 底部渐变描述）+ 标题。两套框架共用同一布局，
  /// 只有占位 / 错误图标按框架取各自的图标集。
  Widget _buildContent(ColorScheme cs, bool isCupertino) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            // 封面自己也裁一次圆角：外层表面裁的是 28 的卡片轮廓，这里的 24 是
            // 封面本身的观感值（沿用改造前 Material 分支），两者叠加不冲突。
            borderRadius: BorderRadius.circular(_coverRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                SizedBox.expand(
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    scale: _hovering ? 1.10 : 1.0,
                    child: Hero(
                      tag: 'playlist_cover_${widget.id}',
                      child: CachedNetworkImage(
                        imageUrl: widget.picUrl,
                        httpHeaders: getImageHeaders(widget.picUrl),
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            isCupertino ? CupertinoIcons.music_note : Icons.music_note,
                            color: cs.onSurface.withOpacity(0.3),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            isCupertino ? CupertinoIcons.exclamationmark_circle : Icons.broken_image,
                            color: cs.onSurface.withOpacity(0.3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    offset: _hovering ? Offset.zero : const Offset(0, 1),
                    child: FractionallySizedBox(
                      widthFactor: 1.0,
                      heightFactor: 0.38,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.0),
                              Colors.black.withOpacity(0.65),
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Text(
                            (widget.description.isNotEmpty ? widget.description : widget.name),
                            style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                widget.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                textAlign: TextAlign.left,
                // 前景色由主题接管，不再按 isDark 写死黑白。
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
