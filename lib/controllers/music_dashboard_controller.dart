import 'dart:async';
import 'dart:io' show Platform;
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../services/music_api_service.dart';
import '../services/storage_service.dart';
import '../services/player_manager.dart';
import '../audio_cache_service.dart';
import '../widgets/custom_toast.dart';

/// 提示回调类型
typedef ToastCallback = void Function(String message, {ToastType type});

/// 音乐仪表板控制器
class MusicDashboardController {
  final MusicApiService apiService;
  final StorageService storageService;
  final PlayerManager playerManager;

  // 数据状态
  List<dynamic> musicList = [];
  List<dynamic> recentList = [];
  List<dynamic> favoriteSongs = [];
  bool isLoading = true;
  bool isLoadingMore = false;
  int currentPage = 1;
  int totalPages = 1;
  String searchQuery = "";
  bool isInitialized = false;
  bool isOffline = false;
  bool isRecovering = false;

  // 定时器
  Timer? saveProgressTimer;
  Timer? healthCheckTimer;
  StreamSubscription? connectivitySubscription;

  // 回调函数
  Function()? onStateChanged;
  ToastCallback? onShowToast;

  static const int pageSize = 30;

  MusicDashboardController({
    required this.apiService,
    required this.storageService,
    required this.playerManager,
  });

