import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:async';
import '../services/music_api_service.dart';
import '../services/storage_service.dart';
import '../services/player_manager.dart';
import '../controllers/music_dashboard_controller.dart';
import '../widgets/glass_bottom_player.dart';
import '../widgets/music_cover.dart';
import '../widgets/custom_toast.dart';
import 'music_player_page.dart';
import '../utils/dialog_utils.dart';
import 'home_page.dart';
import 'favorites_page.dart';

/// 音乐仪表板主页面
class MusicDashboardPage extends StatefulWidget {
  const MusicDashboardPage({super.key});

  @override
  State<MusicDashboardPage> createState() => _MusicDashboardPageState();
}

class _MusicDashboardPageState extends State<MusicDashboardPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const String baseUrl = "https://solo.yinxh.fun";

  late MusicDashboardController _controller;
  late PlayerManager _playerManager;
  late AnimationController _rotationController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 初始化播放器
    final audioPlayer = AudioPlayer();
    _playerManager = PlayerManager(audioPlayer: audioPlayer, baseUrl: baseUrl);

    // 初始化控制器
    _controller = MusicDashboardController(
      apiService: MusicApiService(baseUrl),
      storageService: StorageService.instance,
      playerManager: _playerManager,
    );

    // 设置回调
    _controller.onStateChanged = () {
      if (mounted) setState(() {});
    };
    _controller.onShowToast = (message, {type = ToastType.info}) {
      switch (type) {
        case ToastType.success:
          CustomToast.success(context, message);
          break;
        case ToastType.error:
          CustomToast.error(context, message);
          break;
        case ToastType.loading:
          CustomToast.showLoading(context, message);
          break;
        case ToastType.info:
          CustomToast.info(context, message);
          break;
      }
    };

    _playerManager.onPlayingChanged = (playing) {
      if (mounted) setState(() {});
      playing ? _rotationController.repeat() : _rotationController.stop();
    };

    _playerManager.onLoadingChanged = (loading) {
      if (mounted) setState(() {});
      if (loading) {
        _showLoadingToast();
      } else {
        _hideLoadingToast();
      }
    };

    _playerManager.onPositionChanged = (position) {
      if (mounted) setState(() {});
    };

    _playerManager.onDurationChanged = (duration) {
      if (mounted) setState(() {});
    };

    _playerManager.onCompleted = () {
      _playerManager.playNext();
    };

    _playerManager.onMusicChanged = (music) {
      _controller.addToRecent(music);
      if (mounted) setState(() {});
    };

    // 初始化旋转动画
    _rotationController = AnimationController(
      duration: const Duration(seconds: 15),
      vsync: this,
    );

    // 配置音频会话
    _playerManager.configureAudioSession();

    // 初始化数据
    _controller.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _controller.dispose();
    _playerManager.dispose();
    _rotationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller.saveAllDataImmediately();
    }
    if (state == AppLifecycleState.resumed) {
      _controller.recoverFromBackground();
    }
  }

  void _showToast(String message) {
    CustomToast.info(context, message);
  }

  void _showLoadingToast() {
    CustomToast.showLoading(context, '正在加载音频...');
  }

  void _hideLoadingToast() {
    CustomToast.hideLoading();
  }

  void _openPlayerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (context) => MusicPlayerPageNew(
        getCurrentMusic: () => _playerManager.currentMusic,
        audioPlayer: _playerManager.audioPlayer,
        isPlaying: _playerManager.isPlaying,
        currentPosition: _playerManager.currentPosition,
        totalDuration: _playerManager.totalDuration,
        onPlayPause: () => _handlePlayPause(),
        onNext: () => _playerManager.playNext(),
        onPrevious: () => _playerManager.playPrevious(),
        playMode: _playerManager.playMode,
        onTogglePlayMode: () {
          _playerManager.togglePlayMode();
          _controller.savePreferences();
          setState(() {});
        },
        onVolumeChanged: () => _controller.savePreferences(),
        isFavorite: _controller.isFavorite(_playerManager.currentMusic['id']),
        onToggleFavorite: () {
          _controller.toggleFavorite(_playerManager.currentMusic);
        },
        checkIsFavorite: _controller.isFavorite,
        playQueue: _playerManager.playQueue,
        onPlayFromQueue: (music) => _handlePlayMusic(music),
        baseUrl: baseUrl,
        onClose: () {
          _playerManager.currentMusic = null;
          _controller.savePreferences();
        },
      ),
    );
  }

  Future<void> _handlePlayMusic(dynamic music, {List<dynamic>? queue}) async {
    try {
      await _playerManager.playMusic(music, queue: queue);
    } catch (e) {
      // 播放失败时只显示提示，不自动跳过
      _showToast('歌曲 ${music['title']} 加载失败');
      print('播放音乐失败: $e');
    }
  }

  void _handlePlayPause() {
    if (_playerManager.currentMusic != null) {
      _handlePlayMusic(_playerManager.currentMusic);
    }
  }

  void _showMusicMenu(BuildContext context, dynamic music) {
    final isFavorite = _controller.isFavorite(music['id']);

    DialogUtils.showCustomBottomSheet(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DialogUtils.buildMenuOption(
            icon: isFavorite ? Icons.favorite : Icons.favorite_border,
            title: isFavorite ? '取消收藏' : '添加到喜欢',
            onTap: () {
              Navigator.pop(context);
              Future.delayed(const Duration(milliseconds: 300), () {
                _controller.toggleFavorite(music);
              });
            },
          ),
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
          DialogUtils.buildMenuOption(
            icon: Icons.skip_next_outlined,
            title: '下一首播放',
            onTap: () {
              Navigator.pop(context);
              Future.delayed(const Duration(milliseconds: 300), () {
                _controller.playNext(music);
              });
            },
          ),
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
          DialogUtils.buildMenuOption(
            icon: Icons.playlist_add,
            title: '添加到播放队列',
            onTap: () {
              Navigator.pop(context);
              Future.delayed(const Duration(milliseconds: 300), () {
                _controller.addToQueue(music);
              });
            },
          ),
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
          DialogUtils.buildMenuOption(
            icon: Icons.delete_outline,
            title: '删除',
            onTap: () {
              Navigator.pop(context);
              Future.delayed(const Duration(milliseconds: 300), () {
                _deleteMusicConfirm(context, music);
              });
            },
          ),
        ],
      ),
    );
  }

  void _deleteMusicConfirm(BuildContext context, dynamic music) {
    DialogUtils.showCustomDialog(
      context: context,
      title: '确认删除',
      content: Text('确定要删除 ${music['title']} 吗？'),
      confirmText: '删除',
      isDestructive: true,
      onConfirm: () => _controller.deleteMusic(music),
    );
  }

  void _removeFromRecentConfirm(BuildContext context, dynamic music) {
    DialogUtils.showCustomDialog(
      context: context,
      title: '移除确认',
      content: '确定要从最近播放中移除 ${music['title']} 吗？',
      confirmText: '移除',
      isDestructive: true,
      onConfirm: () => _controller.removeFromRecent(music),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              HomePage(
                controller: _controller,
                playerManager: _playerManager,
                searchController: _searchController,
                onSearchChanged: (value) {
                  _controller.searchQuery = value;
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () {
                      _controller.fetchMusic();
                    },
                  );
                },
                onPlayMusic: _handlePlayMusic,
                onShowMusicMenu: _showMusicMenu,
                onRemoveFromRecent: _removeFromRecentConfirm,
                onUploadMusic: _controller.uploadMusic,
                baseUrl: baseUrl,
              ),
              FavoritesPage(
                controller: _controller,
                playerManager: _playerManager,
                onPlayMusic: _handlePlayMusic,
                baseUrl: baseUrl,
              ),
            ],
          ),
          if (_playerManager.currentMusic != null)
            GlassBottomPlayer(
              currentMusic: _playerManager.currentMusic,
              isPlaying: _playerManager.isPlaying,
              rotationController: _rotationController,
              onTap: _openPlayerSheet,
              onPlayPause: _handlePlayPause,
              baseUrl: baseUrl,
              buildCover:
                  (
                    music, {
                    required size,
                    required radius,
                    showHero = false,
                    showAnimation = false,
                    useThumbnail = false,
                  }) {
                    return MusicCover(
                      music: music,
                      size: size,
                      radius: radius,
                      showHero: showHero,
                      showAnimation: showAnimation,
                      useThumbnail: useThumbnail,
                      baseUrl: baseUrl,
                    );
                  },
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: '喜欢'),
        ],
        selectedItemColor: const Color(0xFFFF4444),
        unselectedItemColor: Colors.grey,
      ),
    );
  }
}
