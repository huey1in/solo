import 'package:flutter/material.dart';

/// 音量调节对话框
class VolumeDialog {
  static void show({
    required BuildContext context,
    required double initialVolume,
    required Function(double) onVolumeChanged,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _VolumeDialogContent(
        initialVolume: initialVolume,
        onVolumeChanged: onVolumeChanged,
      ),
    );
  }
}

class _VolumeDialogContent extends StatefulWidget {
  final double initialVolume;
  final Function(double) onVolumeChanged;

  const _VolumeDialogContent({
    required this.initialVolume,
    required this.onVolumeChanged,
  });

  @override
  State<_VolumeDialogContent> createState() => _VolumeDialogContentState();
}

class _VolumeDialogContentState extends State<_VolumeDialogContent> {
  late double _volume;

  @override
  void initState() {
    super.initState();
    _volume = widget.initialVolume;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[900]?.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '音量调节',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              const Icon(Icons.volume_down, color: Colors.white60),
              Expanded(
                child: Slider(
                  value: _volume,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  onChanged: (value) {
                    setState(() => _volume = value);
                    widget.onVolumeChanged(value);
                  },
                ),
              ),
              const Icon(Icons.volume_up, color: Colors.white60),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
