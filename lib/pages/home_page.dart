import 'package:flutter/material.dart';
import '../controllers/music_dashboard_controller.dart';
import '../services/player_manager.dart';
import '../widgets/music_cover.dart';

/// 首页
class HomePage extends StatelessWidget {
  final MusicDashboardController controller;
  final PlayerManager playerManager;
  final TextEditingController searchController;
  final Function(String) onSearchChanged;
  final Function(dynamic, {List<dynamic>? queue}) onPlayMusic;
  final Function(BuildContext, dynamic) onShowMusicMenu;
  final Function(BuildContext, dynamic) onRemoveFromRecent;
  final Function() onUploadMusic;
  final String baseUrl;

  const HomePage({
    super.key,
    required this.controller,
    required this.playerManager,
    required this.searchController,
    required this.onSearchChanged,
    required this.onPlayMusic,
    required this.onShowMusicMenu,
    required this.onRemoveFromRecent,
    required this.onUploadMusic,
    required this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();

    scrollController.addListener(() {
      if (scrollController.position.pixels >=
          scrollController.position.maxScrollExtent - 300) {
        if (!controller.isLoadingMore &&
            controller.currentPage < controller.totalPages) {
          controller.fetchMusic(loadMore: true);
        }
      }
    });

    return RefreshIndicator(
      onRefresh: () => controller.fetchMusic(isRefresh: true),
      color: const Color(0xFFFF4444),
      backgroundColor: Colors.white,
      displacement: 60,
      child: CustomScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildSearchBar(context)),
          if (!controller.isLoading && controller.recentList.isNotEmpty) ...[
            SliverToBoxAdapter(child: _buildSectionTitle("最近播放")),
            _buildRecentGrid(context),
          ],
          SliverToBoxAdapter(child: _buildSectionTitle("全部音乐")),
          if (controller.isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 120),
                  child: CircularProgressIndicator(
                    color: Color(0xFFFF4444),
                    strokeWidth: 3,
                  ),
                ),
              ),
            )
          else if (controller.musicList.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 120),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.music_off, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        '暂无音乐，下拉刷新试试',
                        style: TextStyle(fontSize: 15, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            _buildMusicList(context),
            if (controller.isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFFFF4444),
                      ),
                    ),
                  ),
                ),
              ),
            if (!controller.isLoadingMore &&
                controller.currentPage >= controller.totalPages &&
                controller.musicList.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      '— 已加载全部 ${controller.musicList.length} 首 —',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ),
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverToBoxAdapter(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 15, 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: const [
              Text(
                '我的乐库',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 28,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            hintText: '搜索歌曲...',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            isCollapsed: true,
            suffixIcon: controller.searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 15),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildRecentGrid(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 190,
        child: ListView.builder(
          padding: const EdgeInsets.only(left: 20),
          scrollDirection: Axis.horizontal,
          itemCount: controller.recentList.length,
          itemBuilder: (context, index) {
            final music = controller.recentList[index];
            return GestureDetector(
              onTap: () => onPlayMusic(music),
              onLongPress: () => onRemoveFromRecent(context, music),
              child: Container(
                width: 130,
                margin: const EdgeInsets.only(right: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MusicCover(
                      music: music,
                      size: 130,
                      radius: 20,
                      showHero: true,
                      useThumbnail: true,
                      baseUrl: baseUrl,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      music['title'] ?? '',
                      maxLines: 1,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      music['artist'] ?? '',
                      maxLines: 1,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMusicList(BuildContext context) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final music = controller.musicList[index];
        final isCurrent = playerManager.currentMusic?['id'] == music['id'];

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 5,
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            leading: MusicCover(
              music: music,
              size: 50,
              radius: 10,
              showHero: !isCurrent,
              showAnimation: isCurrent && playerManager.isPlaying,
              useThumbnail: true,
              baseUrl: baseUrl,
            ),
            title: Text(
              music['title'] ?? '',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isCurrent ? Colors.red : Colors.black,
              ),
            ),
            subtitle: Text(music['artist'] ?? ''),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => onShowMusicMenu(context, music),
            ),
            onTap: () => onPlayMusic(music, queue: controller.musicList),
          ),
        );
      }, childCount: controller.musicList.length),
    );
  }
}
