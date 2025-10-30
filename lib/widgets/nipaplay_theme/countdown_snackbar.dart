import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

import 'theme_color_utils.dart';

class CountdownSnackBar {
  static OverlayEntry? _currentOverlayEntry;
  static Function()? _onCancel;
  static ValueNotifier<String>? _messageNotifier;
  static AnimationController? _controller; // 防泄漏

  static void show(
    BuildContext context, 
    String message, 
    {Function()? onCancel}
  ) {
    if (_currentOverlayEntry != null) {
      // 如果已经有显示的snackbar，只更新内容
      update(message);
      return;
    }

    _onCancel = onCancel;
    _messageNotifier = ValueNotifier<String>(message);
    
    final overlay = Overlay.of(context);
    late final OverlayEntry overlayEntry;
    late final Animation<double> animation;
    
    // 释放旧控制器
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
                  child: ValueListenableBuilder<String>(
                    valueListenable: _messageNotifier!,
                    builder: (context, currentMessage, child) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_arrow,
                                color: ThemeColorUtils.secondaryForeground(context),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  currentMessage,
                                  style: TextStyle(
                                    color: ThemeColorUtils.primaryForeground(context),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (onCancel != null) ...[
                                const SizedBox(width: 8),
                                TextButton(
                              onPressed: () {
                                onCancel();
                                if (_controller != null) {
                                  _closeSnackBar(_controller!, overlayEntry);
                                }
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                backgroundColor: ThemeColorUtils.overlayColor(
                                  context,
                                  darkOpacity: 0.2,
                                  lightOpacity: 0.12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: Text(
                                '取消',
                                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                                  color: ThemeColorUtils.primaryForeground(context),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                              ],
                              const SizedBox(width: 8),
                              IconButton(
                            icon: Icon(
                              Icons.close,
                              color: ThemeColorUtils.secondaryForeground(context),
                              size: 20,
                            ),
                            onPressed: () {
                              if (onCancel != null) {
                                onCancel();
                              }
                              if (_controller != null) {
                                _closeSnackBar(_controller!, overlayEntry);
                              }
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      );
                    },
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
  }

  static void _closeSnackBar(AnimationController controller, OverlayEntry overlayEntry) {
    controller.reverse().then((_) {
      overlayEntry.remove();
      if (_currentOverlayEntry == overlayEntry) {
        _currentOverlayEntry = null;
        _messageNotifier?.dispose();
        _messageNotifier = null;
        // 释放控制器
        _controller?.dispose();
        _controller = null;
      }
    });
  }

  static void hide() {
    if (_currentOverlayEntry != null) {
      _currentOverlayEntry!.remove();
      _currentOverlayEntry = null;
      _messageNotifier?.dispose();
      _messageNotifier = null;
      _controller?.dispose();
      _controller = null;
    }
  }

  static void update(String message) {
    // 更新消息内容，不重新创建控件
    if (_messageNotifier != null) {
      _messageNotifier!.value = message;
    }
  }
} 
