import 'dart:io' if (dart.library.io) 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// MPV GLSL 弹幕着色器资源管理器。
///
/// 负责将 assets/shaders/danmaku/ 下的 shader 复制到运行时可访问
/// 的本地目录，并返回可供 libmpv 读取的绝对路径。
class DanmakuGlslShaderManager {
  static const String _assetRoot = 'assets/shaders/danmaku';
  static const String _shaderFile = 'danmaku_overlay.glsl';

  static String? _cachedShaderPath;
  static Directory? _cachedOverlayDir;

  static Future<String?> getShaderPath() async {
    if (kIsWeb) {
      return null;
    }

    if (_cachedShaderPath != null) {
      return _cachedShaderPath;
    }

    final Directory targetDir = await _resolveShaderDirectory();
    final String assetPath = '$_assetRoot/$_shaderFile';
    final File outputFile = File(p.join(targetDir.path, _shaderFile));

    try {
      final ByteData byteData = await rootBundle.load(assetPath);
      await outputFile.parent.create(recursive: true);

      final Uint8List bytes = byteData.buffer.asUint8List();
      try {
        final bool shouldRewrite = !await outputFile.exists() ||
            (await outputFile.length()) != bytes.length;
        if (shouldRewrite) {
          await outputFile.writeAsBytes(bytes, flush: true);
        }
      } catch (_) {
        await outputFile.writeAsBytes(bytes, flush: true);
      }

      _cachedShaderPath = outputFile.path;
      return _cachedShaderPath;
    } catch (e) {
      debugPrint('[DanmakuGlslShaderManager] 无法提取着色器 $assetPath: $e');
      return null;
    }
  }

  static Future<Directory> getOverlayDirectory() async {
    if (_cachedOverlayDir != null) {
      return _cachedOverlayDir!;
    }

    final Directory baseDir = await _resolveShaderDirectory();
    final Directory overlayDir = Directory(p.join(baseDir.path, 'danmaku_overlays'));
    if (!await overlayDir.exists()) {
      await overlayDir.create(recursive: true);
    }
    _cachedOverlayDir = overlayDir;
    return overlayDir;
  }

  static Future<Directory> _resolveShaderDirectory() async {
    Directory baseDirectory;

    if (Platform.isAndroid || Platform.isIOS) {
      baseDirectory = await getApplicationSupportDirectory();
    } else if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      baseDirectory = await getApplicationSupportDirectory();
    } else {
      baseDirectory = await getTemporaryDirectory();
    }

    final Directory shaderDir =
        Directory(p.join(baseDirectory.path, 'danmaku_shaders'));
    if (!await shaderDir.exists()) {
      await shaderDir.create(recursive: true);
    }

    return shaderDir;
  }
}
