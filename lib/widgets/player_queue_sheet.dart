import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'animated_equalizer.dart';

/// 播放队列底部弹窗
class PlayerQueueSheet extends StatelessWidget {
  final List<dynamic> playQueue;
  final dynamic currentMusic;
  final String baseUrl;
  final Function(dynamic) onPlayFromQueue;
  final bool Function(String) checkIsFavorite;

  const PlayerQueueSheet({
    super.key,
    required this.playQueue,
    required this.currentMusic,
    required this.baseUrl,
    required this.onPlayFromQueue,
    required this.checkIsFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pop(context),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (context, scrollController) => GestureDetector(
          onTap: () {},
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[900]?.withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '播放队列',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${playQueue.length} 首',
                        style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.grey[800]),
                Expanded(
                  child: playQueue.isEmpty
                      ? Center(
                          child: Text(
                            '播放队列为空',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 16,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: playQueue.length,
                          itemBuilder: (context, index) {
                            final music = playQueue[index];
                            final isCurrentPlaying =
                                currentMusic?['id'] == music['id'];

                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: music['has_cover'] == true
                                    ? CachedNetworkImage(
                                        imageUrl:
                                            '$baseUrl/api/music/${music['id']}/cover',
                                        width: 42,
                                        height: 42,
                                        fit: BoxFit.cover,
                                        placeholder: (c, url) => Container(
                                          width: 42,
                                          height: 42,
                                          color: Colors.grey[800],
                                          child: const Icon(
                                            Icons.music_note,
                                            color: Colors.grey,
                                            size: 20,
                                          ),
                                        ),
                                        errorWidget: (c, url, e) => Container(
                                          width: 42,
                                          height: 42,
                                          color: Colors.grey[800],
                                          child: const Icon(
                                            Icons.music_note,
                                            color: Colors.grey,
                                            size: 20,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[800],
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.music_note,
                                          color: Colors.grey,
                                          size: 20,
                                        ),
                                      ),
                              ),
                              title: Text(
                                music['title'] ?? '未知歌曲',
                                style: TextStyle(
                                  color: isCurrentPlaying
                                      ? const Color(0xFFFF4444)
                                      : Colors.white,
                                  fontWeight: isCurrentPlaying
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                music['artist'] ?? '未知艺术家',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: isCurrentPlaying
                                  ? const AnimatedEqualizer(
                                      barColor: Color(0xFFFF4444),
                                    )
                                  : null,
                              onTap: () {
                                Navigator.pop(context);
                                if (!isCurrentPlaying) {
                                  onPlayFromQueue(music);
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
