import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;

/// 音频缓存服务
/// 将网络音频流缓存到本地磁盘，避免重复下载导致播放卡顿
class AudioCacheService {
  static AudioCacheService? _instance;
  static AudioCacheService get instance {
    _instance ??= AudioCacheService._();
    return _instance!;
  }

  AudioCacheService._();

  Directory? _cacheDir;
  // 最大缓存大小：500MB
  static const int _maxCacheSize = 500 * 1024 * 1024;

  // 当前正在预加载的URL（避免重复下载）
  String? _preloadingUrl;
  bool _preloadCancelled = false;

  /// 初始化缓存目录
  Future<void> init() async {
    final appDir = await getApplicationCacheDirectory();
    _cacheDir = Directory('${appDir.path}/audio_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    // 启动时清理过期缓存
    _cleanupCache();
  }

  /// 根据URL生成缓存文件路径
  String _getCacheKey(String url) {
    final bytes = utf8.encode(url);
    final hash = md5.convert(bytes).toString();
    return hash;
  }

  /// 获取缓存文件
  File _getCacheFile(String url) {
    final key = _getCacheKey(url);
    return File('${_cacheDir!.path}/$key');
  }

  /// 获取缓存文件路径（公开方法）
  String getCacheFilePath(String url) {
    return _getCacheFile(url).path;
  }

  /// 获取缓存文件对象（公开方法）
  File getCacheFile(String url) {
    return _getCacheFile(url);
  }

  /// 检查URL是否已缓存
  bool isCached(String url) {
    if (_cacheDir == null) return false;
    final file = _getCacheFile(url);
    return file.existsSync() && file.lengthSync() > 0;
  }

  /// 获取音频源：优先使用本地缓存，否则使用 LockCachingAudioSource 边播边缓存
  AudioSource getAudioSource(String url) {
    if (isCached(url)) {
      // 已缓存：直接从本地文件播放，零网络延迟
      final cacheFile = _getCacheFile(url);
      // 更新访问时间（用于LRU淘汰）
      cacheFile.setLastModifiedSync(DateTime.now());
      return AudioSource.file(cacheFile.path);
    } else {
      // 未缓存：使用 LockCachingAudioSource 边播边缓存到本地
      final cacheFile = _getCacheFile(url);
      return LockCachingAudioSource(Uri.parse(url), cacheFile: cacheFile);
    }
  }

  /// 清理缓存（LRU策略：按最后修改时间排序，删除最旧的文件）
  Future<void> _cleanupCache() async {
    if (_cacheDir == null) return;

    try {
      final files = _cacheDir!.listSync().whereType<File>().toList();
      int totalSize = 0;
      for (final file in files) {
        totalSize += file.lengthSync();
      }

      if (totalSize <= _maxCacheSize) return;

      // 按最后修改时间排序（最旧的在前）
      files.sort(
        (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
      );

      // 删除最旧的文件直到缓存大小低于限制
      for (final file in files) {
        if (totalSize <= _maxCacheSize * 0.8) break; // 清理到80%
        totalSize -= file.lengthSync();
        await file.delete();
      }
    } catch (e) {
      print('清理音频缓存失败: $e');
    }
  }

  /// 手动清除所有缓存
  Future<void> clearAll() async {
    if (_cacheDir == null) return;
    try {
      if (await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
    } catch (e) {
      print('清除音频缓存失败: $e');
    }
  }

  /// 预加载：完整下载音频文件到本地缓存（优先级最高）
  /// 下载完成后切歌时直接从本地播放，零缓冲延迟
  Future<void> preloadUrl(String url) async {
    if (_cacheDir == null) return;
    if (isCached(url)) return; // 已缓存，无需下载
    if (_preloadingUrl == url) return; // 正在下载中，不重复

    _preloadingUrl = url;
    _preloadCancelled = false;

    try {
      print('预加载开始: $url');
      final cacheFile = _getCacheFile(url);
      final tempFile = File('${cacheFile.path}.tmp');

      final request = http.Request('GET', Uri.parse(url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        print('预加载失败: HTTP ${response.statusCode}');
        return;
      }

      final sink = tempFile.openWrite();
      int downloaded = 0;

      await for (final chunk in response.stream) {
        if (_preloadCancelled) {
          await sink.close();
          if (await tempFile.exists()) await tempFile.delete();
          print('预加载已取消');
          return;
        }
        sink.add(chunk);
        downloaded += chunk.length;
      }

      await sink.flush();
      await sink.close();

      // 下载完成，重命名为正式缓存文件
      if (await tempFile.exists() && tempFile.lengthSync() > 0) {
        await tempFile.rename(cacheFile.path);
        cacheFile.setLastModifiedSync(DateTime.now());
        final sizeMB = (downloaded / 1024 / 1024).toStringAsFixed(1);
        print('预加载完成: ${sizeMB}MB');
      }
    } catch (e) {
      if (!_preloadCancelled) {
        print('预加载异常: $e');
      }
    } finally {
      if (_preloadingUrl == url) {
        _preloadingUrl = null;
      }
    }
  }

  /// 取消当前预加载任务
  void cancelPreload() {
    _preloadCancelled = true;
    _preloadingUrl = null;
  }

  /// 获取缓存大小（字节）
  Future<int> getCacheSize() async {
    if (_cacheDir == null) return 0;
    try {
      final files = _cacheDir!.listSync().whereType<File>();
      int total = 0;
      for (final file in files) {
        total += file.lengthSync();
      }
      return total;
    } catch (e) {
      return 0;
    }
  }
}
