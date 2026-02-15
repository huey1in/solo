import 'package:flutter/material.dart';
import '../models/play_mode.dart';

/// 播放器控制按钮组件
class PlayerControls extends StatelessWidget {
  final bool isPlaying;
  final PlayMode playMode;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePlayMode;
  final VoidCallback onShowVolume;

  const PlayerControls({
    super.key,
    required this.isPlaying,
    required this.playMode,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onTogglePlayMode,
    required this.onShowVolume,
  });

  IconData _getPlayModeIcon() {
    switch (playMode) {
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(
              _getPlayModeIcon(),
              color: Colors.white.withValues(alpha: 0.8),
              size: 28,
            ),
            onPressed: onTogglePlayMode,
          ),
          IconButton(
            icon: const Icon(
              Icons.skip_previous_rounded,
              color: Colors.white,
              size: 45,
            ),
            onPressed: onPrevious,
          ),
          GestureDetector(
            onTap: onPlayPause,
            child: Container(
              height: 80,
              width: 80,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
            onPressed: onNext,
          ),
          IconButton(
            icon: Icon(
              Icons.volume_up_outlined,
              color: Colors.white.withValues(alpha: 0.8),
              size: 28,
            ),
            onPressed: onShowVolume,
          ),
        ],
      ),
    );
  }
}
