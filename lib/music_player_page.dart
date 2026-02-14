import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'main.dart'; // 确保导入 PlayMode 枚举

class MusicPlayerPage extends StatefulWidget {
  final dynamic Function() getCurrentMusic;
  final AudioPlayer audioPlayer;
  final bool isPlaying;
  final Duration currentPosition;
  final Duration totalDuration;
  final VoidCallback onPlayPause;
  final VoidCallback onClose;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final PlayMode playMode;
  final VoidCallback onTogglePlayMode;
  final VoidCallback? onVolumeChanged;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final bool Function(String musicId) checkIsFavorite;
  final List<dynamic> playQueue;
  final void Function(dynamic music) onPlayFromQueue;
  final String baseUrl;

  const MusicPlayerPage({
    super.key,
    required this.getCurrentMusic,
    required this.audioPlayer,
    required this.isPlaying,
    required this.currentPosition,
    required this.totalDuration,
    required this.onPlayPause,
    required this.onClose,
    required this.onNext,
    required this.onPrevious,
    required this.playMode,
    required this.onTogglePlayMode,
    this.onVolumeChanged,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.checkIsFavorite,
    required this.playQueue,
    required this.onPlayFromQueue,
    required this.baseUrl,
  });

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage>
    with TickerProviderStateMixin {
  late bool _isPlaying;
  late Duration _currentPosition;
  late Duration _totalDuration;
  PlayMode? _playMode;
  dynamic _currentMusic;
  double _volume = 1.0;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _isPlaying = widget.isPlaying;
    _currentPosition = widget.currentPosition;
    _totalDuration = widget.totalDuration;
    _playMode = widget.playMode;
    _currentMusic = widget.getCurrentMusic();
    _volume = widget.audioPlayer.volume;
    _isFavorite = widget.isFavorite;

    // 监听状态同步
    widget.audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });

    widget.audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
          final newMusic = widget.getCurrentMusic();
          if (newMusic != null &&
              _currentMusic != null &&
              newMusic['id'] != _currentMusic['id']) {
            _currentMusic = newMusic;
            // 当歌曲切换时，更新喜欢状态
            _isFavorite = widget.checkIsFavorite(newMusic['id']);
          }
        });
      }
    });

    widget.audioPlayer.durationStream.listen((duration) {
      if (mounted) setState(() => _totalDuration = duration ?? Duration.zero);
    });
  }

  @override
  void didUpdateWidget(MusicPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFavorite != oldWidget.isFavorite) {
      setState(() {
        _isFavorite = widget.isFavorite;
      });
    }
  }

  void _togglePlayMode() {
    setState(() {
      final currentMode = _playMode ?? PlayMode.listLoop;
      switch (currentMode) {
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
    widget.onTogglePlayMode();
  }

  void _handleNext() {
    widget.onNext();
    // 延迟一点更新，等待歌曲切换完成
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        final newMusic = widget.getCurrentMusic();
        if (newMusic != null) {
          setState(() {
            _currentMusic = newMusic;
            _isFavorite = widget.checkIsFavorite(newMusic['id']);
          });
        }
      }
    });
  }

  void _handlePrevious() {
    widget.onPrevious();
    // 延迟一点更新，等待歌曲切换完成
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        final newMusic = widget.getCurrentMusic();
        if (newMusic != null) {
          setState(() {
            _currentMusic = newMusic;
            _isFavorite = widget.checkIsFavorite(newMusic['id']);
          });
        }
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    final musicId = _currentMusic?['id'];
    final coverUrl = '${widget.baseUrl}/api/music/$musicId/cover';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 沉浸式模糊背景
          _buildBlurredBackground(coverUrl),

          // 2. 黑色渐变层（增强文字可读性）
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.3),
                  Colors.black.withOpacity(0.5),
                  Colors.black.withOpacity(0.8),
                ],
              ),
            ),
          ),

          // 3. 内容层
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const Spacer(),

                // Hero 封面图
                _buildHeroCover(coverUrl, musicId),

                const Spacer(),
                _buildSongInfo(),
                _buildProgressBar(),
                _buildMainControls(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlurredBackground(String url) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
        child: Container(color: Colors.black.withOpacity(0.2)),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(
              Icons.keyboard_arrow_down,
              color: Colors.white,
              size: 32,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          Column(
            children: [
              Text(
                '正在播放',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _currentMusic?['title'] ?? '未知歌曲',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            onPressed: _showPlayQueue,
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCover(String url, String? id) {
    return Center(
      child: Hero(
        tag: 'cover_$id', // 与首页 Tag 保持一致
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.width * 0.8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey[900],
                child: const CircularProgressIndicator(
                  color: Colors.white38,
                  strokeWidth: 2,
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSongInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentMusic?['title'] ?? 'Unknown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  _currentMusic?['artist'] ?? 'Unknown Artist',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 18,
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.red : Colors.white,
              size: 28,
            ),
            onPressed: () {
              setState(() {
                _isFavorite = !_isFavorite;
              });
              widget.onToggleFavorite();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 10),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withOpacity(0.2),
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: _totalDuration.inSeconds > 0
                  ? _currentPosition.inSeconds.toDouble()
                  : 0,
              max: _totalDuration.inSeconds > 0
                  ? _totalDuration.inSeconds.toDouble()
                  : 1,
              onChanged: (value) =>
                  widget.audioPlayer.seek(Duration(seconds: value.toInt())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_currentPosition),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
                Text(
                  _formatDuration(_totalDuration),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(
              _getPlayModeIcon(),
              color: Colors.white.withOpacity(0.8),
              size: 28,
            ),
            onPressed: _togglePlayMode,
          ),
          IconButton(
            icon: const Icon(
              Icons.skip_previous_rounded,
              color: Colors.white,
              size: 45,
            ),
            onPressed: _handlePrevious,
          ),
          GestureDetector(
            onTap: widget.onPlayPause,
            child: Container(
              height: 80,
              width: 80,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.black,
                size: 50,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.skip_next_rounded,
              color: Colors.white,
              size: 45,
            ),
            onPressed: _handleNext,
          ),
          IconButton(
            icon: Icon(
              Icons.volume_up_outlined,
              color: Colors.white.withOpacity(0.8),
              size: 28,
            ),
            onPressed: _showVolumeDialog,
          ),
        ],
      ),
    );
  }

  void _showVolumeDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.grey[900]?.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '音量调节',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  const Icon(Icons.volume_down, color: Colors.white60),
                  Expanded(
                    child: Slider(
                      value: _volume,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white24,
                      onChanged: (value) {
                        setModalState(() => _volume = value);
                        setState(() => _volume = value);
                        widget.audioPlayer.setVolume(value);
                        widget.onVolumeChanged?.call(); // 保存音量设置
                      },
                    ),
                  ),
                  const Icon(Icons.volume_up, color: Colors.white60),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getPlayModeIcon() {
    switch (_playMode ?? PlayMode.listLoop) {
      case PlayMode.sequence:
        return Icons.playlist_play;
      case PlayMode.listLoop:
        return Icons.repeat;
      case PlayMode.singleLoop:
        return Icons.repeat_one;
      case PlayMode.shuffle:
        return Icons.shuffle;
    }
  }

  void _showPlayQueue() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => GestureDetector(
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
                color: Colors.grey[900]?.withOpacity(0.98),
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
                        Text(
                          '播放队列',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.playQueue.length} 首',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey[800]),
                  Expanded(
                    child: widget.playQueue.isEmpty
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
                            itemCount: widget.playQueue.length,
                            itemBuilder: (context, index) {
                              final music = widget.playQueue[index];
                              final isCurrentPlaying =
                                  _currentMusic?['id'] == music['id'];

                              return ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: CachedNetworkImage(
                                    imageUrl:
                                        '${widget.baseUrl}/api/music/${music['id']}/cover',
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
                                    widget.onPlayFromQueue(music);
                                    Future.delayed(
                                      const Duration(milliseconds: 100),
                                      () {
                                        if (mounted) {
                                          final newMusic = widget
                                              .getCurrentMusic();
                                          if (newMusic != null) {
                                            setState(() {
                                              _currentMusic = newMusic;
                                              _isFavorite = widget
                                                  .checkIsFavorite(
                                                    newMusic['id'],
                                                  );
                                            });
                                          }
                                        }
                                      },
                                    );
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
      ),
    );
  }
}