  /// 初始化
  Future<void> init() async {
    await _loadPreferences();
    isInitialized = true;

    // 加载缓存的音乐列表
    await _loadCachedMusicList();

    // 如果有缓存，先显示缓存数据
    if (musicList.isNotEmpty) {
      isLoading = false;
      onStateChanged?.call();
    }

    // 从服务器获取最新数据
    await fetchMusic();

    // 启动定时保存
    saveProgressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (isInitialized && playerManager.currentMusic != null) {
        savePreferences();
      }
    });

    // 启动健康检查
    healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      playerManager.checkHealth();
    });

    // 监听网络状态
    _setupConnectivityListener();
  }

  /// 加载偏好设置
  Future<void> _loadPreferences() async {
    print('[_loadPreferences] 开始加载偏好设置');

    print('[_loadPreferences] 加载播放模式');
    playerManager.playMode = await storageService.loadPlayMode();

    print('[_loadPreferences] 加载音量');
    final volume = await storageService.loadVolume();
    playerManager.audioPlayer.setVolume(volume);

    print('[_loadPreferences] 加载最近播放列表');
    recentList = await storageService.loadRecentList();

    print('[_loadPreferences] 加载播放队列');
    playerManager.playQueue = await storageService.loadPlayQueue();

    print('[_loadPreferences] 加载收藏列表');
    favoriteSongs = await storageService.loadFavorites();

    print('[_loadPreferences] 恢复当前播放音乐');
    // 恢复当前播放音乐（不阻塞初始化）
    final currentData = await storageService.loadCurrentMusic();
    if (currentData != null) {
      print('[_loadPreferences] 找到当前音乐: ${currentData['music']['title']}');
      playerManager.currentMusic = currentData['music'];
      // 异步恢复播放，不阻塞初始化流程
      _restorePlayback(currentData['music'], currentData['position'] as int);
    } else {
      print('[_loadPreferences] 没有当前音乐');
    }

    print('[_loadPreferences] 完成');
    onStateChanged?.call();
  }

  /// 异步恢复播放
  Future<void> _restorePlayback(dynamic music, int position) async {
    try {
      // 只恢复音频源和进度，不自动播放
      final streamUrl = '${apiService.baseUrl}/api/music/${music['id']}/stream';

      if (AudioCacheService.instance.isCached(streamUrl)) {
        await playerManager.audioPlayer.setAudioSource(
          AudioSource.file(
            AudioCacheService.instance.getCacheFilePath(streamUrl),
          ),
          initialPosition: Duration(milliseconds: position),
        );
      } else {
        await playerManager.audioPlayer.setAudioSource(
          LockCachingAudioSource(
            Uri.parse(streamUrl),
            cacheFile: AudioCacheService.instance.getCacheFile(streamUrl),
          ),
          initialPosition: Duration(milliseconds: position),
        );
      }

      // 确保是暂停状态
      await playerManager.audioPlayer.pause();
    } catch (e) {
      print('恢复播放失败: $e');
      // 恢复失败时清除当前音乐
      playerManager.currentMusic = null;
      onStateChanged?.call();
    }
  }

  /// 保存偏好设置
  Future<void> savePreferences() async {
    if (!isInitialized) return;

    await storageService.savePlayMode(playerManager.playMode);
    await storageService.saveVolume(playerManager.audioPlayer.volume);
    await storageService.saveRecentList(recentList);
    await storageService.savePlayQueue(playerManager.playQueue);
    await storageService.saveFavorites(favoriteSongs);

    if (playerManager.currentMusic != null) {
      await storageService.saveCurrentMusic(
        playerManager.currentMusic,
        playerManager.currentPosition.inMilliseconds,
      );
    }
  }

  /// 立即保存所有数据
  Future<void> saveAllDataImmediately() async {
    await storageService.saveAllDataImmediately(
      favorites: favoriteSongs,
      playMode: playerManager.playMode,
      volume: playerManager.audioPlayer.volume,
      recentList: recentList,
      playQueue: playerManager.playQueue,
      currentMusic: playerManager.currentMusic,
      playPosition: playerManager.currentPosition.inMilliseconds,
    );
  }

  /// 加载缓存的音乐列表
  Future<void> _loadCachedMusicList() async {
    musicList = await storageService.loadMusicListCache();
  }

  /// 缓存音乐列表
  Future<void> _cacheMusicList() async {
    await storageService.saveMusicListCache(musicList);
  }

  /// 获取音乐列表
  Future<void> fetchMusic({
    bool isRefresh = false,
    bool loadMore = false,
  }) async {
    print('[fetchMusic] 开始 - isRefresh: $isRefresh, loadMore: $loadMore');
    if (isLoadingMore && loadMore) return;

    final page = loadMore ? currentPage + 1 : 1;

    // 设置加载状态
    if (loadMore) {
      isLoadingMore = true;
    } else if (!isRefresh) {
      isLoading = true;
    }
    onStateChanged?.call();
    print('[fetchMusic] 加载状态已设置 - isLoading: $isLoading');

    try {
      print('[fetchMusic] 发起网络请求...');
      final result = await apiService.fetchMusicList(
        search: searchQuery,
        page: page,
        pageSize: pageSize,
      );
      print('[fetchMusic] 网络请求成功');

      final List<dynamic> newData = result['data'] ?? [];
      final pagination = result['pagination'];
      print('[fetchMusic] 获取到 ${newData.length} 首音乐');

      if (loadMore) {
        musicList.addAll(newData);
      } else {
        musicList = newData;
      }

      currentPage = page;
      totalPages = pagination?['total_page'] ?? 1;

      // 搜索时不缓存
      if (searchQuery.isEmpty && !loadMore) {
        _cacheMusicList();
      }

      if (isRefresh) {
        onShowToast?.call('音乐列表已更新', type: ToastType.success);
      }
    } catch (e) {
      print('[fetchMusic] 请求失败: $e');
      if (isRefresh) {
        onShowToast?.call('刷新失败，请检查网络连接', type: ToastType.error);
      } else if (musicList.isEmpty) {
        onShowToast?.call('加载失败，请检查网络连接', type: ToastType.error);
      }
    } finally {
      // 确保无论成功失败都重置加载状态
      isLoading = false;
      isLoadingMore = false;
      print(
        '[fetchMusic] 完成 - isLoading: $isLoading, 音乐数量: ${musicList.length}',
      );
      onStateChanged?.call();
    }
  }

  /// 上传音乐
  Future<void> uploadMusic() async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          onShowToast?.call('需要存储权限才能选择文件', type: ToastType.error);
          return;
        }
      }

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path == null) {
        onShowToast?.call('无效的文件路径', type: ToastType.error);
        return;
      }

      onShowToast?.call('正在上传...', type: ToastType.loading);
      await apiService.uploadMusic(file.path!);
      onShowToast?.call('上传成功', type: ToastType.success);
      await fetchMusic();
    } catch (e) {
      onShowToast?.call('上传失败: $e', type: ToastType.error);
    }
  }

  /// 删除音乐
  Future<void> deleteMusic(dynamic music) async {
    try {
      await apiService.deleteMusic(music['id']);
      onShowToast?.call('删除成功', type: ToastType.success);

      // 如果删除的是当前播放的音乐
      if (playerManager.currentMusic?['id'] == music['id']) {
        playerManager.currentMusic = null;
        await playerManager.audioPlayer.stop();
      }

      // 从各列表中移除
      recentList.removeWhere((m) => m['id'] == music['id']);
      playerManager.playQueue.removeWhere((m) => m['id'] == music['id']);

      await savePreferences();
      await fetchMusic();
      onStateChanged?.call();
    } catch (e) {
      onShowToast?.call('删除失败: $e', type: ToastType.error);
    }
  }

  /// 添加到最近播放
  void addToRecent(dynamic music) {
    recentList.removeWhere((m) => m['id'] == music['id']);
    recentList.insert(0, music);
    if (recentList.length > 5) recentList.removeLast();
    savePreferences();
    onStateChanged?.call();
  }

  /// 从最近播放移除
  void removeFromRecent(dynamic music) {
    recentList.removeWhere((m) => m['id'] == music['id']);
    savePreferences();
    onShowToast?.call('已从最近播放中移除', type: ToastType.info);
    onStateChanged?.call();
  }

  /// 切换收藏
  void toggleFavorite(dynamic music) {
    final musicId = music is String ? music : music['id'];
    if (isFavorite(musicId)) {
      favoriteSongs.removeWhere((m) => m['id'] == musicId);
      onShowToast?.call('已取消收藏', type: ToastType.info);
    } else {
      if (music is! String) {
        favoriteSongs.add(music);
      }
      onShowToast?.call('已添加到喜欢', type: ToastType.success);
    }
    storageService.saveFavorites(favoriteSongs);
    onStateChanged?.call();
  }

  /// 检查是否收藏
  bool isFavorite(String musicId) {
    return favoriteSongs.any((m) => m['id'] == musicId);
  }

  /// 下一首播放
  void playNext(dynamic music) {
    playerManager.playQueue.removeWhere((m) => m['id'] == music['id']);

    int currentIndex = playerManager.playQueue.indexWhere(
      (m) => m['id'] == playerManager.currentMusic?['id'],
    );

    if (currentIndex == -1) {
      playerManager.playQueue.insert(0, music);
    } else {
      playerManager.playQueue.insert(currentIndex + 1, music);
    }

    savePreferences();
    onShowToast?.call('${music['title']} 将在下一首播放', type: ToastType.success);
    onStateChanged?.call();
  }

  /// 添加到队列
  void addToQueue(dynamic music) {
    if (playerManager.playQueue.any((m) => m['id'] == music['id'])) {
      onShowToast?.call('歌曲已在播放队列中', type: ToastType.info);
      return;
    }

    playerManager.playQueue.add(music);
    savePreferences();
    onShowToast?.call('已添加到播放队列', type: ToastType.success);
    onStateChanged?.call();
  }

  /// 设置网络监听
  void _setupConnectivityListener() {
    try {
      connectivitySubscription = Connectivity().onConnectivityChanged.listen((
        results,
      ) {
        final wasOffline = isOffline;
        final isNowOffline = results.contains(ConnectivityResult.none);
        isOffline = isNowOffline;

        if (isNowOffline && !wasOffline) {
          onShowToast?.call('网络已断开，已缓存的歌曲可继续播放', type: ToastType.info);
        } else if (!isNowOffline && wasOffline) {
          onShowToast?.call('网络已恢复', type: ToastType.success);
        }

        onStateChanged?.call();
      });
    } catch (e) {
      print('网络状态监听初始化失败: $e');
    }
  }

  /// 从后台恢复
  Future<void> recoverFromBackground() async {
    if (isRecovering) return;
    isRecovering = true;

    try {
      await Future.delayed(const Duration(milliseconds: 300));

      final session = await AudioSession.instance;
      await session.setActive(true);

      if (playerManager.currentMusic != null) {
        final state = playerManager.audioPlayer.processingState;

        // 只在播放器真正异常（idle 或 loading）时才恢复
        if (state == ProcessingState.idle || state == ProcessingState.loading) {
          await playerManager.reloadCurrentMusic();
        }
        // 其他状态（ready, buffering, completed）说明播放器正常，不需要恢复
      }
    } catch (e) {
      print('后台恢复失败: $e');
    } finally {
      isRecovering = false;
    }
  }

  /// 释放资源
  void dispose() {
    saveProgressTimer?.cancel();
    healthCheckTimer?.cancel();
    connectivitySubscription?.cancel();
    savePreferences();
  }
}
