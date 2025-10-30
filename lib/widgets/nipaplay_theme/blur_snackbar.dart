import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/nipaplay_colors.dart';
import 'package:provider/provider.dart';

class BlurSnackBar {
  static OverlayEntry? _currentOverlayEntry;
  static AnimationController? _controller; // 防止泄漏：保存当前动画控制器

  static void show(BuildContext context, String content) {
    if (_currentOverlayEntry != null) {
      _currentOverlayEntry!.remove();
      _currentOverlayEntry = null;
    }

    final overlay = Overlay.of(context);
    late final OverlayEntry overlayEntry;
    late final Animation<double> animation;
    
    // 如有旧控制器，先释放
    _controller?.dispose();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: Navigator.of(context),
    );

    animation = CurvedAnimation(
      parent: _controller!,
      curve: Curves.easeInOut,
    );
    
    overlayEntry = OverlayEntry(
      builder: (context) {
        final colors = context.nipaplayColors;
        final isDark = context.isDarkMode;
        final bool enableBlur = context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect;
        final backgroundColor = isDark
            ? colors.surface.withOpacity(0.4)
            : colors.surface.withOpacity(0.92);
        final borderColor = colors.border.withOpacity(isDark ? 0.5 : 0.7);

        return Positioned(
        bottom: 16,
        left: 16,
        right: 16,
        child: FadeTransition(
          opacity: animation,
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: enableBlur ? 10 : 0,
                  sigmaY: enableBlur ? 10 : 0,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: borderColor,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.35 : 0.1),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Text(
                          content,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: colors.iconSecondary,
                          size: 20,
                        ),
                        onPressed: () {
              _controller?.reverse().then((_) {
                            overlayEntry.remove();
                            if (_currentOverlayEntry == overlayEntry) {
                              _currentOverlayEntry = null;
                _controller?.dispose();
                _controller = null;
                            }
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      },
    );

    overlay.insert(overlayEntry);
    _currentOverlayEntry = overlayEntry;
  _controller!.forward();

    Future.delayed(const Duration(seconds: 2), () {
      if (overlayEntry.mounted) {
    _controller?.reverse().then((_) {
          overlayEntry.remove();
          if (_currentOverlayEntry == overlayEntry) {
            _currentOverlayEntry = null;
      _controller?.dispose();
      _controller = null;
          }
        });
      }
    });
  }
} 
