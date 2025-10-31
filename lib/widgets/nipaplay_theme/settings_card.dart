import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'theme_color_utils.dart';

/// 设置页面专用的毛玻璃卡片容器
///
/// 统一了设置页面中重复使用的毛玻璃卡片样式，包括：
/// - 圆角：12px
/// - 毛玻璃效果：根据设置决定是否启用
/// - 半透明背景：白色30%透明度
/// - 边框：白色20%透明度，0.5px宽度
/// - 内边距：16px
class SettingsCard extends StatelessWidget {
  /// 卡片的子内容
  final Widget child;

  /// 自定义内边距，如果不提供则使用默认的 16px
  final EdgeInsetsGeometry? padding;

  /// 自定义圆角半径，如果不提供则使用默认的 12px
  final double? borderRadius;

  /// 自定义外边距
  final EdgeInsetsGeometry? margin;

  /// 自定义背景透明度，如果不提供则使用默认的 0.3
  final double? backgroundOpacity;

  /// 自定义边框透明度，如果不提供则使用默认的 0.2
  final double? borderOpacity;

  /// 自定义背景颜色，若提供则忽略透明度配置
  final Color? backgroundColor;

  /// 自定义边框颜色，若提供则忽略边框透明度配置
  final Color? borderColor;

  /// 自定义阴影
  final List<BoxShadow>? boxShadow;

  const SettingsCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.margin,
    this.backgroundOpacity,
    this.borderOpacity,
    this.backgroundColor,
    this.borderColor,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final appearanceProvider = context.watch<AppearanceSettingsProvider>();
    final isBlurEnabled = appearanceProvider.enableWidgetBlurEffect;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = ThemeColorUtils.primaryForeground(context);

    final effectiveBorderRadius = borderRadius ?? 12.0;
    final effectivePadding = padding ?? const EdgeInsets.all(16.0);
    final effectiveBackgroundOpacity = backgroundOpacity ?? 0.3;
    final effectiveBorderOpacity = borderOpacity ?? 0.2;
    final Color resolvedBackgroundColor = backgroundColor ??
        (isDark
            ? baseColor.withOpacity(effectiveBackgroundOpacity)
            : Colors.white);
    final Color resolvedBorderColor = borderColor ??
        (isDark
            ? baseColor.withOpacity(effectiveBorderOpacity)
            : Colors.black.withOpacity(0.08));
    final List<BoxShadow>? resolvedBoxShadow = boxShadow ??
        [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.35)
                : Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ];

    Widget surface = ClipRRect(
      borderRadius: BorderRadius.circular(effectiveBorderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: isBlurEnabled ? 25.0 : 0.0,
          sigmaY: isBlurEnabled ? 25.0 : 0.0,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(effectiveBorderRadius),
            color: resolvedBackgroundColor,
            border: Border.all(
              color: resolvedBorderColor,
              width: 0.5,
            ),
          ),
          padding: effectivePadding,
          child: child,
        ),
      ),
    );

    Widget cardContent = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(effectiveBorderRadius),
        boxShadow: resolvedBoxShadow,
      ),
      child: surface,
    );

    // 如果有外边距，包装在Container中
    if (margin != null) {
      cardContent = Container(
        margin: margin,
        child: cardContent,
      );
    }

    return cardContent;
  }
}
