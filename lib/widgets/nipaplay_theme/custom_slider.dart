import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';
import 'theme_color_utils.dart';

class CustomSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final String label;
  final String hintText;

  const CustomSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.hintText,
  });

  @override
  State<CustomSlider> createState() => _CustomSliderState();
}

class _CustomSliderState extends State<CustomSlider> with SingleTickerProviderStateMixin {
  final GlobalKey _sliderKey = GlobalKey();
  bool _isHovering = false;
  bool _isThumbHovered = false;
  bool _isDragging = false;
  OverlayEntry? _overlayEntry;
  late AnimationController _thumbAnimationController;
  late Animation<double> _thumbAnimation;

  @override
  void initState() {
    super.initState();
    _thumbAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _thumbAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _thumbAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _thumbAnimationController.dispose();
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
                  filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 10 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 10 : 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: ThemeColorUtils.overlayColor(
                        context,
                        darkOpacity: 0.2,
                        lightOpacity: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: ThemeColorUtils.borderColor(
                          context,
                          darkOpacity: 0.3,
                          lightOpacity: 0.18,
                        ),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withOpacity(isDark ? 0.35 : 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      '${(widget.value * 100).toInt()}%',
                      style: TextStyle(
                        color: ThemeColorUtils.primaryForeground(context),
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
      
      // 直接使用计算出的进度值，不再限制为固定档位
      widget.onChanged(progress);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accentColor = Theme.of(context).colorScheme.primary;
    final primaryTextColor = ThemeColorUtils.primaryForeground(context);
    final secondaryTextColor = ThemeColorUtils.secondaryForeground(context);
    final trackBackgroundColor = isDark
        ? Colors.white.withOpacity(0.2)
        : Colors.black.withOpacity(0.08);
    final trackFillColor = accentColor;
    final thumbColor = accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: primaryTextColor,
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
            });
          },
          child: GestureDetector(
            onTapDown: (details) {
              setState(() => _isDragging = true);
              _updateValueFromPosition(details.localPosition);
              _showOverlay(context, widget.value);
            },
            onTapUp: (details) {
              setState(() => _isDragging = false);
              _updateValueFromPosition(details.localPosition);
              _removeOverlay();
            },
            onPanStart: (details) {
              setState(() => _isDragging = true);
              _showOverlay(context, widget.value);
            },
            onPanUpdate: (details) {
              _updateValueFromPosition(details.localPosition);
              _showOverlay(context, widget.value);
            },
            onPanEnd: (details) {
              setState(() => _isDragging = false);
              _removeOverlay();
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  key: _sliderKey,
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: trackBackgroundColor,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: ThemeColorUtils.borderColor(
                            context,
                            darkOpacity: 0.22,
                            lightOpacity: 0.18,
                          ),
                          width: 0.5,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 20,
                      child: FractionallySizedBox(
                        widthFactor: widget.value,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: trackFillColor,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: thumbColor.withOpacity(isDark ? 0.35 : 0.2),
                                blurRadius: 10,
                                spreadRadius: 0.5,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: (widget.value * constraints.maxWidth) - (_isThumbHovered || _isDragging ? 8 : 6),
                      top: 22 - (_isThumbHovered || _isDragging ? 8 : 6),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) {
                          setState(() => _isThumbHovered = true);
                          _thumbAnimationController.forward();
                        },
                        onExit: (_) {
                          setState(() => _isThumbHovered = false);
                          _thumbAnimationController.reverse();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutBack,
                          width: _isThumbHovered || _isDragging ? 16 : 12,
                          height: _isThumbHovered || _isDragging ? 16 : 12,
                            decoration: BoxDecoration(
                              color: thumbColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: thumbColor.withOpacity(
                                      _isThumbHovered || _isDragging
                                          ? (isDark ? 0.45 : 0.28)
                                          : (isDark ? 0.35 : 0.2)),
                                  blurRadius:
                                      _isThumbHovered || _isDragging ? 12 : 8,
                                  offset: const Offset(0, 4),
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
        const SizedBox(height: 8),
        Text(
          widget.hintText,
          style: TextStyle(
            color: secondaryTextColor,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
