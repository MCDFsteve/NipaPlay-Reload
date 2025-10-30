import 'package:flutter/material.dart';
import 'package:nipaplay/utils/nipaplay_colors.dart';

// 根据当前主题模式返回标题的 TextStyle
TextStyle getTitleTextStyle(BuildContext context) {
  final colors = context.nipaplayColors;
  return TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
    color: colors.textPrimary,
  );
}

TextStyle getTextStyle(BuildContext context) {
  final colors = context.nipaplayColors;
  return TextStyle(
    fontWeight: FontWeight.normal,
    fontSize: 16,
    color: colors.textSecondary,
  );
}
