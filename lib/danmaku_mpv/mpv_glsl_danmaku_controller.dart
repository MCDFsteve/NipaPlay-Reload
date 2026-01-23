import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../danmaku_abstraction/positioned_danmaku_item.dart';
import '../danmaku_abstraction/danmaku_content_item.dart';
import '../player_abstraction/player_abstraction.dart';
import '../utils/danmaku_glsl_shader_manager.dart';
import '../utils/globals.dart' as globals;

class MpvGlslDanmakuController {
  MpvGlslDanmakuController({
    required Player player,
  }) : _player = player;

  final Player _player;

  List<PositionedDanmakuItem> _layoutItems = const [];
  Size _logicalSize = Size.zero;
  double _pixelRatio = 1.0;

  double _fontSize = 24.0;
  double _opacity = 1.0;
  double _timeOffset = 0.0;
  double _scrollDurationSeconds = 10.0;
  double _playbackRate = 1.0;
  double _currentTimeSeconds = 0.0;
  bool _isPlaying = true;
  bool _isVisible = true;

  int _accumulatedMs = 0;
  int _renderIntervalMs = 33;
  bool _needsRender = true;
  bool _isRendering = false;
  bool _isDisposed = false;

  File? _overlayFileA;
  File? _overlayFileB;
  bool _useOverlayA = true;
  String? _lastShaderOpts;

  final Map<String, _TextLayout> _textCache = {};

  void updateLayout(
    List<PositionedDanmakuItem> items,
    Size logicalSize,
    double pixelRatio,
  ) {
    _layoutItems = items;
    if (_logicalSize != logicalSize || _pixelRatio != pixelRatio) {
      _logicalSize = logicalSize;
      _pixelRatio = pixelRatio;
      _needsRender = true;
    }
    if (!_isPlaying) {
      _scheduleImmediateRender();
    }
  }

  void updateConfig({
    required double fontSize,
    required double opacity,
    required double timeOffset,
    required double scrollDurationSeconds,
    required double playbackRate,
    required bool isPlaying,
    required bool isVisible,
  }) {
    final bool sizeChanged = fontSize != _fontSize;
    if (sizeChanged) {
      _textCache.clear();
    }

    _fontSize = fontSize;
    _opacity = opacity;
    _timeOffset = timeOffset;
    _scrollDurationSeconds = scrollDurationSeconds;
    _playbackRate = playbackRate;
    _isPlaying = isPlaying;
    _isVisible = isVisible;
    _needsRender = true;
    if (!_isPlaying) {
      _scheduleImmediateRender();
    }
  }

  void updatePlaybackTime(double timeSeconds) {
    if ((_currentTimeSeconds - timeSeconds).abs() > 0.2) {
      _needsRender = true;
    }
    _currentTimeSeconds = timeSeconds;
    if (!_isPlaying) {
      _scheduleImmediateRender();
    }
  }

  void loadDanmaku(List<Map<String, dynamic>> danmaku) {
    _needsRender = true;
    if (!_isPlaying) {
      _scheduleImmediateRender();
    }
  }

  void clearDanmaku() {
    _layoutItems = const [];
    _needsRender = true;
    if (!_isPlaying) {
      _scheduleImmediateRender();
    }
  }

  void setVisible(bool visible) {
    if (_isVisible != visible) {
      _isVisible = visible;
      _needsRender = true;
      if (!_isPlaying) {
        _scheduleImmediateRender();
      }
    }
  }

  void updateTick(int deltaMs) {
    if (_isDisposed) return;

    if (_isPlaying) {
      _currentTimeSeconds += (deltaMs / 1000.0) * _playbackRate;
    }

    _accumulatedMs += deltaMs;
    if (_accumulatedMs < _renderIntervalMs && !_needsRender) {
      return;
    }
    _accumulatedMs = 0;

    if (_isRendering) {
      return;
    }

    _renderFrame();
  }

  void _scheduleImmediateRender() {
    if (_isDisposed) return;
    if (_isRendering) {
      _needsRender = true;
      return;
    }
    _renderFrame();
  }

  Future<void> dispose() async {
    _isDisposed = true;
    _layoutItems = const [];
    _textCache.clear();
  }

