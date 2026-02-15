import 'package:flutter/material.dart';
import 'audio_cache_service.dart';
import 'pages/music_dashboard_page.dart';

/// 应用入口
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化音频缓存服务
  await AudioCacheService.instance.init();

  runApp(const SoloMusicApp());
}

/// Solo Music 应用
class SoloMusicApp extends StatelessWidget {
  const SoloMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solo Music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFE8F4F8),
        primaryColor: const Color(0xFFFF4444),
        fontFamily: 'PingFang SC',
      ),
      home: const MusicDashboardPage(),
    );
  }
}
