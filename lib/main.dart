import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:ui';
import 'dart:math';
import 'dart:async';
import 'dart:io' show Platform;
import 'music_player_page.dart'; // 请确保该文件存在并引用

enum PlayMode { sequence, listLoop, singleLoop, shuffle }

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  static const String _primaryUrl = "https://solo.yinxh.fun";
  static const String _fallbackUrl = "http://38.14.210.31:8001";
  String baseUrl = _primaryUrl;
  List<dynamic> _musicList = [];
  List<dynamic> _recentList = [];
  bool _isLoading = true;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  // 播放队列（当前播放的歌曲列表）
  List<dynamic> _playQueue = [];

  // 底部导航和喜欢列表
  int _currentIndex = 0;
  List<String> _favoriteIds = [];

  final AudioPlayer _audioPlayer = AudioPlayer();
  dynamic _currentPlayingMusic;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  PlayMode _playMode = PlayMode.listLoop;
  late AnimationController _rotationController;
  Timer? _saveProgressTimer; // 定时保存进度的定时器

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
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
    _audioPlayer.positionStream.listen(
      (p) => setState(() => _currentPosition = p),
    );
    _audioPlayer.durationStream.listen(
      (d) => setState(() => _totalDuration = d ?? Duration.zero),
    );
    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _handleNext();
    });

    // 启动定时保存，每5秒保存一次播放进度
    _saveProgressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_currentPlayingMusic != null) {
        _savePreferences();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveProgressTimer?.cancel(); // 取消定时器
    _savePreferences(); // 最后保存一次
    _audioPlayer.dispose();
    _rotationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // iOS 上应用进入后台时保存数据，防止系统杀死应用后数据丢失
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _savePreferences();
    }
  }

  // --- 逻辑函数 ---
  // 初始化：检测服务器可用性后再加载数据
  Future<void> _initApp() async {
    await _checkBaseUrl();
    await _loadPreferences();
    _fetchMusic();
  }

  // 检测主地址是否可用，不可用则回退到备用地址
  Future<void> _checkBaseUrl() async {
    try {
      final response = await http
          .get(Uri.parse('$_primaryUrl/api/music'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        setState(() => baseUrl = _primaryUrl);
        return;
      }
    } catch (_) {}
    // 主地址不可用，切换到备用地址
    setState(() => baseUrl = _fallbackUrl);
    print('主服务器不可用，已切换到备用地址: $_fallbackUrl');
  }

  // 加载保存的设置
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载播放模式
      final playModeIndex = prefs.getInt('playMode') ?? PlayMode.listLoop.index;
      setState(() {
        _playMode = PlayMode.values[playModeIndex];
      });

      // 加载音量
      final savedVolume = prefs.getDouble('volume') ?? 1.0;
      _audioPlayer.setVolume(savedVolume);

      // 加载最近播放列表
      final recentJson = prefs.getString('recentList');
      if (recentJson != null) {
        final decoded = json.decode(recentJson) as List;
        setState(() {
          _recentList = decoded;
        });
      }

      // 加载播放队列
      final queueJson = prefs.getString('playQueue');
      if (queueJson != null) {
        final decoded = json.decode(queueJson) as List;
        setState(() {
          _playQueue = decoded;
        });
      }

      // 加载喜欢列表
      final favoritesJson = prefs.getString('favorites');
      if (favoritesJson != null) {
        final decoded = json.decode(favoritesJson) as List;
        setState(() {
          _favoriteIds = decoded.cast<String>();
        });
      }

      // 加载当前播放音乐
      final currentMusicJson = prefs.getString('currentMusic');
      if (currentMusicJson != null) {
        final music = json.decode(currentMusicJson);
        final savedPosition = prefs.getInt('playPosition') ?? 0;

        setState(() {
          _currentPlayingMusic = music;
        });

        // 恢复播放状态（但不自动播放）
        try {
          await _audioPlayer.setUrl('$baseUrl/api/music/${music['id']}/stream');
          await _audioPlayer.seek(Duration(milliseconds: savedPosition));
          // 不自动播放，等待用户点击
        } catch (e) {
          print('恢复播放失败: $e');
        }
      }
    } catch (e) {
      print('加载设置失败: $e');
    }
  }

  // 单独保存喜欢列表（确保收藏保存不受其他数据影响）
  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('favorites', json.encode(_favoriteIds));
    } catch (e) {
      print('保存喜欢列表失败: $e');
    }
  }

  // 保存设置
  Future<void> _savePreferences() async {
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

  Future<void> _fetchMusic() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/music?search=$_searchQuery'),
      );
      if (response.statusCode == 200) {
        setState(() {
          _musicList = json.decode(response.body)['data'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
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
      await _audioPlayer.setUrl('$baseUrl/api/music/${music['id']}/stream');
      _audioPlayer.play();
      _savePreferences(); // 保存当前播放音乐
    } catch (e) {
      // 如果歌曲无法播放（可能已被删除），跳到下一首
      _showToast('歌曲「${music['title']}」无法播放，已跳过');

      // 从喜欢列表中移除（如果存在）
      if (_favoriteIds.contains(music['id'])) {
        setState(() {
          _favoriteIds.remove(music['id']);
        });
        _savePreferences();
      }

      // 从播放队列中移除
      setState(() {
        _playQueue.removeWhere((m) => m['id'] == music['id']);
      });

      // 播放下一首
      _handleNext();
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
              _toggleFavorite(music['id']);
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
  void _toggleFavorite(String musicId) {
    setState(() {
      if (_favoriteIds.contains(musicId)) {
        _favoriteIds.remove(musicId);
        _showToast('已取消收藏');
      } else {
        _favoriteIds.add(musicId);
        _showToast('已添加到喜欢');
      }
    });
    // 立即单独保存喜欢列表，确保 iOS 上不会因其他数据保存失败而丢失
    _saveFavorites();
  }

  bool _isFavorite(String musicId) {
    return _favoriteIds.contains(musicId);
  }

  List<dynamic> _getFavoriteSongs() {
    final availableSongs = <dynamic>[];

    for (var musicId in _favoriteIds) {
      final music = _musicList.firstWhere(
        (m) => m['id'] == musicId,
        orElse: () => null,
      );
      if (music != null) {
        availableSongs.add(music);
      }
    }

    return availableSongs;
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
          _currentIndex == 0 ? _buildHomePage() : _buildFavoritesPage(),
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
    return CustomScrollView(
      slivers: [
        _buildAppBar(),
        SliverToBoxAdapter(child: _buildSearchBar()),
        if (!_isLoading && _recentList.isNotEmpty) ...[
          SliverToBoxAdapter(child: _buildSectionTitle("最近播放")),
          _buildRecentGrid(),
        ],
        SliverToBoxAdapter(child: _buildSectionTitle("全部音乐")),
        _buildMusicList(),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
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
              child: Image.network(
                '$baseUrl/api/music/${music['id']}/cover',
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 50,
                  height: 50,
                  color: Colors.grey[300],
                  child: const Icon(Icons.music_note, color: Colors.grey),
                ),
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
          onPressed: () => _toggleFavorite(music['id']),
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
            _fetchMusic();
          },
          decoration: InputDecoration(
            hintText: '搜索歌曲...',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: InputBorder.none,
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
                    _buildCover(music, size: 130, radius: 20, showHero: true),
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
              showAnimation: isCurr && _isPlaying, // 显示动画遮罩
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
  }) {
    Widget img = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        '$baseUrl/api/music/${music['id']}/cover',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) => Container(
          color: Colors.grey[200],
          child: const Icon(Icons.music_note),
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

  // 毛玻璃浮动底栏
  Widget _buildGlassBottomPlayer() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 10,
      left: 15,
      right: 15,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
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
                  _toggleFavorite(_currentPlayingMusic['id']);
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
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              height: 70,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: Colors.black.withOpacity(0.7),
              child: Row(
                children: [
                  RotationTransition(
                    turns: _rotationController,
                    child: _buildCover(
                      _currentPlayingMusic,
                      size: 50,
                      radius: 25,
                      showHero: true,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentPlayingMusic['title'] ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                        ),
                        Text(
                          _currentPlayingMusic['artist'] ?? '',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isPlaying ? Icons.pause_circle : Icons.play_circle,
                      color: Colors.white,
                      size: 35,
                    ),
                    onPressed: () => _playMusic(_currentPlayingMusic),
                  ),
                ],
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