  Future<void> _ensureOverlayFiles() async {
    if (_overlayFileA != null && _overlayFileB != null) {
      return;
    }

    final Directory overlayDir =
        await DanmakuGlslShaderManager.getOverlayDirectory();
    _overlayFileA = File(p.join(overlayDir.path, 'danmaku_overlay_a.png'));
    _overlayFileB = File(p.join(overlayDir.path, 'danmaku_overlay_b.png'));
  }

  Future<void> _renderFrame() async {
    if (_isDisposed) return;
    if (!_isVisible) {
      await _renderBlankFrame();
      return;
    }

    if (_logicalSize.width <= 0 || _logicalSize.height <= 0) {
      return;
    }

    if (_layoutItems.isEmpty) {
      await _renderBlankFrame();
      return;
    }

    _isRendering = true;
    _needsRender = false;

    try {
      await _ensureOverlayFiles();

      final int width = (_logicalSize.width * _pixelRatio).round();
      final int height = (_logicalSize.height * _pixelRatio).round();
      if (width <= 0 || height <= 0) {
        _isRendering = false;
        return;
      }

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      for (final item in _layoutItems) {
        if (!_shouldDrawItem(item)) {
          continue;
        }

        final _TextLayout layout = _getTextLayout(item.content);
        final Offset position = _resolveItemPosition(item, layout);
        if (position.dx.isNaN || position.dy.isNaN) {
          continue;
        }

        if (item.content.isMe) {
          _drawMeBorder(canvas, layout, position);
        }

        layout.painter.paint(canvas, position);
      }

      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(width, height);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) {
        _isRendering = false;
        return;
      }

      final Uint8List bytes = byteData.buffer.asUint8List();
      final String? texturePath = await _writeOverlay(bytes);
      if (texturePath != null) {
        _applyShaderOptions(texturePath, width.toDouble(), height.toDouble());
      }
    } catch (_) {
      // ignore render errors
    } finally {
      _isRendering = false;
    }
  }

  Future<void> _renderBlankFrame() async {
    if (_isDisposed) return;
    if (_logicalSize.width <= 0 || _logicalSize.height <= 0) {
      return;
    }

    _isRendering = true;
    _needsRender = false;

    try {
      await _ensureOverlayFiles();

      final int width = (_logicalSize.width * _pixelRatio).round();
      final int height = (_logicalSize.height * _pixelRatio).round();
      if (width <= 0 || height <= 0) {
        _isRendering = false;
        return;
      }

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final Paint clearPaint = Paint()..blendMode = BlendMode.clear;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        clearPaint,
      );

      final ui.Picture picture = recorder.endRecording();
      final ui.Image image = await picture.toImage(width, height);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        return;
      }

      final Uint8List bytes = byteData.buffer.asUint8List();
      final String? texturePath = await _writeOverlay(bytes);
      if (texturePath != null) {
        _applyShaderOptions(texturePath, width.toDouble(), height.toDouble());
      }
    } catch (_) {
      // ignore
    } finally {
      _isRendering = false;
    }
  }

  Future<String?> _writeOverlay(Uint8List bytes) async {
    if (_overlayFileA == null || _overlayFileB == null) {
      return null;
    }

    final File file = _useOverlayA ? _overlayFileA! : _overlayFileB!;
    _useOverlayA = !_useOverlayA;
    try {
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  void _applyShaderOptions(String texturePath, double width, double height) {
    final String separator = Platform.isWindows ? ';' : ':';
    final String opts = [
      'danmaku_tex=$texturePath',
      'danmaku_w=${width.toStringAsFixed(1)}',
      'danmaku_h=${height.toStringAsFixed(1)}',
      'danmaku_opacity=${_opacity.toStringAsFixed(3)}',
    ].join(separator);

    if (opts == _lastShaderOpts) {
      return;
    }
    _lastShaderOpts = opts;
    try {
      _player.setProperty('glsl-shader-opts', opts);
    } catch (_) {
      // ignore
    }
  }

  bool _shouldDrawItem(PositionedDanmakuItem item) {
    final DanmakuItemType type = item.content.type;
    final double elapsed = _currentTimeSeconds - (item.time - _timeOffset);

    if (type == DanmakuItemType.scroll) {
      const double earlyStart = 1.0;
      if (elapsed < -earlyStart) return false;
      if (elapsed > _scrollDurationSeconds) return false;
      return true;
    }

    if (type == DanmakuItemType.top || type == DanmakuItemType.bottom) {
      const double staticDuration = 5.0;
      return elapsed >= 0.0 && elapsed <= staticDuration;
    }

    return false;
  }

  _TextLayout _getTextLayout(DanmakuContentItem content) {
    final double scaledFontSize =
        _fontSize * content.fontSizeMultiplier * _pixelRatio;
    final double countFontSize = 25.0 * _pixelRatio;
    final Color baseColor = content.color;

    final String key = [
      content.text,
      content.countText ?? '',
      scaledFontSize.toStringAsFixed(2),
      countFontSize.toStringAsFixed(2),
      baseColor.value.toRadixString(16),
      content.isMe ? '1' : '0',
    ].join('|');

    final _TextLayout? cached = _textCache[key];
    if (cached != null) {
      return cached;
    }

    final double luminance =
        (0.299 * baseColor.red + 0.587 * baseColor.green + 0.114 * baseColor.blue) /
            255.0;
    final Color strokeColor = luminance < 0.2 ? Colors.white : Colors.black;

    final double stroke = globals.strokeWidth * _pixelRatio;
    final List<Shadow> shadows = [
      Shadow(offset: Offset(-stroke, -stroke), blurRadius: 0, color: strokeColor),
      Shadow(offset: Offset(stroke, -stroke), blurRadius: 0, color: strokeColor),
      Shadow(offset: Offset(stroke, stroke), blurRadius: 0, color: strokeColor),
      Shadow(offset: Offset(-stroke, stroke), blurRadius: 0, color: strokeColor),
      Shadow(offset: Offset(0, -stroke), blurRadius: 0, color: strokeColor),
      Shadow(offset: Offset(0, stroke), blurRadius: 0, color: strokeColor),
      Shadow(offset: Offset(-stroke, 0), blurRadius: 0, color: strokeColor),
      Shadow(offset: Offset(stroke, 0), blurRadius: 0, color: strokeColor),
    ];

    final TextStyle mainStyle = TextStyle(
      fontSize: scaledFontSize,
      color: baseColor,
      fontWeight: FontWeight.normal,
      shadows: shadows,
    );

    final TextStyle countStyle = TextStyle(
      fontSize: countFontSize,
      color: Colors.white,
      fontWeight: FontWeight.bold,
      shadows: shadows,
    );

    final TextSpan span = content.countText == null
        ? TextSpan(text: content.text, style: mainStyle)
        : TextSpan(
            children: [
              TextSpan(text: content.text, style: mainStyle),
              TextSpan(text: content.countText, style: countStyle),
            ],
          );

    final TextPainter painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );
    painter.layout();

    final _TextLayout layout = _TextLayout(
      painter: painter,
      width: painter.width,
      height: painter.height,
    );
    _textCache[key] = layout;
    return layout;
  }

  Offset _resolveItemPosition(
    PositionedDanmakuItem item,
    _TextLayout layout,
  ) {
    final DanmakuItemType type = item.content.type;
    final double width = _logicalSize.width * _pixelRatio;
    final double y = item.y * _pixelRatio;

    if (type == DanmakuItemType.scroll) {
      const double earlyStart = 1.0;
      final double elapsed = _currentTimeSeconds - (item.time - _timeOffset);
      final double extraDistance = (width + layout.width) / 10.0;
      final double startX = width + extraDistance;
      final double totalDistance = extraDistance + width + layout.width;
      final double adjustedElapsed = elapsed + earlyStart;
      final double totalDuration = _scrollDurationSeconds + earlyStart;
      final double x = startX - (adjustedElapsed / totalDuration) * totalDistance;
      return Offset(x, y);
    }

    final double x = (width - layout.width) / 2.0;
    return Offset(x, y);
  }

  void _drawMeBorder(Canvas canvas, _TextLayout layout, Offset position) {
    final double paddingX = 4.0 * _pixelRatio;
    final double paddingY = 2.0 * _pixelRatio;
    final Rect rect = Rect.fromLTWH(
      position.dx - paddingX,
      position.dy - paddingY,
      layout.width + paddingX * 2,
      layout.height + paddingY * 2,
    );
    final RRect rrect =
        RRect.fromRectAndRadius(rect, Radius.circular(4.0 * _pixelRatio));
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 1.0 * _pixelRatio;
    canvas.drawRRect(rrect, paint);
  }
}

class _TextLayout {
  const _TextLayout({
    required this.painter,
    required this.width,
    required this.height,
  });

  final TextPainter painter;
  final double width;
  final double height;
}
