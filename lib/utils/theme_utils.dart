import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/nipaplay_theme/theme_color_utils.dart';

// 根据当前主题模式返回标题的 TextStyle
TextStyle getTitleTextStyle(BuildContext context) {
  final Color foreground = ThemeColorUtils.primaryForeground(context);
  return TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
    color: foreground,
  );
}

TextStyle getTextStyle(BuildContext context) {
  final Color foreground = ThemeColorUtils.primaryForeground(context);
  return TextStyle(
    fontWeight: FontWeight.normal,
    fontSize: 16,
    color: foreground,
  );
}
