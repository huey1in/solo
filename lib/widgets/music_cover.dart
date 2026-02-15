import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'animated_equalizer.dart';

/// 通用音乐封面组件（支持 Hero 动画）
class MusicCover extends StatelessWidget {
  final dynamic music;
  final double size;
  final double radius;
  final bool showHero;
  final bool showAnimation; // 是否显示播放动画
  final bool useThumbnail; // 列表中使用缩略图
  final String baseUrl;

  const MusicCover({
    super.key,
    required this.music,
    required this.size,
    required this.radius,
    this.showHero = false,
    this.showAnimation = false,
    this.useThumbnail = false,
    required this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasCover = music['has_cover'] == true;
    final coverUrl = useThumbnail
        ? '$baseUrl/api/music/${music['id']}/cover?thumb=1'
        : '$baseUrl/api/music/${music['id']}/cover';

    Widget img = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: hasCover
          ? CachedNetworkImage(
              imageUrl: coverUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (c, url) => Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: const Icon(Icons.music_note, color: Colors.grey),
              ),
              errorWidget: (c, url, e) => Container(
                width: size,
                height: size,
                color: Colors.grey[200],
                child: const Icon(Icons.music_note),
              ),
            )
          : Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Icon(
                Icons.music_note,
                color: Colors.grey,
                size: size * 0.4,
              ),
            ),
    );

    // 如果需要显示动画遮罩，使用 Stack 叠加
    if (showAnimation) {
      img = Stack(
        alignment: Alignment.center,
        children: [
          img,
          // 半透明黑色遮罩
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
          // 播放动画
          const AnimatedEqualizer(isOverlay: true),
        ],
      );
    }

    return showHero ? Hero(tag: 'cover_${music['id']}', child: img) : img;
  }
}
