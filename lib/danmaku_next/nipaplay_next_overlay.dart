import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_next/nipaplay_next_engine.dart';
import 'package:nipaplay/danmaku_next/danmaku_next_log.dart';
import 'package:nipaplay/danmaku_next/msdf_atlas_manager.dart';
import 'package:nipaplay/danmaku_next/msdf_danmaku_painter.dart';
import 'package:nipaplay/danmaku_next/msdf_font_atlas.dart';
import 'package:nipaplay/danmaku_next/msdf_text_renderer.dart';

class NipaPlayNextOverlay extends StatefulWidget {
  final List<Map<String, dynamic>> danmakuList;
  final double currentTimeSeconds;
  final double fontSize;
  final bool isVisible;
  final double opacity;
  final double displayArea;
  final double timeOffset;
  final double scrollDurationSeconds;
  final bool allowStacking;
  final ValueChanged<List<PositionedDanmakuItem>>? onLayoutCalculated;

  const NipaPlayNextOverlay({
    super.key,
    required this.danmakuList,
    required this.currentTimeSeconds,
    required this.fontSize,
    required this.isVisible,
    required this.opacity,
    required this.displayArea,
    required this.timeOffset,
    required this.scrollDurationSeconds,
    required this.allowStacking,
    this.onLayoutCalculated,
  });

  @override
  State<NipaPlayNextOverlay> createState() => _NipaPlayNextOverlayState();
}

class _NipaPlayNextOverlayState extends State<NipaPlayNextOverlay> {
  final NipaPlayNextEngine _engine = NipaPlayNextEngine();
  int _listIdentity = 0;
  late final MsdfTextRenderer _renderer;
  MsdfFontAtlas? _atlas;
  late final VoidCallback _atlasListener;
  double _atlasFontSize = 0.0;

  @override
  void initState() {
    super.initState();
    _listIdentity = identityHashCode(widget.danmakuList);
    DanmakuNextLog.d(
      'Overlay',
      'init list=${widget.danmakuList.length} font=${widget.fontSize} visible=${widget.isVisible}',
      throttle: Duration.zero,
    );
    _renderer = MsdfTextRenderer();
    _renderer.initialize().then((_) {
      if (mounted) setState(() {});
    });
    _atlasListener = () {
      if (mounted) setState(() {});
    };
    _attachAtlas(widget.fontSize);
  }

  @override
  void didUpdateWidget(covariant NipaPlayNextOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.fontSize != widget.fontSize) {
      DanmakuNextLog.d(
        'Overlay',
        'font size changed ${oldWidget.fontSize} -> ${widget.fontSize}',
        throttle: Duration.zero,
      );
      _attachAtlas(widget.fontSize);
    }

    final listIdentity = identityHashCode(widget.danmakuList);
    if (listIdentity != _listIdentity) {
      _listIdentity = listIdentity;
      DanmakuNextLog.d(
        'Overlay',
        'danmaku list changed size=${widget.danmakuList.length}',
        throttle: Duration.zero,
      );
    }
  }

  void _attachAtlas(double fontSize) {
    if (_atlas != null) {
      MsdfAtlasManager.removeListener(_atlasFontSize, _atlasListener);
    }
    _atlasFontSize = fontSize;
    _atlas = MsdfAtlasManager.getAtlas(
      fontSize: fontSize,
      onUpdated: _atlasListener,
    );
  }

  @override
  void dispose() {
    MsdfAtlasManager.removeListener(_atlasFontSize, _atlasListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      DanmakuNextLog.d(
        'Overlay',
        'hidden, skip build',
        throttle: const Duration(seconds: 2),
      );
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.isEmpty) {
          return const SizedBox.expand();
        }

        _engine.configure(
          danmakuList: widget.danmakuList,
          size: size,
          fontSize: widget.fontSize,
          displayArea: widget.displayArea,
          scrollDurationSeconds: widget.scrollDurationSeconds,
          allowStacking: widget.allowStacking,
        );

        final effectiveTime = widget.currentTimeSeconds + widget.timeOffset;
        final positioned = _engine.layout(effectiveTime);

        DanmakuNextLog.d(
          'Overlay',
          'build size=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)} '
          'time=${effectiveTime.toStringAsFixed(2)} items=${positioned.length}',
          throttle: const Duration(seconds: 1),
        );

        if (widget.onLayoutCalculated != null) {
          final snapshot = positioned;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.onLayoutCalculated?.call(snapshot);
          });
        }

        final atlas = _atlas;
        if (atlas == null) {
          return const SizedBox.expand();
        }

        return CustomPaint(
          painter: MsdfDanmakuPainter(
            items: positioned,
            atlas: atlas,
            renderer: _renderer,
            opacity: widget.opacity,
          ),
          size: size,
        );
      },
    );
  }
}
