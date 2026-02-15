import 'package:flutter/material.dart';
import '../controllers/music_dashboard_controller.dart';
import '../services/player_manager.dart';
import '../widgets/music_cover.dart';
import '../widgets/animated_equalizer.dart';

/// 喜欢页面
class FavoritesPage extends StatelessWidget {
  final MusicDashboardController controller;
  final PlayerManager playerManager;
  final Function(dynamic, {List<dynamic>? queue}) onPlayMusic;
  final String baseUrl;

  const FavoritesPage({
    super.key,
    required this.controller,
    required this.playerManager,
    required this.onPlayMusic,
    required this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    final favoriteSongs = controller.favoriteSongs;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 15, 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    '我喜欢',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    '${favoriteSongs.length} 首歌曲',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (favoriteSongs.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无喜欢的歌曲',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final music = favoriteSongs[index];
              return _buildFavoriteMusicCard(context, music);
            }, childCount: favoriteSongs.length),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildFavoriteMusicCard(BuildContext context, dynamic music) {
    final isPlaying = playerManager.currentMusic?['id'] == music['id'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: () => onPlayMusic(music, queue: controller.favoriteSongs),
        leading: Stack(
          alignment: Alignment.center,
          children: [
            MusicCover(
              music: music,
              size: 50,
              radius: 8,
              useThumbnail: true,
              baseUrl: baseUrl,
            ),
            if (isPlaying) const AnimatedEqualizer(),
          ],
        ),
        title: Text(
          music['title'] ?? '未知歌曲',
          style: TextStyle(
            fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
            color: isPlaying ? const Color(0xFFFF4444) : Colors.black87,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          music['artist'] ?? '未知艺术家',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.favorite, color: Color(0xFFFF4444)),
          onPressed: () => controller.toggleFavorite(music),
        ),
      ),
    );
  }
}
