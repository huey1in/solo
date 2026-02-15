import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:ui';
import '../models/play_mode.dart';
import '../lyric_view.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_progress_bar.dart';
import '../widgets/player_cover.dart';
import '../widgets/volume_dialog.dart';
import '../widgets/player_queue_sheet.dart';

/// 全屏音乐播放器页面（精简版）
class MusicPlayerPageNew extends StatefulWidget {
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

  const MusicPlayerPageNew({
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
  State<MusicPlayerPageNew> createState() => _MusicPlayerPageNewState();
}

class _MusicPlayerPageNewState extends State<MusicPlayerPageNew> {
  late bool _isPlaying;
  late Duration _currentPosition;
  late Duration _totalDuration;
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
    _currentMusic = widget.getCurrentMusic();
    _volume = widget.audioPlayer.volume;
    _isFavorite = widget.isFavorite;

    _setupListeners();
  }

  void _setupListeners() {
    widget.audioPlayer.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });

    widget.audioPlayer.positionStream.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _updateCurrentMusic();
        });
      }
    });

    widget.audioPlayer.durationStream.listen((duration) {
      if (mounted) setState(() => _totalDuration = duration ?? Duration.zero);
    });
  }

  void _updateCurrentMusic() {
    final newMusic = widget.getCurrentMusic();
    if (newMusic != null &&
        _currentMusic != null &&
        newMusic['id'] != _currentMusic['id']) {
      _currentMusic = newMusic;
      _isFavorite = widget.checkIsFavorite(newMusic['id']);
    }
  }

  @override
  void didUpdateWidget(MusicPlayerPageNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFavorite != oldWidget.isFavorite) {
      setState(() => _isFavorite = widget.isFavorite);
    }
  }

  void _handleNext() {
    widget.onNext();
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

  @override
  Widget build(BuildContext context) {
    final musicId = _currentMusic?['id'];
    final bool hasCover = _currentMusic?['has_cover'] == true;
    final coverUrl = hasCover
        ? '${widget.baseUrl}/api/music/$musicId/cover'
        : '';

    return Container(
      height: MediaQuery.of(context).size.height * 0.95,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          _buildBlurredBackground(coverUrl),
          _buildGradientOverlay(),
          SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                _buildDragHandle(),
                const SizedBox(height: 6),
                _buildTopBar(),
                const Spacer(),
                _buildCoverOrLyrics(coverUrl, musicId),
                const Spacer(),
                _buildSongInfo(),
                PlayerProgressBar(
                  currentPosition: _currentPosition,
                  totalDuration: _totalDuration,
                  bufferedPosition: widget.audioPlayer.bufferedPosition,
                  onSeek: (position) => widget.audioPlayer.seek(position),
                ),
                PlayerControls(
                  isPlaying: _isPlaying,
                  playMode: widget.playMode,
                  onPlayPause: widget.onPlayPause,
                  onNext: _handleNext,
                  onPrevious: _handlePrevious,
                  onTogglePlayMode: widget.onTogglePlayMode,
                  onShowVolume: _showVolumeDialog,
                ),
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
        child: Container(color: Colors.black.withValues(alpha: 0.2)),
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.3),
            Colors.black.withValues(alpha: 0.5),
            Colors.black.withValues(alpha: 0.8),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
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

  Widget _buildCoverOrLyrics(String coverUrl, String? musicId) {
    return GestureDetector(
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
          : PlayerCover(coverUrl: coverUrl, musicId: musicId),
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
                    color: Colors.white.withValues(alpha: 0.7),
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
              setState(() => _isFavorite = !_isFavorite);
              widget.onToggleFavorite();
            },
          ),
        ],
      ),
    );
  }

  void _showVolumeDialog() {
    VolumeDialog.show(
      context: context,
      initialVolume: _volume,
      onVolumeChanged: (value) {
        setState(() => _volume = value);
        widget.audioPlayer.setVolume(value);
        widget.onVolumeChanged?.call();
      },
    );
  }

  void _showPlayQueue() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => PlayerQueueSheet(
        playQueue: widget.playQueue,
        currentMusic: _currentMusic,
        baseUrl: widget.baseUrl,
        onPlayFromQueue: (music) {
          widget.onPlayFromQueue(music);
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
        },
        checkIsFavorite: widget.checkIsFavorite,
      ),
    );
  }
}
