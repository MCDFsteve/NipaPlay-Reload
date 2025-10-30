// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:nipaplay/utils/nipaplay_colors.dart';

class AppTheme {
  // 获取适合当前平台的默认字体
  static String? get _platformDefaultFont {
    if (kIsWeb) return null; // Web平台使用浏览器默认字体
    return Platform.isWindows ? "微软雅黑" : null;
  }

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light, // 设置亮度为浅色模式
    fontFamily: _platformDefaultFont, // 使用平台默认字体
    scaffoldBackgroundColor: NipaplayColors.light.backgroundPrimary,
    colorScheme: ColorScheme(
      brightness: Brightness.light, // 设置颜色方案的亮度为浅色模式
      primary: NipaplayColors.light.accent,
      onPrimary: Colors.white,
      secondary: NipaplayColors.light.accent.withOpacity(0.85),
      onSecondary: Colors.white,
      surface: NipaplayColors.light.surface,
      onSurface: NipaplayColors.light.textPrimary,
      error: Colors.red,
      onError: Colors.white,
    ),
    iconTheme: IconThemeData(color: NipaplayColors.light.iconPrimary),
    textTheme: ThemeData.light().textTheme.apply(
          bodyColor: NipaplayColors.light.textPrimary,
          displayColor: NipaplayColors.light.textPrimary,
        ),
    extensions: const <ThemeExtension<dynamic>>[
      NipaplayColors.light,
    ],
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark, // 设置亮度为深色模式
    fontFamily: _platformDefaultFont, // 使用平台默认字体
    scaffoldBackgroundColor: NipaplayColors.dark.backgroundPrimary,
    colorScheme: ColorScheme(
      brightness: Brightness.dark, // 设置颜色方案的亮度为深色模式
      primary: NipaplayColors.dark.accent,
      onPrimary: Colors.black,
      secondary: NipaplayColors.dark.accent.withOpacity(0.8),
      onSecondary: Colors.black,
      surface: NipaplayColors.dark.surface,
      onSurface: NipaplayColors.dark.textPrimary,
      error: Colors.red,
      onError: Colors.white,
    ),
    iconTheme: IconThemeData(color: NipaplayColors.dark.iconPrimary),
    textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: NipaplayColors.dark.textPrimary,
          displayColor: NipaplayColors.dark.textPrimary,
        ),
    extensions: const <ThemeExtension<dynamic>>[
      NipaplayColors.dark,
    ],
  );
}
