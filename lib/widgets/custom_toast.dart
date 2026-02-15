import 'package:flutter/material.dart';

/// 提示类型
enum ToastType { success, error, info, loading }

/// 自定义提示组件
class CustomToast {
  static OverlayEntry? _currentToast;
  static OverlayEntry? _loadingToast;

  /// 显示提示
  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 2),
  }) {
    _currentToast?.remove();
    _currentToast = null;

    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        type: type,
        onDismiss: () {
          _currentToast?.remove();
          _currentToast = null;
        },
      ),
    );

    _currentToast = overlayEntry;
    overlay.insert(overlayEntry);

    Future.delayed(duration, () {
      if (_currentToast == overlayEntry) {
        overlayEntry.remove();
        _currentToast = null;
      }
    });
  }

  /// 显示加载提示
  static void showLoading(BuildContext context, String message) {
    hideLoading();

    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        type: ToastType.loading,
        onDismiss: () {},
      ),
    );

    _loadingToast = overlayEntry;
    overlay.insert(overlayEntry);
  }

  /// 隐藏加载提示
  static void hideLoading() {
    _loadingToast?.remove();
    _loadingToast = null;
  }

  /// 显示成功提示
  static void success(BuildContext context, String message) {
    show(context, message, type: ToastType.success);
  }

  /// 显示错误提示
  static void error(BuildContext context, String message) {
    show(context, message, type: ToastType.error);
  }

  /// 显示信息提示
  static void info(BuildContext context, String message) {
    show(context, message, type: ToastType.info);
  }
}

/// 提示组件 Widget
class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getIconColor() {
    return Colors.white;
  }

  IconData _getIcon() {
    switch (widget.type) {
      case ToastType.success:
        return Icons.check_circle_rounded;
      case ToastType.error:
        return Icons.error_rounded;
      case ToastType.loading:
        return Icons.hourglass_empty_rounded;
      case ToastType.info:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.type == ToastType.loading)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getIconColor(),
                        ),
                      ),
                    )
                  else
                    Icon(_getIcon(), color: _getIconColor(), size: 18),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
