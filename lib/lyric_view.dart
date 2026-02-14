import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

/// LRC歌词解析行
class LyricLine {
  final Duration time;
  final String text;
  LyricLine(this.time, this.text);
}

/// 歌词显示组件
class LyricView extends StatefulWidget {
  final String baseUrl;
  final String? musicId;
  final Duration currentPosition;

  const LyricView({
    super.key,
    required this.baseUrl,
    required this.musicId,
    required this.currentPosition,
  });

  @override
  State<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends State<LyricView> {
  List<LyricLine> _lyrics = [];
  bool _isLoading = true;
  bool _hasLyrics = false;
  String? _lastMusicId;
  final ScrollController _scrollController = ScrollController();
  int _currentLineIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  @override
  void didUpdateWidget(LyricView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.musicId != oldWidget.musicId) {
      _loadLyrics();
    }
    _updateCurrentLine();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics() async {
    if (widget.musicId == null || widget.musicId == _lastMusicId) return;
    _lastMusicId = widget.musicId;

    setState(() {
      _isLoading = true;
      _lyrics = [];
      _hasLyrics = false;
      _currentLineIndex = -1;
    });

    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/api/music/${widget.musicId}/lyric'),
      );

      if (response.statusCode == 200) {
        final lines = _parseLrc(response.body);
        if (mounted) {
          setState(() {
            _lyrics = lines;
            _hasLyrics = lines.isNotEmpty;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasLyrics = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasLyrics = false;
        });
      }
    }
  }

  /// 解析LRC歌词格式
  List<LyricLine> _parseLrc(String lrcContent) {
    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

    for (final line in lrcContent.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final msStr = match.group(3)!;
        final ms = msStr.length == 2
            ? int.parse(msStr) * 10
            : int.parse(msStr);
        final text = match.group(4)?.trim() ?? '';
        if (text.isNotEmpty) {
          lines.add(LyricLine(
            Duration(minutes: minutes, seconds: seconds, milliseconds: ms),
            text,
          ));
        }
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  void _updateCurrentLine() {
    if (_lyrics.isEmpty) return;

    int newIndex = -1;
    for (int i = _lyrics.length - 1; i >= 0; i--) {
      if (widget.currentPosition >= _lyrics[i].time) {
        newIndex = i;
        break;
      }
    }

    if (newIndex != _currentLineIndex && newIndex >= 0) {
      setState(() => _currentLineIndex = newIndex);
      _scrollToCurrentLine();
    }
  }

  void _scrollToCurrentLine() {
    if (!_scrollController.hasClients) return;
    if (_currentLineIndex < 0) return;

    final targetOffset = (_currentLineIndex * 48.0) - 120.0;
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(
            color: Colors.white38,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (!_hasLyrics) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            '暂无歌词',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
      itemCount: _lyrics.length,
      itemBuilder: (context, index) {
        final isActive = index == _currentLineIndex;
        return AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: TextStyle(
            color: isActive
                ? Colors.white
                : Colors.white.withOpacity(0.35),
            fontSize: isActive ? 18 : 15,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            height: 1.8,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              _lyrics[index].text,
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }
}
