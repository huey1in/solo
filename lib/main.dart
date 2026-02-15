import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio/just_audio.dart';
// just_audio_background 暂时禁用（模拟器兼容性问题）
// import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:math';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:audio_session/audio_session.dart';
import 'music_player_page.dart'; // 请确保该文件存在并引用
import 'audio_cache_service.dart';

enum PlayMode { sequence, listLoop, singleLoop, shuffle }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // just_audio_background 暂时禁用（模拟器上 _audioHandler late init 会崩溃）
  // 在真机上可取消注释以启用通知栏控制
  // await JustAudioBackground.init(
  //   androidNotificationChannelId: 'com.solo.music.channel.audio',
  //   androidNotificationChannelName: 'Solo Music',
  //   androidNotificationOngoing: true,
  //   androidStopForegroundOnPause: true,
  // );
  // 初始化音频缓存服务
  await AudioCacheService.instance.init();
  runApp(const SoloMusicApp());
}

class SoloMusicApp extends StatelessWidget {
  const SoloMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solo Music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFE8F4F8), // 淡蓝色
        primaryColor: const Color(0xFFFF4444),
        fontFamily: 'PingFang SC', // 适配中文字体
      ),
      home: const MusicDashboard(),
    );
  }
}

class MusicDashboard extends StatefulWidget {
  const MusicDashboard({super.key});

  @override
  State<MusicDashboard> createState() => _MusicDashboardState();
}

