import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_next/danmaku_next_log.dart';
import 'package:nipaplay/utils/storage_service.dart';

import 'msdf_font_atlas.dart';

class MsdfAtlasManager {
  MsdfAtlasManager._();

  static final Map<String, _AtlasEntry> _entries = {};
  static final Map<String, Future<void>> _cacheLoading = {};
  static final Map<String, bool> _cacheLoaded = {};
  static const int _cacheVersion = 3;
  static const String _cacheFolder = 'msdf';

  static String _key(double fontSize) => fontSize.toStringAsFixed(2);

  static MsdfFontAtlas getAtlas({
    required double fontSize,
    VoidCallback? onUpdated,
  }) {
    final key = _key(fontSize);
    final entry = _entries.putIfAbsent(key, () => _AtlasEntry(fontSize));
    if (onUpdated != null) {
      entry.listeners.add(onUpdated);
    }
    return entry.atlas;
  }

  static void removeListener(double fontSize, VoidCallback listener) {
    final entry = _entries[_key(fontSize)];
    entry?.listeners.remove(listener);
  }

  static Future<void> prebuildFromDanmakuList({
    required List<Map<String, dynamic>> danmakuList,
    required double fontSize,
    required String reason,
    bool forceRebuild = false,
  }) async {
    if (danmakuList.isEmpty) {
      DanmakuNextLog.d(
        'MSDF',
        'prebuild skipped (empty list) reason=$reason',
        throttle: Duration.zero,
      );
      return;
    }

    final chars = <String>{};
    int textCount = 0;
    for (final danmaku in danmakuList) {
      final text = (danmaku['content'] ?? danmaku['c'])?.toString() ?? '';
      if (text.isEmpty) continue;
      textCount++;
      for (final rune in text.runes) {
        chars.add(String.fromCharCode(rune));
      }
    }

    if (chars.isEmpty) {
      DanmakuNextLog.d(
        'MSDF',
        'prebuild skipped (no chars) reason=$reason',
        throttle: Duration.zero,
      );
      return;
    }

    final entry = _entries.putIfAbsent(_key(fontSize), () => _AtlasEntry(fontSize));
    final atlas = entry.atlas;
    if (forceRebuild) {
      atlas.reset(resetBaseline: true);
    } else {
      await _ensureCacheLoaded(entry, fontSize);
    }

    if (!forceRebuild && atlas.containsChars(chars)) {
      DanmakuNextLog.d(
        'MSDF',
        'prebuild skipped (cache hit) reason=$reason chars=${chars.length}',
        throttle: Duration.zero,
      );
      return;
    }

    final charList = chars.toList();
    const chunkSize = 512;
    final texts = <String>[];
    for (var i = 0; i < charList.length; i += chunkSize) {
      final end = min(i + chunkSize, charList.length);
      texts.add(charList.sublist(i, end).join());
    }

    DanmakuNextLog.d(
      'MSDF',
      'prebuild start reason=$reason texts=$textCount chars=${chars.length} chunks=${texts.length}',
      throttle: Duration.zero,
    );

    await atlas.prebuildFromTexts(texts);
    await _saveCache(entry, fontSize);

    DanmakuNextLog.d(
      'MSDF',
      'prebuild done reason=$reason chars=${chars.length}',
      throttle: Duration.zero,
    );
  }

  static Future<void> _ensureCacheLoaded(
    _AtlasEntry entry,
    double fontSize,
  ) async {
    if (kIsWeb) return;
    final key = _key(fontSize);
    if (_cacheLoaded[key] == true) return;
    final loading = _cacheLoading[key];
    if (loading != null) {
      await loading;
      return;
    }

    final future = _loadCache(entry, fontSize);
    _cacheLoading[key] = future;
    try {
      await future;
    } finally {
      _cacheLoading.remove(key);
      _cacheLoaded[key] = true;
    }
  }

  static Future<Directory> _getFontCacheDir(double fontSize) async {
    final cacheDir = await StorageService.getCacheDirectory();
    final fontKey = _key(fontSize).replaceAll('.', '_');
    final dir = Directory('${cacheDir.path}/$_cacheFolder/v$_cacheVersion/$fontKey');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<void> _loadCache(_AtlasEntry entry, double fontSize) async {
    try {
      final dir = await _getFontCacheDir(fontSize);
      final metaFile = File('${dir.path}/atlas.json');
      final imageFile = File('${dir.path}/atlas.png');
      if (!await metaFile.exists() || !await imageFile.exists()) {
        return;
      }

      final meta = jsonDecode(await metaFile.readAsString());
      if (meta is! Map<String, dynamic>) return;

      final bytes = await imageFile.readAsBytes();
      final ui.Image image = await _decodeImage(bytes);

      final ok = entry.atlas.applyCacheData(meta, image);
      if (!ok) {
        image.dispose();
        return;
      }

      DanmakuNextLog.d(
        'MSDF',
        'cache loaded path=${imageFile.path}',
        throttle: Duration.zero,
      );
      entry._notifyListeners();
    } catch (e) {
      DanmakuNextLog.d(
        'MSDF',
        'cache load failed: $e',
        throttle: Duration.zero,
      );
    }
  }

  static Future<void> _saveCache(_AtlasEntry entry, double fontSize) async {
    if (kIsWeb) return;
    final atlas = entry.atlas;
    final meta = atlas.exportCacheMeta();
    if (meta == null) return;
    final texture = atlas.atlasTexture;
    if (texture == null) return;

    try {
      final dir = await _getFontCacheDir(fontSize);
      final imageFile = File('${dir.path}/atlas.png');
      final metaFile = File('${dir.path}/atlas.json');

      final byteData = await texture.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();

      meta['version'] = _cacheVersion;
      meta['timestamp'] = DateTime.now().millisecondsSinceEpoch;

      await imageFile.writeAsBytes(bytes, flush: true);
      await metaFile.writeAsString(jsonEncode(meta), flush: true);

      DanmakuNextLog.d(
        'MSDF',
        'cache saved path=${imageFile.path} glyphs=${meta['glyphs'] is List ? (meta['glyphs'] as List).length : 0}',
        throttle: Duration.zero,
      );
    } catch (e) {
      DanmakuNextLog.d(
        'MSDF',
        'cache save failed: $e',
        throttle: Duration.zero,
      );
    }
  }

  static Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}

class _AtlasEntry {
  final Set<VoidCallback> listeners = <VoidCallback>{};
  late final MsdfFontAtlas atlas;

  _AtlasEntry(double fontSize) {
    atlas = MsdfFontAtlas(
      fontSize: fontSize,
      onAtlasUpdated: _notifyListeners,
    );
  }

  void _notifyListeners() {
    final callbacks = List<VoidCallback>.from(listeners);
    for (final callback in callbacks) {
      callback();
    }
  }
}
