import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 播放器封面组件
class PlayerCover extends StatelessWidget {
  final String coverUrl;
  final String? musicId;

  const PlayerCover({super.key, required this.coverUrl, this.musicId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.width * 0.8,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: coverUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[900],
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white38,
                        strokeWidth: 2,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[900],
                    child: const Icon(
                      Icons.music_note,
                      color: Colors.white,
                      size: 100,
                    ),
                  ),
                )
              : Container(
                  color: Colors.grey[900],
                  child: const Icon(
                    Icons.music_note,
                    color: Colors.white54,
                    size: 100,
                  ),
                ),
        ),
      ),
    );
  }
}
