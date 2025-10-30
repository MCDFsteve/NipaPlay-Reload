import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

import 'theme_color_utils.dart';

/// 通用的毛玻璃底部弹出菜单
class GlassBottomSheet extends StatelessWidget {
  const GlassBottomSheet({
    super.key,
    required this.title,
    required this.child,
    this.height,
  });

  final String title;
  final Widget child;
  final double? height;

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    double? height,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => GlassBottomSheet(
        title: title,
        child: child,
        height: height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enableBlur = context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect;
    final sheetHeight = height ?? MediaQuery.of(context).size.height * 0.6;
    final primaryTextColor = ThemeColorUtils.primaryForeground(context);
    final gradientStart = ThemeColorUtils.glassGradientStart(
      context,
      darkOpacity: enableBlur ? 0.3 : 0.18,
      lightOpacity: enableBlur ? 0.2 : 0.12,
    );
    final gradientEnd = ThemeColorUtils.glassGradientEnd(
      context,
      darkOpacity: enableBlur ? 0.25 : 0.1,
      lightOpacity: enableBlur ? 0.15 : 0.08,
    );
    final borderStart = ThemeColorUtils.glassBorderStart(
      context,
      darkOpacity: 0.5,
      lightOpacity: 0.25,
    );
    final borderEnd = ThemeColorUtils.glassBorderEnd(
      context,
      darkOpacity: 0.35,
      lightOpacity: 0.15,
    );
    final dragHandleColor = ThemeColorUtils.overlayColor(
      context,
      darkOpacity: 0.7,
      lightOpacity: 0.4,
    );

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: GlassmorphicContainer(
        width: double.infinity,
        height: double.infinity,
        borderRadius: 20,
        blur: enableBlur ? 20 : 0,
        alignment: Alignment.center,
        border: 1,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            gradientStart,
            gradientEnd,
          ],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            borderStart,
            borderEnd,
          ],
        ),
        child: Column(
          children: [
            // 拖拽条
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              alignment: Alignment.center,
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: dragHandleColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // 标题
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                title,
                locale: const Locale('zh', 'CN'),
                style: TextStyle(
                  color: primaryTextColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // 内容
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
