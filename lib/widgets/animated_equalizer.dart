import 'package:flutter/material.dart';

/// 动态律动图标
class AnimatedEqualizer extends StatefulWidget {
  final bool isOverlay; // 是否作为遮罩层
  final Color barColor; // 自定义颜色

  const AnimatedEqualizer({
    super.key,
    this.isOverlay = false,
    this.barColor = Colors.red,
  });

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        duration: Duration(milliseconds: 400 + (i * 150)),
        vsync: this,
      )..repeat(reverse: true),
    );
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 遮罩层样式：更大、白色
    if (widget.isOverlay) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(
          4,
          (i) => AnimatedBuilder(
            animation: _controllers[i % 3],
            builder: (c, w) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 4,
              height: 8 + (20 * _controllers[i % 3].value),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );
    }

    // 默认样式
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
          animation: _controllers[i],
          builder: (c, w) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            width: 3,
            height: 4 + (14 * _controllers[i].value),
            color: widget.barColor,
          ),
        ),
      ),
    );
  }
}
