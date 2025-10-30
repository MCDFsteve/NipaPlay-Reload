import 'package:flutter/material.dart';

/// 提供在深浅色模式之间切换常用颜色的辅助函数。
class ThemeColorUtils {
  ThemeColorUtils._();

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color primaryForeground(BuildContext context) =>
      _isDark(context) ? Colors.white : Colors.black;

  static Color secondaryForeground(BuildContext context) =>
      _isDark(context) ? Colors.white70 : Colors.black54;

  static Color subtleForeground(BuildContext context) =>
      _isDark(context)
          ? Colors.white.withOpacity(0.85)
          : Colors.black.withOpacity(0.7);

  static Color tertiaryForeground(BuildContext context) =>
      _isDark(context)
          ? Colors.white.withOpacity(0.6)
          : Colors.black.withOpacity(0.5);

  static Color overlayColor(
    BuildContext context, {
    double darkOpacity = 0.1,
    double lightOpacity = 0.05,
  }) =>
      _isDark(context)
          ? Colors.white.withOpacity(darkOpacity)
          : Colors.black.withOpacity(lightOpacity);

  static Color borderColor(
    BuildContext context, {
    double darkOpacity = 0.25,
    double lightOpacity = 0.2,
  }) =>
      _isDark(context)
          ? Colors.white.withOpacity(darkOpacity)
          : Colors.black.withOpacity(lightOpacity);

  static Color glassGradientStart(BuildContext context,
          {double darkOpacity = 0.18, double lightOpacity = 0.08}) =>
      (_isDark(context) ? Colors.white : Colors.black)
          .withOpacity(_isDark(context) ? darkOpacity : lightOpacity);

  static Color glassGradientEnd(BuildContext context,
          {double darkOpacity = 0.05, double lightOpacity = 0.03}) =>
      (_isDark(context) ? Colors.white : Colors.black)
          .withOpacity(_isDark(context) ? darkOpacity : lightOpacity);

  static Color glassBorderStart(BuildContext context,
          {double darkOpacity = 0.5, double lightOpacity = 0.12}) =>
      (_isDark(context) ? Colors.white : Colors.black)
          .withOpacity(_isDark(context) ? darkOpacity : lightOpacity);

  static Color glassBorderEnd(BuildContext context,
          {double darkOpacity = 0.15, double lightOpacity = 0.06}) =>
      (_isDark(context) ? Colors.white : Colors.black)
          .withOpacity(_isDark(context) ? darkOpacity : lightOpacity);
}
