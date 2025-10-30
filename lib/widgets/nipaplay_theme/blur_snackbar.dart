import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

import 'theme_color_utils.dart';

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
      builder: (context) => Positioned(
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
                filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 10 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 10 : 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: ThemeColorUtils.overlayColor(
                      context,
                      darkOpacity: 0.1,
                      lightOpacity: 0.08,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ThemeColorUtils.borderColor(
                        context,
                        darkOpacity: 0.2,
                        lightOpacity: 0.15,
                      ),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Text(
                          content,
                          style: TextStyle(
                            color: ThemeColorUtils.primaryForeground(context),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: ThemeColorUtils.secondaryForeground(context),
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
      ),
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
