import 'package:flutter/material.dart';

/// 播放进度条组件
class PlayerProgressBar extends StatelessWidget {
  final Duration currentPosition;
  final Duration totalDuration;
  final Duration bufferedPosition;
  final Function(Duration) onSeek;

  const PlayerProgressBar({
    super.key,
    required this.currentPosition,
    required this.totalDuration,
    required this.bufferedPosition,
    required this.onSeek,
  });

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    final double bufferedValue = totalDuration.inMilliseconds > 0
        ? bufferedPosition.inMilliseconds / totalDuration.inMilliseconds
        : 0.0;

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
              inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
              thumbColor: Colors.white,
              trackShape: BufferedTrackShape(
                bufferedValue: bufferedValue.clamp(0.0, 1.0),
                bufferedColor: Colors.white.withValues(alpha: 0.35),
              ),
            ),
            child: Slider(
              value: totalDuration.inSeconds > 0
                  ? currentPosition.inSeconds.toDouble()
                  : 0,
              max: totalDuration.inSeconds > 0
                  ? totalDuration.inSeconds.toDouble()
                  : 1,
              onChanged: (value) => onSeek(Duration(seconds: value.toInt())),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(currentPosition),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                Text(
                  _formatDuration(totalDuration),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
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
}

/// 自定义 Slider 轨道：在同一条轨道上显示缓冲进度
class BufferedTrackShape extends RoundedRectSliderTrackShape {
  final double bufferedValue;
  final Color bufferedColor;

  BufferedTrackShape({
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

    // 1. 底层：未加载部分
    final inactiveRect = RRect.fromRectAndRadius(trackRect, radius);
    canvas.drawRRect(
      inactiveRect,
      Paint()..color = sliderTheme.inactiveTrackColor ?? Colors.grey,
    );

    // 2. 中层：已缓冲部分
    final bufferedWidth = trackRect.width * bufferedValue;
    if (bufferedWidth > 0) {
      final bufferedRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          trackRect.left,
          trackRect.top,
          bufferedWidth,
          trackRect.height,
        ),
        radius,
      );
      canvas.drawRRect(bufferedRect, Paint()..color = bufferedColor);
    }

    // 3. 顶层：已播放部分
    final activeWidth = thumbCenter.dx - trackRect.left;
    if (activeWidth > 0) {
      final activeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          trackRect.left,
          trackRect.top,
          activeWidth,
          trackRect.height,
        ),
        radius,
      );
      canvas.drawRRect(
        activeRect,
        Paint()..color = sliderTheme.activeTrackColor ?? Colors.white,
      );
    }
  }
}
