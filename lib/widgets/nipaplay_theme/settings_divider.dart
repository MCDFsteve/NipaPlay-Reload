import 'package:flutter/material.dart';
import 'package:nipaplay/utils/nipaplay_colors.dart';

/// 设置页面中使用的分割线，自动适配浅色/深色模式。
class SettingsDivider extends StatelessWidget {
  final double height;
  final double thickness;
  final double? indent;
  final double? endIndent;

  const SettingsDivider({
    super.key,
    this.height = 1,
    this.thickness = 1,
    this.indent,
    this.endIndent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nipaplayColors;
    return Divider(
      height: height,
      thickness: thickness,
      indent: indent,
      endIndent: endIndent,
      color: colors.divider.withOpacity(context.isDarkMode ? 0.5 : 0.8),
    );
  }
}