class _MusicDashboardState extends State<MusicDashboard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const String baseUrl = "https://solo.yinxh.fun";
  List<dynamic> _musicList = [];
  List<dynamic> _recentList = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  int _totalPages = 1;
  static const int _pageSize = 30;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // 播放队列（当前播放的歌曲列表）
  List<dynamic> _playQueue = [];

  // 底部导航和喜欢列表
  int _currentIndex = 0;
  List<dynamic> _favoriteSongs = [];

  final AudioPlayer _audioPlayer = AudioPlayer();
  dynamic _currentPlayingMusic;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  // bufferedPosition 由 audioPlayer.bufferedPosition 直接读取
  PlayMode _playMode = PlayMode.listLoop;
  late AnimationController _rotationController;
  Timer? _saveProgressTimer; // 定时保存进度的定时器
  Timer? _searchDebounce; // 搜索防抖定时器
  Timer? _healthCheckTimer; // 播放器健康检查定时器
  bool _isInitialized = false; // 标记是否已完成初始化加载，防止未加载完就触发保存
  bool _isOffline = false; // 网络状态
  bool _isRecovering = false; // 是否正在从后台恢复
  StreamSubscription? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
    _scrollController.addListener(_onScroll);
    _rotationController = AnimationController(
      duration: const Duration(seconds: 15),
      vsync: this,
    );

    // 播放监听逻辑
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state.playing);
        _isPlaying ? _rotationController.repeat() : _rotationController.stop();
      }
    });
    _audioPlayer.positionStream.listen((p) {
      if (mounted) {
        setState(() => _currentPosition = p);
        // 预加载下一首：当前歌曲播放到 80% 时后台缓存下一首
        _maybePreloadNext();
      }
    });
    _audioPlayer.durationStream.listen(
      (d) => setState(() => _totalDuration = d ?? Duration.zero),
    );
    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _handleNext();
    });

    // 配置音频会话（音频焦点处理：来电暂停、导航降低音量等）
    try {
      _configureAudioSession();
    } catch (e) {
      print('配置音频会话失败: $e');
    }

    // 网络状态监听
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
        final wasOffline = _isOffline;
        final isNowOffline = results.contains(ConnectivityResult.none);
        if (mounted) {
          setState(() => _isOffline = isNowOffline);
          if (isNowOffline && !wasOffline) {
            _showToast('网络已断开，已缓存的歌曲可继续播放');
          } else if (!isNowOffline && wasOffline) {
            _showToast('网络已恢复');
          }
        }
      });
    } catch (e) {
      print('网络状态监听初始化失败: $e');
    }

    // 启动定时保存，每5秒保存一次播放进度
    _saveProgressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isInitialized && _currentPlayingMusic != null) {
        _savePreferences();
      }
    });

    // 启动播放器健康检查，每30秒检查一次
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkPlayerHealth();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveProgressTimer?.cancel();
    _healthCheckTimer?.cancel();
    _searchDebounce?.cancel();
    _connectivitySubscription?.cancel();
    _scrollController.dispose();
    _savePreferences(); // 最后保存一次
    _audioPlayer.dispose();
    _rotationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // iOS 上应用进入后台时立即保存数据，防止系统杀死应用后数据丢失
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // 使用 unawaited 但确保 SharedPreferences 立即写入
      _saveAllDataImmediately();
    }

    // 从后台恢复时重新初始化播放器
    if (state == AppLifecycleState.resumed) {
      _recoverFromBackground();
    }
  }

  // iOS 上需要立即保存所有数据，防止应用被系统杀死
  Future<void> _saveAllDataImmediately() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // 使用同一个 prefs 实例一次性保存所有关键数据
      await Future.wait([
        prefs.setString('favorites', json.encode(_favoriteSongs)),
        prefs.setInt('playMode', _playMode.index),
        prefs.setDouble('volume', _audioPlayer.volume),
        prefs.setString('recentList', json.encode(_recentList)),
        prefs.setString('playQueue', json.encode(_playQueue)),
        if (_currentPlayingMusic != null) ...[
          prefs.setString('currentMusic', json.encode(_currentPlayingMusic)),
          prefs.setInt('playPosition', _currentPosition.inMilliseconds),
        ],
      ]);
    } catch (e) {
      print('紧急保存数据失败: $e');
    }
  }

  // 从后台恢复应用
  Future<void> _recoverFromBackground() async {
    if (_isRecovering) return;
    _isRecovering = true;

    try {
      print('从后台恢复应用');
      await Future.delayed(const Duration(milliseconds: 300));

      // 重新激活音频会话
      final session = await AudioSession.instance;
      await session.setActive(true);

      // 如果有正在播放的歌曲，主动重置播放器状态
      if (_currentPlayingMusic != null) {
        final state = _audioPlayer.processingState;
        print('播放器状态: $state');

        // 无论当前状态如何，都尝试 stop 来重置内部 HTTP 连接状态
        // 这样后续 _playMusic 调用 setAudioSource 时不会因为旧连接失效而失败
        if (state == ProcessingState.idle ||
            state == ProcessingState.loading) {
          await _reloadCurrentMusic();
        } else {
          // 即使状态看起来正常(ready/completed/buffering)，也主动 stop 重置
          // 防止长时间后台挂起导致底层 HTTP client 失效
          try {
            await _audioPlayer.stop();
            await _reloadCurrentMusic();
          } catch (e) {
            print('主动重置播放器失败: $e');
          }
        }
      }
    } catch (e) {
      print('后台恢复失败: $e');
    } finally {
      _isRecovering = false;
    }
  }

  // 重新加载当前音乐
  Future<void> _reloadCurrentMusic() async {
    if (_currentPlayingMusic == null) return;

    try {
      final streamUrl = '$baseUrl/api/music/${_currentPlayingMusic['id']}/stream';
      final wasPlaying = _isPlaying;

      await _audioPlayer.stop();

      if (AudioCacheService.instance.isCached(streamUrl)) {
        await _audioPlayer.setAudioSource(
          AudioSource.file(AudioCacheService.instance.getCacheFilePath(streamUrl)),
          initialPosition: _currentPosition,
        );
      } else {
        await _audioPlayer.setAudioSource(
          LockCachingAudioSource(
            Uri.parse(streamUrl),
            cacheFile: AudioCacheService.instance.getCacheFile(streamUrl),
          ),
          initialPosition: _currentPosition,
        );
      }

      if (wasPlaying) {
        await _audioPlayer.play();
      }

      print('播放器恢复成功');
    } catch (e) {
      print('播放器恢复失败: $e');
    }
  }

  // 检查播放器健康状态
  void _checkPlayerHealth() {
    if (_currentPlayingMusic == null) return;

    try {
      final state = _audioPlayer.processingState;
      final position = _audioPlayer.position;
      final duration = _audioPlayer.duration;

      print('播放器健康检查: state=$state, position=$position, duration=$duration');

      // 如果播放器状态异常且有正在播放的音乐，尝试恢复
      if (state == ProcessingState.idle) {
        if (_isPlaying) {
          print('检测到播放器异常，尝试恢复');
          _reloadCurrentMusic();
        }
      }
    } catch (e) {
      print('播放器健康检查异常: $e');
    }
  }

  // 配置音频会话（音频焦点处理）
  Future<void> _configureAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false,
    ));

    // 监听音频焦点变化
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        // 被打断（来电等）：暂停
        if (_isPlaying) _audioPlayer.pause();
      } else {
        // 打断结束：恢复播放
        if (event.type == AudioInterruptionType.pause) {
          _audioPlayer.play();
        }
      }
    });

    // 监听音频变得嘈杂（如拔出耳机）：暂停
    session.becomingNoisyEventStream.listen((_) {
      if (_isPlaying) _audioPlayer.pause();
    });
  }

  // 预加载下一首（当前歌曲播放到50%时触发完整下载）
  bool _preloadTriggered = false;
  void _maybePreloadNext() {
    if (_preloadTriggered) return;
    if (_totalDuration.inSeconds <= 0) return;
    final progress = _currentPosition.inMilliseconds / _totalDuration.inMilliseconds;
    if (progress < 0.5) return;

    _preloadTriggered = true;
    final nextMusic = _getNextMusic();
    if (nextMusic == null) return;

    final nextUrl = '$baseUrl/api/music/${nextMusic['id']}/stream';
    // 完整下载下一首到本地缓存（优先级最高，不影响当前播放）
    AudioCacheService.instance.preloadUrl(nextUrl);
  }

  // 获取下一首音乐（不实际播放）
  dynamic _getNextMusic() {
    if (_playQueue.isEmpty) return null;
    if (_playMode == PlayMode.shuffle) {
      return _playQueue[Random().nextInt(_playQueue.length)];
    }
    int index = _playQueue.indexWhere(
      (m) => m['id'] == _currentPlayingMusic?['id'],
    );
    if (index == -1) return _playQueue[0];
    int next = index + 1;
    if (next >= _playQueue.length) {
      if (_playMode == PlayMode.sequence) return null;
      next = 0;
    }
    return _playQueue[next];
  }

  // --- 逻辑函数 ---
  // 初始化：加载设置和数据
  Future<void> _initApp() async {
    await _loadPreferences();
    _isInitialized = true; // 标记已完成加载，允许保存
    // 先加载本地缓存（快速显示）
    await _loadCachedMusicList();
    if (_musicList.isNotEmpty) {
      setState(() => _isLoading = false);
    }
    // 无论是否有缓存，都从服务器获取最新数据
    await _fetchMusic();
  }

  // 从本地缓存加载音乐列表
  Future<void> _loadCachedMusicList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cachedMusicList');
      if (cachedJson != null) {
        final decoded = json.decode(cachedJson) as List;
        setState(() {
          _musicList = decoded;
        });
      }
    } catch (e) {
      print('加载缓存音乐列表失败: $e');
    }
  }

  // 保存音乐列表到本地缓存
  Future<void> _cacheMusicList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cachedMusicList', json.encode(_musicList));
    } catch (e) {
      print('缓存音乐列表失败: $e');
    }
  }

  // 加载保存的设置
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    // 每个部分单独 try-catch，防止一个失败影响其他
    try {
      final playModeIndex = prefs.getInt('playMode') ?? PlayMode.listLoop.index;
      setState(() {
        _playMode = PlayMode.values[playModeIndex];
      });
    } catch (e) {
      print('加载播放模式失败: $e');
    }

    try {
      final savedVolume = prefs.getDouble('volume') ?? 1.0;
      _audioPlayer.setVolume(savedVolume);
    } catch (e) {
      print('加载音量失败: $e');
    }

    try {
      final recentJson = prefs.getString('recentList');
      if (recentJson != null) {
        final decoded = json.decode(recentJson) as List;
        setState(() {
          _recentList = decoded;
        });
      }
    } catch (e) {
      print('加载最近播放失败: $e');
    }

    try {
      final queueJson = prefs.getString('playQueue');
      if (queueJson != null) {
        final decoded = json.decode(queueJson) as List;
        setState(() {
          _playQueue = decoded;
        });
      }
    } catch (e) {
      print('加载播放队列失败: $e');
    }

    try {
      final favoritesJson = prefs.getString('favorites');
      if (favoritesJson != null) {
        final decoded = json.decode(favoritesJson) as List;
        setState(() {
          // 兼容旧版（纯ID列表）和新版（完整歌曲对象列表）
          if (decoded.isNotEmpty && decoded.first is String) {
            // 旧版ID列表，清空（无法恢复完整数据）
            _favoriteSongs = [];
          } else {
            _favoriteSongs = decoded;
          }
        });
      }
    } catch (e) {
      print('加载喜欢列表失败: $e');
    }

    try {
      final currentMusicJson = prefs.getString('currentMusic');
      if (currentMusicJson != null) {
        final music = json.decode(currentMusicJson);
        final savedPosition = prefs.getInt('playPosition') ?? 0;

        setState(() {
          _currentPlayingMusic = music;
        });

        try {
          final streamUrl = '$baseUrl/api/music/${music['id']}/stream';
          if (AudioCacheService.instance.isCached(streamUrl)) {
            await _audioPlayer.setAudioSource(
              AudioSource.file(AudioCacheService.instance.getCacheFilePath(streamUrl)),
            );
          } else {
            await _audioPlayer.setAudioSource(
              LockCachingAudioSource(
                Uri.parse(streamUrl),
                cacheFile: AudioCacheService.instance.getCacheFile(streamUrl),
              ),
            );
          }
          await _audioPlayer.seek(Duration(milliseconds: savedPosition));
        } catch (e) {
          print('恢复播放失败: $e');
        }
      }
    } catch (e) {
      print('加载当前播放音乐失败: $e');
    }
  }

  // 单独保存喜欢列表（确保收藏保存不受其他数据影响）
  Future<void> _saveFavorites() async {
    if (!_isInitialized) return; // 未初始化完成不保存，防止空数据覆盖
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('favorites', json.encode(_favoriteSongs));
    } catch (e) {
      print('保存喜欢列表失败: $e');
    }
  }

  // 保存设置
  Future<void> _savePreferences() async {
    if (!_isInitialized) return; // 未初始化完成不保存，防止空数据覆盖
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('playMode', _playMode.index);
      await prefs.setDouble('volume', _audioPlayer.volume);
    } catch (e) {
      print('保存基础设置失败: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('recentList', json.encode(_recentList));
    } catch (e) {
      print('保存最近播放失败: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playQueue', json.encode(_playQueue));
    } catch (e) {
      print('保存播放队列失败: $e');
    }

    // 保存喜欢列表
    await _saveFavorites();

    // 保存当前播放音乐和进度
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_currentPlayingMusic != null) {
        await prefs.setString(
          'currentMusic',
          json.encode(_currentPlayingMusic),
        );
        await prefs.setInt('playPosition', _currentPosition.inMilliseconds);
      } else {
        await prefs.remove('currentMusic');
        await prefs.remove('playPosition');
      }
    } catch (e) {
      print('保存播放进度失败: $e');
    }
  }

  void _addToRecent(dynamic music) {
    setState(() {
      _recentList.removeWhere((m) => m['id'] == music['id']);
      _recentList.insert(0, music);
      if (_recentList.length > 5) _recentList.removeLast(); // 最多5首
    });
    _savePreferences(); // 保存最近播放列表
  }

  void _removeFromRecent(BuildContext context, dynamic music) {
    _showCustomDialog(
      context: context,
      title: '移除确认',
      content: '确定要从最近播放中移除「${music['title']}」吗？',
      confirmText: '移除',
      isDestructive: true,
      onConfirm: () {
        setState(() {
          _recentList.removeWhere((m) => m['id'] == music['id']);
        });
        _savePreferences();
        _showToast('已从最近播放中移除');
      },
    );
  }

  Future<void> _uploadMusic() async {
    try {
      // iOS 不需要 storage 权限，仅 Android 需要
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          _showToast('需要存储权限才能选择文件');
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
        _showToast('无效的文件路径');
        return;
      }

      _showToast('正在上传...');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/music/upload'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', file.path!));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        _showToast('上传成功');
        _fetchMusic();
      } else {
        final error = json.decode(response.body)['error'] ?? '上传失败';
        _showToast(error);
      }
    } catch (e) {
      _showToast('上传失败: $e');
    }
  }

  Future<void> _fetchMusic({bool isRefresh = false, bool loadMore = false}) async {
    if (_isLoadingMore && loadMore) return; // 防止重复加载
    final page = loadMore ? _currentPage + 1 : 1;

    if (loadMore) setState(() => _isLoadingMore = true);

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/music?search=$_searchQuery&page=$page&page_size=$_pageSize'),
      );
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final List<dynamic> newData = body['data'] ?? [];
        final pagination = body['pagination'];
        setState(() {
          if (loadMore) {
            _musicList.addAll(newData);
          } else {
            _musicList = newData;
          }
          _currentPage = page;
          _totalPages = pagination?['total_page'] ?? 1;
          _isLoading = false;
          _isLoadingMore = false;
        });
        // 搜索时不缓存，只缓存第一页全量列表
        if (_searchQuery.isEmpty && !loadMore) {
          _cacheMusicList();
        }
        if (isRefresh) {
          _showToast('音乐列表已更新');
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
      if (isRefresh) {
        _showToast('刷新失败，请检查网络连接');
      }
    }
  }

  // 滚动监听：接近底部时加载更多
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  // 加载下一页
  void _loadMore() {
    if (_isLoadingMore || _currentPage >= _totalPages) return;
    _fetchMusic(loadMore: true);
  }

  // 下拉刷新回调：重置分页
  Future<void> _onRefresh() async {
    await _fetchMusic(isRefresh: true);
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _playMusic(dynamic music, {List<dynamic>? queue}) async {
    if (_currentPlayingMusic?['id'] == music['id']) {
      _isPlaying ? await _audioPlayer.pause() : await _audioPlayer.play();
      return;
    }

    // 如果提供了新的队列，则更新播放队列
    if (queue != null) {
      setState(() {
        _playQueue = List.from(queue);
      });
    }

    // 确保当前歌曲在播放队列中
    if (!_playQueue.any((m) => m['id'] == music['id'])) {
      setState(() {
        _playQueue.add(music);
      });
    }

    _addToRecent(music);
    setState(() => _currentPlayingMusic = music);

    try {
      _preloadTriggered = false; // 重置预加载标志
      AudioCacheService.instance.cancelPreload(); // 取消旧的预加载，释放带宽给当前歌曲
      await _setAudioSource(music);
      _audioPlayer.play();
      _savePreferences(); // 保存当前播放音乐
    } catch (e) {
      print('播放失败(首次): $e');
      // 首次失败：可能是后台挂起导致播放器状态异常，重置后重试一次
      try {
        await _audioPlayer.stop();
        await Future.delayed(const Duration(milliseconds: 200));
        await _setAudioSource(music);
        _audioPlayer.play();
        _savePreferences();
        print('重试播放成功');
      } catch (retryError) {
        print('重试播放也失败: $retryError');
        _showToast('歌曲「${music['title']}」无法播放，已跳过');

        // 从喜欢列表中移除（如果存在）
        if (_isFavorite(music['id'])) {
          setState(() {
            _favoriteSongs.removeWhere((m) => m['id'] == music['id']);
          });
          _saveFavorites();
        }

        // 从播放队列中移除
        setState(() {
          _playQueue.removeWhere((m) => m['id'] == music['id']);
        });

        // 播放下一首
        _handleNext();
      }
    }
  }

  // 设置音频源（提取公共逻辑，避免重复代码）
  Future<void> _setAudioSource(dynamic music) async {
    final streamUrl = '$baseUrl/api/music/${music['id']}/stream';
    if (AudioCacheService.instance.isCached(streamUrl)) {
      await _audioPlayer.setAudioSource(
        AudioSource.file(AudioCacheService.instance.getCacheFilePath(streamUrl)),
      );
    } else {
      await _audioPlayer.setAudioSource(
        LockCachingAudioSource(
          Uri.parse(streamUrl),
          cacheFile: AudioCacheService.instance.getCacheFile(streamUrl),
        ),
      );
    }
  }

  void _handleNext() {
    if (_playQueue.isEmpty) return;

    if (_playMode == PlayMode.shuffle) {
      final random = Random();
      int next = random.nextInt(_playQueue.length);
      _playMusic(_playQueue[next]);
      return;
    }

    int index = _playQueue.indexWhere(
      (m) => m['id'] == _currentPlayingMusic?['id'],
    );

    if (index == -1) {
      _playMusic(_playQueue[0]);
      return;
    }

    if (_playMode == PlayMode.singleLoop) {
      // 单曲循环：重新播放当前歌曲
      _audioPlayer.seek(Duration.zero);
      _audioPlayer.play();
      return;
    }

    int next = index + 1;
    if (next >= _playQueue.length) {
      if (_playMode == PlayMode.sequence) {
        // 顺序播放到最后一首停止
        _audioPlayer.stop();
        return;
      }
      next = 0; // 列表循环
    }
    _playMusic(_playQueue[next]);
  }

  void _handlePrevious() {
    if (_playQueue.isEmpty) return;
    int index = _playQueue.indexWhere(
      (m) => m['id'] == _currentPlayingMusic?['id'],
    );
    if (index == -1) {
      _playMusic(_playQueue[0]);
      return;
    }
    int previous = (index - 1 + _playQueue.length) % _playQueue.length;
    _playMusic(_playQueue[previous]);
  }

  // 下一首播放（插入到当前歌曲之后）
  void _playNext(dynamic music) {
    // 先移除队列中已存在的该歌曲
    _playQueue.removeWhere((m) => m['id'] == music['id']);

    int currentIndex = _playQueue.indexWhere(
      (m) => m['id'] == _currentPlayingMusic?['id'],
    );

    setState(() {
      if (currentIndex == -1) {
        _playQueue.insert(0, music);
      } else {
        _playQueue.insert(currentIndex + 1, music);
      }
    });
    _savePreferences();
    _showToast('「${music['title']}」将在下一首播放');
  }

  // 添加到播放队列末尾
  void _addToQueue(dynamic music) {
    if (_playQueue.any((m) => m['id'] == music['id'])) {
      _showToast('歌曲已在播放队列中');
      return;
    }

    setState(() {
      _playQueue.add(music);
    });
    _savePreferences();
    _showToast('已添加到播放队列');
  }

  void _togglePlayMode() {
    setState(() {
      switch (_playMode) {
        case PlayMode.listLoop:
          _playMode = PlayMode.singleLoop;
          break;
        case PlayMode.singleLoop:
          _playMode = PlayMode.shuffle;
          break;
        case PlayMode.shuffle:
          _playMode = PlayMode.sequence;
          break;
        case PlayMode.sequence:
          _playMode = PlayMode.listLoop;
          break;
      }
    });
    _savePreferences(); // 保存播放模式
  }

  void _onVolumeChanged() {
    _savePreferences(); // 保存音量设置
  }

  void _showMusicMenu(BuildContext context, dynamic music) {
    final isFavorite = _isFavorite(music['id']);

    _showCustomBottomSheet(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMenuOption(
            icon: isFavorite ? Icons.favorite : Icons.favorite_border,
            title: isFavorite ? '取消收藏' : '添加到喜欢',
            onTap: () {
              Navigator.pop(context);
              _toggleFavorite(music);
            },
          ),
          Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          _buildMenuOption(
            icon: Icons.skip_next_outlined,
            title: '下一首播放',
            onTap: () {
              Navigator.pop(context);
              _playNext(music);
            },
          ),
          Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          _buildMenuOption(
            icon: Icons.playlist_add,
            title: '添加到播放队列',
            onTap: () {
              Navigator.pop(context);
              _addToQueue(music);
            },
          ),
          Divider(height: 1, color: Colors.grey.withOpacity(0.2)),
          _buildMenuOption(
            icon: Icons.delete_outline,
            title: '删除',
            onTap: () {
              Navigator.pop(context);
              _deleteMusicConfirm(context, music);
            },
          ),
        ],
      ),
    );
  }

  void _deleteMusicConfirm(BuildContext context, dynamic music) {
    _showCustomDialog(
      context: context,
      title: '确认删除',
      content: Text('确定要删除「${music['title']}」吗？'),
      confirmText: '删除',
      isDestructive: true,
      onConfirm: () => _deleteMusic(music),
    );
  }

  Future<void> _deleteMusic(dynamic music) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/music/${music['id']}'),
      );

      if (response.statusCode == 200) {
        _showToast('删除成功');

        // 如果删除的是当前播放的音乐，停止播放
        if (_currentPlayingMusic?['id'] == music['id']) {
          setState(() => _currentPlayingMusic = null);
          await _audioPlayer.stop();
        }

        // 从最近播放列表中移除
        setState(() {
          _recentList.removeWhere((m) => m['id'] == music['id']);
        });

        // 从播放队列中移除该歌曲
        setState(() {
          _playQueue.removeWhere((m) => m['id'] == music['id']);
        });

        _savePreferences();

        // 刷新列表
        _fetchMusic();
      } else {
        final error = json.decode(response.body)['error'] ?? '删除失败';
        _showToast(error);
      }
    } catch (e) {
      _showToast('删除失败: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes)}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  // --- 喜欢列表管理 ---
  Future<void> _toggleFavorite(dynamic music) async {
    final musicId = music is String ? music : music['id'];
    setState(() {
      if (_isFavorite(musicId)) {
        _favoriteSongs.removeWhere((m) => m['id'] == musicId);
        _showToast('已取消收藏');
      } else {
        if (music is! String) {
          _favoriteSongs.add(music);
        }
        _showToast('已添加到喜欢');
      }
    });
    await _saveFavorites();
  }

  bool _isFavorite(String musicId) {
    return _favoriteSongs.any((m) => m['id'] == musicId);
  }

  List<dynamic> _getFavoriteSongs() {
    return List.from(_favoriteSongs);
  }

  // 自定义弹窗
  void _showCustomDialog({
    required BuildContext context,
    required String title,
    required dynamic content,
    String? confirmText,
    bool showCancel = true,
    bool isDestructive = false,
    VoidCallback? onConfirm,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (content is Widget)
                      content
                    else
                      Text(
                        content.toString(),
                        style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (showCancel) ...[
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                            child: Text(
                              '取消',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onConfirm?.call();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDestructive
                                ? Colors.red
                                : const Color(0xFFFF4444),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            confirmText ?? '确定',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // 自定义底部菜单
  void _showCustomBottomSheet({
    required BuildContext context,
    required Widget child,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 10),
            child,
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // 菜单选项组件
  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Colors.black87, size: 24),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI 构建 ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              _buildHomePage(),
              _buildFavoritesPage(),
            ],
          ),
          if (_currentPlayingMusic != null) _buildGlassBottomPlayer(),
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

  Widget _buildHomePage() {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: const Color(0xFFFF4444),
      backgroundColor: Colors.white,
      displacement: 60,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildSearchBar()),
          if (!_isLoading && _recentList.isNotEmpty) ...[
            SliverToBoxAdapter(child: _buildSectionTitle("最近播放")),
            _buildRecentGrid(),
          ],
          SliverToBoxAdapter(child: _buildSectionTitle("全部音乐")),
          if (_isLoading)
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
          else if (_musicList.isEmpty)
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
            _buildMusicList(),
            if (_isLoadingMore)
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
            if (!_isLoadingMore && _currentPage >= _totalPages && _musicList.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      '— 已加载全部 ${_musicList.length} 首 —',
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

  Widget _buildFavoritesPage() {
    final favoriteSongs = _getFavoriteSongs();

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
              return _buildFavoriteMusicCard(music);
            }, childCount: favoriteSongs.length),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  Widget _buildFavoriteMusicCard(dynamic music) {
    final isPlaying = _currentPlayingMusic?['id'] == music['id'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: () => _playMusic(music, queue: _getFavoriteSongs()),
        leading: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: music['has_cover'] == true
                ? CachedNetworkImage(
                    imageUrl: '$baseUrl/api/music/${music['id']}/cover',
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: 50,
                      height: 50,
                      color: Colors.grey[200],
                      child: const Icon(
                        Icons.music_note,
                        color: Colors.grey,
                        size: 24,
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 50,
                      height: 50,
                      color: Colors.grey[300],
                      child: const Icon(Icons.music_note, color: Colors.grey),
                    ),
                  )
                : Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.music_note, color: Colors.grey, size: 24),
                  ),
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
          onPressed: () => _toggleFavorite(music),
        ),
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
            children: [
              const Text(
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() => _searchQuery = value);
            // 搜索防抖：300ms内无新输入才发起请求
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 300), () {
              _fetchMusic();
            });
          },
          decoration: InputDecoration(
            hintText: '搜索歌曲...',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            isCollapsed: true,
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                      _fetchMusic();
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

  // 美化后的横向卡片
  Widget _buildRecentGrid() {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 190,
        child: ListView.builder(
          padding: const EdgeInsets.only(left: 20),
          scrollDirection: Axis.horizontal,
          itemCount: _recentList.length,
          itemBuilder: (context, index) {
            final music = _recentList[index];
            return GestureDetector(
              onTap: () => _playMusic(music),
              onLongPress: () => _removeFromRecent(context, music),
              child: Container(
                width: 130,
                margin: const EdgeInsets.only(right: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCover(music, size: 130, radius: 20, showHero: true, useThumbnail: true),
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

  Widget _buildMusicList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final music = _musicList[index];
        bool isCurr = _currentPlayingMusic?['id'] == music['id'];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 5),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            leading: _buildCover(
              music,
              size: 50,
              radius: 10,
              showHero: !isCurr,
              showAnimation: isCurr && _isPlaying,
              useThumbnail: true, // 列表使用缩略图
            ),
            title: Text(
              music['title'] ?? '',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isCurr ? Colors.red : Colors.black,
              ),
            ),
            subtitle: Text(music['artist'] ?? ''),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showMusicMenu(context, music),
            ),
            onTap: () => _playMusic(music, queue: _musicList),
          ),
        );
      }, childCount: _musicList.length),
    );
  }

  // 通用封面组件（支持 Hero 动画）
  Widget _buildCover(
    dynamic music, {
    required double size,
    required double radius,
    bool showHero = false,
    bool showAnimation = false, // 是否显示播放动画
    bool useThumbnail = false, // 列表中使用缩略图
  }) {
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
              child: Icon(Icons.music_note, color: Colors.grey, size: size * 0.4),
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
              color: Colors.black.withOpacity(0.3),
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

  // 上拉面板打开播放器页面
  void _openPlayerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 全屏
      backgroundColor: Colors.transparent,
      enableDrag: true, // 下拉收起
      builder: (context) => MusicPlayerPage(
        getCurrentMusic: () => _currentPlayingMusic,
        audioPlayer: _audioPlayer,
        isPlaying: _isPlaying,
        currentPosition: _currentPosition,
        totalDuration: _totalDuration,
        onPlayPause: () => _playMusic(_currentPlayingMusic),
        onNext: _handleNext,
        onPrevious: _handlePrevious,
        playMode: _playMode,
        onTogglePlayMode: _togglePlayMode,
        onVolumeChanged: _onVolumeChanged,
        isFavorite: _isFavorite(_currentPlayingMusic['id']),
        onToggleFavorite: () {
          setState(() {
            _toggleFavorite(_currentPlayingMusic);
          });
        },
        checkIsFavorite: _isFavorite,
        playQueue: _playQueue,
        onPlayFromQueue: (music) => _playMusic(music),
        baseUrl: baseUrl,
        onClose: () {
          setState(() => _currentPlayingMusic = null);
          _savePreferences();
        },
      ),
    );
  }

  // iOS 26 Liquid Glass 拟态玻璃浮动底栏
  Widget _buildGlassBottomPlayer() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 10,
      left: 15,
      right: 15,
      child: GestureDetector(
        onTap: () => _openPlayerSheet(),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              // 主阴影：玻璃悬浮感
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: 0,
              ),
              // 光晕：模拟光线穿过玻璃的漫射
              BoxShadow(
                color: Colors.blue.withOpacity(0.04),
                blurRadius: 30,
                offset: const Offset(0, 4),
                spreadRadius: -2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.22),
                      Colors.white.withOpacity(0.10),
                    ],
                  ),
                  border: Border.all(
                    width: 1.0,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                child: Stack(
                  children: [
                    // 顶部高光（最亮的折射边缘）
                    Positioned(
                      top: 0,
                      left: 10,
                      right: 10,
                      child: Container(
                        height: 1.0,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.0),
                              Colors.white.withOpacity(0.95),
                              Colors.white,
                              Colors.white.withOpacity(0.95),
                              Colors.white.withOpacity(0.0),
                            ],
                            stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // 底部反光线条
                    Positioned(
                      bottom: 0,
                      left: 30,
                      right: 30,
                      child: Container(
                        height: 0.5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.0),
                              Colors.white.withOpacity(0.5),
                              Colors.white.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 左侧边缘折射光
                    Positioned(
                      top: 10,
                      bottom: 10,
                      left: 0,
                      child: Container(
                        width: 0.5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.0),
                              Colors.white.withOpacity(0.7),
                              Colors.white.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 右侧边缘折射光
                    Positioned(
                      top: 10,
                      bottom: 10,
                      right: 0,
                      child: Container(
                        width: 0.5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.0),
                              Colors.white.withOpacity(0.4),
                              Colors.white.withOpacity(0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 彩虹色散层（模拟光线穿过玻璃的棱镜效果）
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: const Alignment(-1.2, -0.8),
                            end: const Alignment(1.2, 0.8),
                            colors: [
                              const Color(0x12FF6EC7), // 粉色折射
                              const Color(0x08FFD93D), // 黄色
                              Colors.transparent,
                              const Color(0x0870D6FF), // 蓝色折射
                              const Color(0x10A78BFA), // 紫色折射
                            ],
                            stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // 内容区
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          // 封面（带玻璃阴影）
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: RotationTransition(
                              turns: _rotationController,
                              child: _buildCover(
                                _currentPlayingMusic,
                                size: 48,
                                radius: 24,
                                showHero: true,
                                useThumbnail: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentPlayingMusic['title'] ?? '',
                                  style: TextStyle(
                                    color: Colors.black.withOpacity(0.85),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _currentPlayingMusic['artist'] ?? '',
                                  style: TextStyle(
                                    color: Colors.black.withOpacity(0.45),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // 播放按钮（内嵌玻璃按钮）
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withOpacity(0.06),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.6),
                                width: 0.5,
                              ),
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.black.withOpacity(0.7),
                                size: 24,
                              ),
                              onPressed: () => _playMusic(_currentPlayingMusic),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 动态律动图标 (保持不变)
class AnimatedEqualizer extends StatefulWidget {
  final bool isOverlay; // 是否作为遮罩层
  final Color barColor; // 自定义颜色

  const AnimatedEqualizer({
    super.key,
    this.isOverlay = false,
    this.barColor = Colors.red,
  });

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        duration: Duration(milliseconds: 400 + (i * 150)),
        vsync: this,
      )..repeat(reverse: true),
    );
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 遮罩层样式：更大、白色
    if (widget.isOverlay) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          4,
          (i) => AnimatedBuilder(
            animation: _controllers[i % 3],
            builder: (c, w) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 4,
              height: 8 + (20 * _controllers[i % 3].value),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
    }

    // 默认样式
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
          animation: _controllers[i],
          builder: (c, w) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            width: 3,
            height: 4 + (14 * _controllers[i].value),
            color: widget.barColor,
          ),
        ),
      ),
    );
  }
}
