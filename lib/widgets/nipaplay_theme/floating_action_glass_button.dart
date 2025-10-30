import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:nipaplay/widgets/nipaplay_theme/hover_tooltip_bubble.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/nipaplay_colors.dart';

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
    final palette = context.nipaplayColors;
    final isDark = context.isDarkMode;
    final bool blurEnabled = appearanceSettings.enableWidgetBlurEffect;

    final Color backgroundStart = isDark
        ? Colors.white.withOpacity(0.12)
        : palette.accent.withOpacity(blurEnabled ? 0.2 : 0.35);
    final Color backgroundEnd = isDark
        ? Colors.white.withOpacity(0.06)
        : palette.accent.withOpacity(blurEnabled ? 0.15 : 0.25);

    final Color borderStart = isDark
        ? Colors.white.withOpacity(0.45)
        : palette.border.withOpacity(0.9);
    final Color borderEnd = isDark
        ? Colors.white.withOpacity(0.25)
        : palette.border.withOpacity(0.6);

    final Color iconColor = isDark ? Colors.white : palette.backgroundPrimary;

    final Widget button = GlassmorphicContainer(
      width: 56,
      height: 56,
      borderRadius: 28,
      blur: blurEnabled ? 25 : 0,
      alignment: Alignment.center,
      border: 1,
      linearGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [backgroundStart, backgroundEnd],
      ),
      borderGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [borderStart, borderEnd],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onPressed,
          child: Center(
            child: Icon(
              iconData,
              color: iconColor,
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
