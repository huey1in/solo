import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/play_mode.dart';

/// 数据持久化服务
class StorageService {
  static StorageService? _instance;
  static StorageService get instance {
    _instance ??= StorageService._();
    return _instance!;
  }

  StorageService._();

  /// 保存播放模式
  Future<void> savePlayMode(PlayMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('playMode', mode.index);
    } catch (e) {
      print('保存播放模式失败: $e');
    }
  }

  /// 加载播放模式
  Future<PlayMode> loadPlayMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt('playMode') ?? PlayMode.listLoop.index;
      return PlayMode.values[index];
    } catch (e) {
      print('加载播放模式失败: $e');
      return PlayMode.listLoop;
    }
  }

  /// 保存音量
  Future<void> saveVolume(double volume) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('volume', volume);
    } catch (e) {
      print('保存音量失败: $e');
    }
  }

  /// 加载音量
  Future<double> loadVolume() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble('volume') ?? 1.0;
    } catch (e) {
      print('加载音量失败: $e');
      return 1.0;
    }
  }

  /// 保存最近播放列表
  Future<void> saveRecentList(List<dynamic> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('recentList', json.encode(list));
    } catch (e) {
      print('保存最近播放失败: $e');
    }
  }

  /// 加载最近播放列表
  Future<List<dynamic>> loadRecentList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('recentList');
      if (jsonStr != null) {
        return json.decode(jsonStr) as List;
      }
    } catch (e) {
      print('加载最近播放失败: $e');
    }
    return [];
  }

  /// 保存播放队列
  Future<void> savePlayQueue(List<dynamic> queue) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('playQueue', json.encode(queue));
    } catch (e) {
      print('保存播放队列失败: $e');
    }
  }

  /// 加载播放队列
  Future<List<dynamic>> loadPlayQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('playQueue');
      if (jsonStr != null) {
        return json.decode(jsonStr) as List;
      }
    } catch (e) {
      print('加载播放队列失败: $e');
    }
    return [];
  }

  /// 保存喜欢列表
  Future<void> saveFavorites(List<dynamic> favorites) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('favorites', json.encode(favorites));
    } catch (e) {
      print('保存喜欢列表失败: $e');
    }
  }

  /// 加载喜欢列表
  Future<List<dynamic>> loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('favorites');
      if (jsonStr != null) {
        final decoded = json.decode(jsonStr) as List;
        // 兼容旧版（纯ID列表）和新版（完整歌曲对象列表）
        if (decoded.isNotEmpty && decoded.first is String) {
          return []; // 旧版ID列表，清空
        }
        return decoded;
      }
    } catch (e) {
      print('加载喜欢列表失败: $e');
    }
    return [];
  }

  /// 保存当前播放音乐和进度
  Future<void> saveCurrentMusic(dynamic music, int positionMs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (music != null) {
        await prefs.setString('currentMusic', json.encode(music));
        await prefs.setInt('playPosition', positionMs);
      } else {
        await prefs.remove('currentMusic');
        await prefs.remove('playPosition');
      }
    } catch (e) {
      print('保存播放进度失败: $e');
    }
  }

  /// 加载当前播放音乐和进度
  Future<Map<String, dynamic>?> loadCurrentMusic() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final musicJson = prefs.getString('currentMusic');
      if (musicJson != null) {
        final music = json.decode(musicJson);
        final position = prefs.getInt('playPosition') ?? 0;
        return {'music': music, 'position': position};
      }
    } catch (e) {
      print('加载当前播放音乐失败: $e');
    }
    return null;
  }

  /// 保存音乐列表缓存
  Future<void> saveMusicListCache(List<dynamic> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cachedMusicList', json.encode(list));
    } catch (e) {
      print('缓存音乐列表失败: $e');
    }
  }

  /// 加载音乐列表缓存
  Future<List<dynamic>> loadMusicListCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cachedMusicList');
      if (jsonStr != null) {
        return json.decode(jsonStr) as List;
      }
    } catch (e) {
      print('加载缓存音乐列表失败: $e');
    }
    return [];
  }

  /// 立即保存所有关键数据（用于应用进入后台时）
  Future<void> saveAllDataImmediately({
    required List<dynamic> favorites,
    required PlayMode playMode,
    required double volume,
    required List<dynamic> recentList,
    required List<dynamic> playQueue,
    dynamic currentMusic,
    int? playPosition,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await Future.wait([
        prefs.setString('favorites', json.encode(favorites)),
        prefs.setInt('playMode', playMode.index),
        prefs.setDouble('volume', volume),
        prefs.setString('recentList', json.encode(recentList)),
        prefs.setString('playQueue', json.encode(playQueue)),
        if (currentMusic != null) ...[
          prefs.setString('currentMusic', json.encode(currentMusic)),
          prefs.setInt('playPosition', playPosition ?? 0),
        ],
      ]);
    } catch (e) {
      print('紧急保存数据失败: $e');
    }
  }
}
