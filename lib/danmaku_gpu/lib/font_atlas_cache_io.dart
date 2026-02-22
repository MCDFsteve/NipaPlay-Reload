import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/utils/storage_service.dart';

class FontAtlasCacheManager {
  static const String _cacheFolderName = 'danmaku_font_atlas_cache';
  static const int _cacheVersion = 1;

  static String _buildKey(double fontSize, Color color) {
    return '${fontSize.toStringAsFixed(2)}_${color.value.toRadixString(16)}';
  }

  static Future<Directory?> _getCacheDir() async {
    try {
      final baseDir = await StorageService.getAppStorageDirectory();
      final cacheDir = Directory(p.join(baseDir.path, _cacheFolderName));
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      return cacheDir;
    } catch (e) {
      debugPrint('FontAtlasCacheManager: 获取缓存目录失败: $e');
      return null;
    }
  }

  static Future<Set<String>> loadChars({
    required double fontSize,
    Color color = Colors.white,
  }) async {
    final cacheDir = await _getCacheDir();
    if (cacheDir == null) return {};

    final key = _buildKey(fontSize, color);
    final file = File(p.join(cacheDir.path, 'atlas_$key.json'));
    if (!await file.exists()) {
      return {};
    }

    try {
      final raw = await file.readAsString();
      final data = json.decode(raw);
      if (data is! Map) return {};
      if (data['version'] != _cacheVersion) return {};

      final runes = data['runes'];
      if (runes is! List) return {};

      final Set<String> chars = {};
      for (final rune in runes) {
        if (rune is int) {
          chars.add(String.fromCharCode(rune));
        }
      }
      return chars;
    } catch (e) {
      debugPrint('FontAtlasCacheManager: 读取字符集缓存失败: $e');
      return {};
    }
  }

  static Future<void> saveChars({
    required double fontSize,
    Color color = Colors.white,
    required Set<String> chars,
  }) async {
    final cacheDir = await _getCacheDir();
    if (cacheDir == null) return;
    if (chars.isEmpty) return;

    final key = _buildKey(fontSize, color);
    final file = File(p.join(cacheDir.path, 'atlas_$key.json'));
    try {
      final runes = chars.map((char) => char.runes.first).toList();
      final payload = json.encode({
        'version': _cacheVersion,
        'fontSize': fontSize,
        'color': color.value,
        'runes': runes,
      });
      await file.writeAsString(payload);
      debugPrint('FontAtlasCacheManager: 已保存字符集缓存 (${runes.length}字)');
    } catch (e) {
      debugPrint('FontAtlasCacheManager: 保存字符集缓存失败: $e');
    }
  }
}
