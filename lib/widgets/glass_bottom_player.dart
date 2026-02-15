import 'package:flutter/material.dart';
import 'dart:ui';

/// iOS 26 Liquid Glass 拟态玻璃浮动底栏
class GlassBottomPlayer extends StatelessWidget {
  final dynamic currentMusic;
  final bool isPlaying;
  final AnimationController rotationController;
  final VoidCallback onTap;
  final VoidCallback onPlayPause;
  final String baseUrl;
  final Widget Function(
    dynamic music, {
    required double size,
    required double radius,
    bool showHero,
    bool showAnimation,
    bool useThumbnail,
  })
  buildCover;

  const GlassBottomPlayer({
    super.key,
    required this.currentMusic,
    required this.isPlaying,
    required this.rotationController,
    required this.onTap,
    required this.onPlayPause,
    required this.baseUrl,
    required this.buildCover,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 10,
      left: 15,
      right: 15,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              // 主阴影：玻璃悬浮感
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: 0,
              ),
              // 光晕：模拟光线穿过玻璃的漫射
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.04),
                blurRadius: 30,
                offset: const Offset(0, 4),
                spreadRadius: -2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.22),
                      Colors.white.withValues(alpha: 0.10),
                    ],
                  ),
                  border: Border.all(
                    width: 1.0,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                child: Stack(
                  children: [
                    // 顶部高光（最亮的折射边缘）
                    Positioned(
                      top: 0,
                      left: 10,
                      right: 10,
                      child: Container(
                        height: 1.0,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.95),
                              Colors.white,
                              Colors.white.withValues(alpha: 0.95),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // 底部反光线条
                    Positioned(
                      bottom: 0,
                      left: 30,
                      right: 30,
                      child: Container(
                        height: 0.5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.5),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 左侧边缘折射光
                    Positioned(
                      top: 10,
                      bottom: 10,
                      left: 0,
                      child: Container(
                        width: 0.5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.7),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 右侧边缘折射光
                    Positioned(
                      top: 10,
                      bottom: 10,
                      right: 0,
                      child: Container(
                        width: 0.5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white.withValues(alpha: 0.4),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 彩虹色散层（模拟光线穿过玻璃的棱镜效果）
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: const Alignment(-1.2, -0.8),
                            end: const Alignment(1.2, 0.8),
                            colors: [
                              const Color(0x12FF6EC7), // 粉色折射
                              const Color(0x08FFD93D), // 黄色
                              Colors.transparent,
                              const Color(0x0870D6FF), // 蓝色折射
                              const Color(0x10A78BFA), // 紫色折射
                            ],
                            stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                          ),
                        ),
                      ),
                    ),
                    // 内容区
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          // 封面（带玻璃阴影）
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: RotationTransition(
                              turns: rotationController,
                              child: buildCover(
                                currentMusic,
                                size: 48,
                                radius: 24,
                                showHero: true,
                                useThumbnail: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentMusic['title'] ?? '',
                                  style: TextStyle(
                                    color: Colors.black.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  currentMusic['artist'] ?? '',
                                  style: TextStyle(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          // 播放按钮（内嵌玻璃按钮）
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.06),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.6),
                                width: 0.5,
                              ),
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.black.withValues(alpha: 0.7),
                                size: 24,
                              ),
                              onPressed: onPlayPause,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
