import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/widgets/nipaplay_theme/hover_tooltip_bubble.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

import 'theme_color_utils.dart';

class FloatingActionGlassButton extends StatelessWidget {
  final IconData iconData;
  final VoidCallback onPressed;
  final String? tooltip;
  final String? description; // 新增：悬浮气泡描述

  const FloatingActionGlassButton({
    super.key,
    required this.iconData,
    required this.onPressed,
    this.tooltip,
    this.description, // 新增：悬浮气泡描述
  });

  @override
  Widget build(BuildContext context) {
    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final primaryIconColor = ThemeColorUtils.primaryForeground(context);
    final gradientStart = ThemeColorUtils.glassGradientStart(
      context,
      darkOpacity: appearanceSettings.enableWidgetBlurEffect ? 0.1 : 0.12,
      lightOpacity: appearanceSettings.enableWidgetBlurEffect ? 0.08 : 0.12,
    );
    final gradientEnd = ThemeColorUtils.glassGradientEnd(
      context,
      darkOpacity: appearanceSettings.enableWidgetBlurEffect ? 0.1 : 0.08,
      lightOpacity: appearanceSettings.enableWidgetBlurEffect ? 0.06 : 0.08,
    );
    final borderStart = ThemeColorUtils.glassBorderStart(context);
    final borderEnd = ThemeColorUtils.glassBorderEnd(context);
    final Widget button = GlassmorphicContainer(
      width: 56,
      height: 56,
      borderRadius: 28,
      blur: appearanceSettings.enableWidgetBlurEffect ? 25 : 0,
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onPressed,
          child: Center(
            child: Icon(
              iconData,
              color: primaryIconColor,
              size: 24,
            ),
          ),
        ),
      ),
    );

    // 如果有描述信息，则用HoverTooltipBubble包装
    if (description != null && description!.isNotEmpty) {
      return HoverTooltipBubble(
        text: description!,
        showDelay: const Duration(milliseconds: 500),
        hideDelay: const Duration(milliseconds: 100),
        child: button,
      );
    } else {
      return button;
    }
  }
} 
