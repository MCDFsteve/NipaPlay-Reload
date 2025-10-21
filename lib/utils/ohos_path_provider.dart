import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// HarmonyOS 下的路径提供器，使用 Stage Model 约定的沙箱目录。
class OhosPathProvider extends PathProviderPlatform {
  OhosPathProvider();

  static const String _stageEntryRoot = '/data/storage/el2/base/haps/entry';
  static const String _filesRoot = '$_stageEntryRoot/files';
  static const String _cacheRoot = '$_stageEntryRoot/cache';

  Future<String?> _ensureDir(String path) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory.path;
    } catch (error) {
      debugPrint('[OhosPathProvider] 创建目录失败: $path -> $error');
      return null;
    }
  }

  @override
  Future<String?> getApplicationDocumentsPath() {
    return _ensureDir(_filesRoot);
  }

  @override
  Future<String?> getApplicationSupportPath() {
    return _ensureDir('$_filesRoot/support');
  }

  @override
  Future<String?> getLibraryPath() {
    // OHOS 无独立的 library 目录，复用 files。
    return _ensureDir(_filesRoot);
  }

  @override
  Future<String?> getTemporaryPath() {
    return _ensureDir('$_cacheRoot/temp');
  }

  @override
  Future<String?> getApplicationCachePath() {
    return _ensureDir(_cacheRoot);
  }

  @override
  Future<String?> getDownloadsPath() {
    return _ensureDir('$_filesRoot/Downloads');
  }

  @override
  Future<String?> getExternalStoragePath() async {
    return null;
  }

  @override
  Future<List<String>?> getExternalStoragePaths({StorageDirectory? type}) async {
    return <String>[];
  }

  @override
  Future<List<String>?> getExternalCachePaths() async {
    return <String>[];
  }
}
