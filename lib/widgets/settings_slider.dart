import 'package:flutter/material.dart';
import 'dart:ui';

class SettingsSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final String label;
  final String Function(double value) displayTextBuilder;
  final double min;
  final double max;
  final double? step;

  const SettingsSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.displayTextBuilder,
    this.min = 0.0,
    this.max = 1.0,
    this.step,
  });

  @override
  State<SettingsSlider> createState() => _SettingsSliderState();
}

class _SettingsSliderState extends State<SettingsSlider> {
  final GlobalKey _sliderKey = GlobalKey();
  bool _isHovering = false;
  bool _isThumbHovered = false;
  bool _isDragging = false;
  OverlayEntry? _overlayEntry;

  double get _progress => ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  double _getValueFromProgress(double progress) {
    double value = widget.min + progress * (widget.max - widget.min);
    if (widget.step != null && widget.step! > 0) {
      value = ((value - widget.min) / widget.step!).round() * widget.step! + widget.min;
    }
    return value.clamp(widget.min, widget.max);
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay(BuildContext context, double progress) {
    _removeOverlay();
    final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox == null) return;
    final position = sliderBox.localToGlobal(Offset.zero);
    final size = sliderBox.size;
    final bubbleX = position.dx + (progress * size.width) - 20;
    final bubbleY = position.dy - 40;
    final value = _getValueFromProgress(progress);
    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              left: bubbleX,
              top: bubbleY,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.displayTextBuilder(value),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateValueFromPosition(Offset localPosition) {
    final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox != null) {
      final width = sliderBox.size.width;
      final progress = (localPosition.dx / width).clamp(0.0, 1.0);
      final value = _getValueFromProgress(progress);
      widget.onChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        MouseRegion(
          onEnter: (_) {
            setState(() {
              _isHovering = true;
            });
          },
          onExit: (_) {
            setState(() {
              _isHovering = false;
              _isThumbHovered = false;
            });
          },
          onHover: (event) {
            if (!_isHovering || _isDragging) return;
            final RenderBox? sliderBox = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
            if (sliderBox != null) {
              final localPosition = sliderBox.globalToLocal(event.position);
              final width = sliderBox.size.width;
              final progress = (localPosition.dx / width).clamp(0.0, 1.0);
              final thumbRect = Rect.fromLTWH(
                (_progress * width) - 8,
                16,
                16,
                16
              );
              setState(() {
                _isThumbHovered = thumbRect.contains(localPosition);
              });
            }
          },
          child: GestureDetector(
            onHorizontalDragStart: (details) {
              setState(() => _isDragging = true);
              _updateValueFromPosition(details.localPosition);
              _showOverlay(context, _progress);
            },
            onHorizontalDragUpdate: (details) {
              _updateValueFromPosition(details.localPosition);
              if (_overlayEntry != null) {
                _showOverlay(context, _progress);
              }
            },
            onHorizontalDragEnd: (details) {
              setState(() => _isDragging = false);
              _removeOverlay();
            },
            onTapDown: (details) {
              setState(() => _isDragging = true);
              _updateValueFromPosition(details.localPosition);
              _showOverlay(context, _progress);
            },
            onTapUp: (details) {
              setState(() => _isDragging = false);
              _removeOverlay();
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  key: _sliderKey,
                  clipBehavior: Clip.none,
                  children: [
                    // 背景轨道
                    Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // 进度轨道
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 20,
                      child: FractionallySizedBox(
                        widthFactor: _progress,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.3),
                                blurRadius: 2,
                                spreadRadius: 0.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 滑块
                    Positioned(
                      left: (_progress * constraints.maxWidth) - (_isThumbHovered || _isDragging ? 8 : 6),
                      top: 22 - (_isThumbHovered || _isDragging ? 8 : 6),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutBack,
                          width: _isThumbHovered || _isDragging ? 16 : 12,
                          height: _isThumbHovered || _isDragging ? 16 : 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: _isThumbHovered || _isDragging ? 6 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
} 