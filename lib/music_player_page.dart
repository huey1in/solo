import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import 'main.dart'; // 确保导入 PlayMode 枚举
import 'lyric_view.dart';

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
  bool _showLyrics = false;

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
    final bool hasCover = _currentMusic?['has_cover'] == true;
    final coverUrl = hasCover ? '${widget.baseUrl}/api/music/$musicId/cover' : '';

    return Container(
      height: MediaQuery.of(context).size.height * 0.95,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 1. 沉浸式模糊背景
          _buildBlurredBackground(coverUrl),

          // 2. 黑色渐变层（增强文字可读性）
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
            top: false,
            child: Column(
              children: [
                // 拖拽手柄
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                _buildTopBar(),
                const Spacer(),

                // 点击封面切换歌词 / 点击歌词切换封面
                GestureDetector(
                  onTap: () => setState(() => _showLyrics = !_showLyrics),
                  child: _showLyrics
                      ? SizedBox(
                          width: MediaQuery.of(context).size.width * 0.85,
                          height: MediaQuery.of(context).size.width * 0.8,
                          child: LyricView(
                            baseUrl: widget.baseUrl,
                            musicId: musicId,
                            currentPosition: _currentPosition,
                          ),
                        )
                      : _buildHeroCover(coverUrl, musicId),
                ),

                const Spacer(),
                _buildSongInfo(),
                _buildProgressBar(),
                _buildMainControls(),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlurredBackground(String url) {
    if (url.isEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black87,
      );
    }
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
          const Spacer(),
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
            child: url.isNotEmpty
              ? CachedNetworkImage(
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
    final bufferedPosition = widget.audioPlayer.bufferedPosition;
    final double bufferedValue = _totalDuration.inMilliseconds > 0
        ? bufferedPosition.inMilliseconds / _totalDuration.inMilliseconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 10),
      child: Column(
        children: [
          // 单个 Slider，缓冲进度画在轨道背景上
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withOpacity(0.15),
              thumbColor: Colors.white,
              trackShape: _BufferedTrackShape(
                bufferedValue: bufferedValue.clamp(0.0, 1.0),
                bufferedColor: Colors.white.withOpacity(0.35),
              ),
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
                                  child: music['has_cover'] == true
                                    ? CachedNetworkImage(
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
                                      )
                                    : Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[800],
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(Icons.music_note, color: Colors.grey, size: 20),
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

/// 自定义 Slider 轨道：在同一条轨道上显示缓冲进度
/// 三层颜色：已播放(activeTrackColor) > 已缓冲(bufferedColor) > 未加载(inactiveTrackColor)
class _BufferedTrackShape extends RoundedRectSliderTrackShape {
  final double bufferedValue; // 0.0 ~ 1.0
  final Color bufferedColor;

  _BufferedTrackShape({
    required this.bufferedValue,
    required this.bufferedColor,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final canvas = context.canvas;
    final trackHeight = sliderTheme.trackHeight ?? 4;
    final radius = Radius.circular(trackHeight / 2);

    // 1. 底层：未加载部分（最暗）
    final inactiveRect = RRect.fromRectAndRadius(trackRect, radius);
    canvas.drawRRect(
      inactiveRect,
      Paint()..color = sliderTheme.inactiveTrackColor ?? Colors.grey,
    );

    // 2. 中层：已缓冲部分（半透明）
    final bufferedWidth = trackRect.width * bufferedValue;
    if (bufferedWidth > 0) {
      final bufferedRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(trackRect.left, trackRect.top, bufferedWidth, trackRect.height),
        radius,
      );
      canvas.drawRRect(bufferedRect, Paint()..color = bufferedColor);
    }

    // 3. 顶层：已播放部分（最亮）
    final activeWidth = thumbCenter.dx - trackRect.left;
    if (activeWidth > 0) {
      final activeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(trackRect.left, trackRect.top, activeWidth, trackRect.height),
        radius,
      );
      canvas.drawRRect(
        activeRect,
        Paint()..color = sliderTheme.activeTrackColor ?? Colors.white,
      );
    }
  }
}
