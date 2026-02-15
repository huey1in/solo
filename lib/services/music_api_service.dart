import 'dart:convert';
import 'package:http/http.dart' as http;

/// 音乐API服务
class MusicApiService {
  final String baseUrl;

  MusicApiService(this.baseUrl);

  /// 获取音乐列表
  Future<Map<String, dynamic>> fetchMusicList({
    String search = '',
    int page = 1,
    int pageSize = 30,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/api/music?search=$search&page=$page&page_size=$pageSize',
        ),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('获取音乐列表失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('网络请求失败: $e');
    }
  }

  /// 上传音乐
  Future<void> uploadMusic(String filePath) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/music/upload'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        final error = json.decode(response.body)['error'] ?? '上传失败';
        throw Exception(error);
      }
    } catch (e) {
      throw Exception('上传失败: $e');
    }
  }

  /// 删除音乐
  Future<void> deleteMusic(String musicId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/music/$musicId'),
      );

      if (response.statusCode != 200) {
        final error = json.decode(response.body)['error'] ?? '删除失败';
        throw Exception(error);
      }
    } catch (e) {
      throw Exception('删除失败: $e');
    }
  }

  /// 获取音频流URL
  String getStreamUrl(String musicId) {
    return '$baseUrl/api/music/$musicId/stream';
  }

  /// 获取封面URL
  String getCoverUrl(String musicId, {bool thumbnail = false}) {
    return thumbnail
        ? '$baseUrl/api/music/$musicId/cover?thumb=1'
        : '$baseUrl/api/music/$musicId/cover';
  }

  /// 获取歌词URL
  String getLyricUrl(String musicId) {
    return '$baseUrl/api/music/$musicId/lyric';
  }
}
