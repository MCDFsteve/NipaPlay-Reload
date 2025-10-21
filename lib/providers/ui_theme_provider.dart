import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

/// 枚举保留占位，后续若重新引入多主题可继续扩展。
enum UIThemeType {
  nipaplay,
  fluentUI,
}

class UIThemeProvider extends ChangeNotifier {
  bool _isInitialized = false;
  ThemeMode _fluentThemeMode = ThemeMode.system;

  UIThemeProvider() {
    _initialize();
  }

  bool get isInitialized => _isInitialized;
  UIThemeType get currentTheme => UIThemeType.nipaplay;

  bool get isNipaplayTheme => true;

  /// Fluent UI 主题已移除，这里始终返回 false，保持旧调用兼容。
  bool get isFluentUITheme => false;

  ThemeMode get fluentThemeMode => _fluentThemeMode;

  Future<void> _initialize() async {
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setTheme(UIThemeType theme) async {
    // 目前仅保留 NipaPlay 主题，方法保留作兼容占位。
  }

  Future<void> setFluentThemeMode(ThemeMode mode) async {
    if (_fluentThemeMode == mode) {
      return;
    }
    _fluentThemeMode = mode;
    notifyListeners();
  }

  String getThemeName(UIThemeType theme) {
    switch (theme) {
      case UIThemeType.nipaplay:
        return 'NipaPlay';
      case UIThemeType.fluentUI:
        return 'Fluent';
    }
  }
}
