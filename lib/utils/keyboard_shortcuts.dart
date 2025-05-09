import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'fullscreen_handler.dart';

class KeyboardShortcuts {
  static const String _shortcutsKey = 'keyboard_shortcuts';
  static const int _debounceTime = 300; // 增加防抖时间到300毫秒
  static final Map<String, int> _lastTriggerTime = {};
  static final Map<String, bool> _isProcessing = {}; // 添加处理状态标记
  static final Map<String, LogicalKeyboardKey> _keyBindings = {};
  static final Map<String, String> _shortcuts = {};
  static final Map<String, Function> _actionHandlers = {};

  // 初始化默认快捷键
  static void initialize() {
    _shortcuts.addAll({
      'play_pause': '空格',
      'fullscreen': 'Enter',
      'rewind': '←',
      'forward': '→',
      'toggle_danmaku': 'D',
    });
    _updateKeyBindings();
  }

  // 注册动作处理器
  static void registerActionHandler(String action, Function handler) {
    _actionHandlers[action] = handler;
  }

  // 处理键盘事件
  static KeyEventResult handleKeyEvent(RawKeyEvent event, BuildContext context) {
    if (event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }
    
    // 检查当前是否有文本输入焦点
    final currentFocus = FocusManager.instance.primaryFocus;
    if (currentFocus != null) {
      final currentWidget = currentFocus.context?.widget;
      // 如果当前焦点是文本输入相关的组件，不拦截键盘事件
      if (currentWidget is TextField || 
          currentWidget is TextFormField || 
          currentWidget is EditableText) {
        return KeyEventResult.ignored;
      }
    }

    // 先处理全屏相关的按键
    final fullscreenResult = FullscreenHandler.handleFullscreenKey(event, context);
    if (fullscreenResult == KeyEventResult.handled) {
      return fullscreenResult;
    }

    // 其他按键的正常处理逻辑
    for (final entry in _keyBindings.entries) {
      final action = entry.key;
      final key = entry.value;

      if (event.logicalKey == key && _shouldTrigger(action)) {
        final handler = _actionHandlers[action];
        if (handler != null) {
          handler();
          return KeyEventResult.handled;
        }
      }
    }

    return KeyEventResult.ignored;
  }

  static bool _shouldTrigger(String action) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastTime = _lastTriggerTime[action] ?? 0;
    
    // 检查是否正在处理中
    if (_isProcessing[action] == true) {
      return false;
    }
    
    if (now - lastTime < _debounceTime) {
      return false;
    }
    
    _lastTriggerTime[action] = now;
    _isProcessing[action] = true;
    
    // 设置一个定时器来重置处理状态
    Future.delayed(const Duration(milliseconds: _debounceTime), () {
      _isProcessing[action] = false;
    });
    
    return true;
  }

  static Future<void> loadShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    final savedShortcuts = prefs.getString(_shortcutsKey);
    if (savedShortcuts != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(savedShortcuts);
        _shortcuts.clear();
        _shortcuts.addAll(Map<String, String>.from(decoded));
        _updateKeyBindings();
      } catch (e) {
        //debugPrint('Error loading shortcuts: $e');
        // 如果加载失败，使用默认快捷键
        initialize();
      }
    } else {
      // 如果没有保存的快捷键，使用默认值
      initialize();
    }
  }

  static Future<void> saveShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shortcutsKey, json.encode(_shortcuts));
  }

  static void _updateKeyBindings() {
    _keyBindings.clear();
    for (final entry in _shortcuts.entries) {
      _keyBindings[entry.key] = _getKeyFromString(entry.value);
    }
  }

  static LogicalKeyboardKey _getKeyFromString(String keyString) {
    switch (keyString) {
      case '空格':
        return LogicalKeyboardKey.space;
      case 'Enter':
        return LogicalKeyboardKey.enter;
      case '←':
        return LogicalKeyboardKey.arrowLeft;
      case '→':
        return LogicalKeyboardKey.arrowRight;
      case 'P':
        return LogicalKeyboardKey.keyP;
      case 'K':
        return LogicalKeyboardKey.keyK;
      case 'F':
        return LogicalKeyboardKey.keyF;
      case 'D':
        return LogicalKeyboardKey.keyD;
      case 'J':
        return LogicalKeyboardKey.keyJ;
      case 'L':
        return LogicalKeyboardKey.keyL;
      case 'S':
        return LogicalKeyboardKey.keyS;
      case 'T':
        return LogicalKeyboardKey.keyT;
      case 'B':
        return LogicalKeyboardKey.keyB;
      case '4':
        return LogicalKeyboardKey.digit4;
      case '6':
        return LogicalKeyboardKey.digit6;
      default:
        return LogicalKeyboardKey.space;
    }
  }

  static String getShortcutText(String action) {
    return _shortcuts[action] ?? '';
  }

  static Future<void> setShortcut(String action, String shortcut) async {
    _shortcuts[action] = shortcut;
    _keyBindings[action] = _getKeyFromString(shortcut);
    await saveShortcuts();
  }

  static Map<String, String> get allShortcuts => Map.unmodifiable(_shortcuts);

  static String formatActionWithShortcut(String action, String shortcut) {
    return '$action ($shortcut)';
  }

  static Future<bool> hasSavedShortcuts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_shortcutsKey);
  }
} 