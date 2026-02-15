import 'dart:async';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import '../models/play_mode.dart';
import '../audio_cache_service.dart';

/// 播放器管理器
class PlayerManager {
  final AudioPlayer audioPlayer;
  final String baseUrl;

  PlayMode playMode = PlayMode.listLoop;
  List<dynamic> playQueue = [];
  dynamic currentMusic;
  bool isPlaying = false;
  bool isLoading = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;

  // 预加载标志
  bool _preloadTriggered = false;

  // 回调函数
  Function(bool)? onPlayingChanged;
  Function(bool)? onLoadingChanged;
  Function(Duration)? onPositionChanged;
  Function(Duration)? onDurationChanged;
  Function()? onCompleted;
  Function(dynamic)? onMusicChanged;

  PlayerManager({required this.audioPlayer, required this.baseUrl}) {
    _setupListeners();
  }

  /// 设置监听器
  void _setupListeners() {
    audioPlayer.playerStateStream.listen((state) {
      isPlaying = state.playing;
      onPlayingChanged?.call(isPlaying);
    });

    audioPlayer.processingStateStream.listen((state) {
      final loading =
          state == ProcessingState.loading ||
          state == ProcessingState.buffering;
      if (isLoading != loading) {
        isLoading = loading;
        onLoadingChanged?.call(isLoading);
      }
    });

    audioPlayer.positionStream.listen((position) {
      currentPosition = position;
      onPositionChanged?.call(position);
      _maybePreloadNext();
    });

    audioPlayer.durationStream.listen((duration) {
      totalDuration = duration ?? Duration.zero;
      onDurationChanged?.call(totalDuration);
    });

    audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        onCompleted?.call();
      }
    });
  }

  /// 配置音频会话
  Future<void> configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: false,
        ),
      );

      // 监听音频焦点变化
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          if (isPlaying) audioPlayer.pause();
        } else {
          if (event.type == AudioInterruptionType.pause) {
            audioPlayer.play();
          }
        }
      });

      // 监听音频变得嘈杂（如拔出耳机）
      session.becomingNoisyEventStream.listen((_) {
        if (isPlaying) audioPlayer.pause();
      });
    } catch (e) {
      print('配置音频会话失败: $e');
    }
  }

  /// 播放音乐
  Future<void> playMusic(dynamic music, {List<dynamic>? queue}) async {
    if (currentMusic?['id'] == music['id']) {
      isPlaying ? await audioPlayer.pause() : await audioPlayer.play();
      return;
    }

    // 如果提供了新的队列，则更新播放队列
    if (queue != null) {
      playQueue = List.from(queue);
    }

    // 确保当前歌曲在播放队列中
    if (!playQueue.any((m) => m['id'] == music['id'])) {
      playQueue.add(music);
    }

    currentMusic = music;
    onMusicChanged?.call(music);

    try {
      _preloadTriggered = false;
      AudioCacheService.instance.cancelPreload();

      // 设置音频源，给予足够的超时时间（30秒）
      await _setAudioSource(music).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('加载超时');
        },
      );

      audioPlayer.play();
    } catch (e) {
      print('播放失败(首次): $e');
      // 重试一次
      try {
        await audioPlayer.stop();
        await Future.delayed(const Duration(milliseconds: 500));

        await _setAudioSource(music).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception('加载超时');
          },
        );

        audioPlayer.play();
        print('重试播放成功');
      } catch (retryError) {
        print('重试播放也失败: $retryError');
        throw Exception('歌曲无法播放');
      }
    }
  }

  /// 设置音频源
  Future<void> _setAudioSource(dynamic music) async {
    final streamUrl = '$baseUrl/api/music/${music['id']}/stream';
    if (AudioCacheService.instance.isCached(streamUrl)) {
      await audioPlayer.setAudioSource(
        AudioSource.file(
          AudioCacheService.instance.getCacheFilePath(streamUrl),
        ),
      );
    } else {
      await audioPlayer.setAudioSource(
        LockCachingAudioSource(
          Uri.parse(streamUrl),
          cacheFile: AudioCacheService.instance.getCacheFile(streamUrl),
        ),
      );
    }
  }

  /// 预加载下一首
  void _maybePreloadNext() {
    if (_preloadTriggered) return;
    if (totalDuration.inSeconds <= 0) return;
    final progress =
        currentPosition.inMilliseconds / totalDuration.inMilliseconds;
    if (progress < 0.5) return;

    _preloadTriggered = true;
    final nextMusic = _getNextMusic();
    if (nextMusic == null) return;

    final nextUrl = '$baseUrl/api/music/${nextMusic['id']}/stream';
    AudioCacheService.instance.preloadUrl(nextUrl);
  }

  /// 获取下一首音乐
  dynamic _getNextMusic() {
    if (playQueue.isEmpty) return null;
    if (playMode == PlayMode.shuffle) {
      return playQueue[Random().nextInt(playQueue.length)];
    }
    int index = playQueue.indexWhere((m) => m['id'] == currentMusic?['id']);
    if (index == -1) return playQueue[0];
    int next = index + 1;
    if (next >= playQueue.length) {
      if (playMode == PlayMode.sequence) return null;
      next = 0;
    }
    return playQueue[next];
  }

  /// 下一首
  Future<void> playNext() async {
    if (playQueue.isEmpty) return;

    if (playMode == PlayMode.shuffle) {
      final random = Random();
      int next = random.nextInt(playQueue.length);
      await playMusic(playQueue[next]);
      return;
    }

    int index = playQueue.indexWhere((m) => m['id'] == currentMusic?['id']);
    if (index == -1) {
      await playMusic(playQueue[0]);
      return;
    }

    if (playMode == PlayMode.singleLoop) {
      audioPlayer.seek(Duration.zero);
      audioPlayer.play();
      return;
    }

    int next = index + 1;
    if (next >= playQueue.length) {
      if (playMode == PlayMode.sequence) {
        audioPlayer.stop();
        return;
      }
      next = 0;
    }
    await playMusic(playQueue[next]);
  }

  /// 上一首
  Future<void> playPrevious() async {
    if (playQueue.isEmpty) return;
    int index = playQueue.indexWhere((m) => m['id'] == currentMusic?['id']);
    if (index == -1) {
      await playMusic(playQueue[0]);
      return;
    }
    int previous = (index - 1 + playQueue.length) % playQueue.length;
    await playMusic(playQueue[previous]);
  }

  /// 切换播放模式
  void togglePlayMode() {
    switch (playMode) {
      case PlayMode.listLoop:
        playMode = PlayMode.singleLoop;
        break;
      case PlayMode.singleLoop:
        playMode = PlayMode.shuffle;
        break;
      case PlayMode.shuffle:
        playMode = PlayMode.sequence;
        break;
      case PlayMode.sequence:
        playMode = PlayMode.listLoop;
        break;
    }
  }

  /// 重新加载当前音乐（用于后台恢复）
  Future<void> reloadCurrentMusic() async {
    if (currentMusic == null) return;

    try {
      final streamUrl = '$baseUrl/api/music/${currentMusic['id']}/stream';
      final wasPlaying = isPlaying;

      await audioPlayer.stop();

      if (AudioCacheService.instance.isCached(streamUrl)) {
        await audioPlayer.setAudioSource(
          AudioSource.file(
            AudioCacheService.instance.getCacheFilePath(streamUrl),
          ),
          initialPosition: currentPosition,
        );
      } else {
        await audioPlayer.setAudioSource(
          LockCachingAudioSource(
            Uri.parse(streamUrl),
            cacheFile: AudioCacheService.instance.getCacheFile(streamUrl),
          ),
          initialPosition: currentPosition,
        );
      }

      if (wasPlaying) {
        await audioPlayer.play();
      }

      print('播放器恢复成功');
    } catch (e) {
      print('播放器恢复失败: $e');
    }
  }

  /// 检查播放器健康状态
  void checkHealth() {
    if (currentMusic == null) return;

    try {
      final state = audioPlayer.processingState;
      final playing = audioPlayer.playing;

      // 只有在实际播放中且状态异常时才恢复
      if (state == ProcessingState.idle && playing) {
        print('检测到播放器异常，尝试恢复');
        reloadCurrentMusic();
      }
    } catch (e) {
      print('播放器健康检查异常: $e');
    }
  }

  /// 释放资源
  void dispose() {
    audioPlayer.dispose();
  }
}
