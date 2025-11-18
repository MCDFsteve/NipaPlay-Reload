library day_mode_material;

import 'package:flutter/material.dart' as m;

// 重新导出原始 Material 组件，但屏蔽 Text，方便在需要的页面导入本模块来"劫持" Text。
export 'package:flutter/material.dart' hide Text;

/// 替换自带 Text：当主题为浅色（Brightness.light）时，自动把硬编码的白色系文本
/// 转换为黑色，避免日间模式中文字看不清的问题。
class Text extends m.StatelessWidget {
  const Text(
    String data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  })  : _data = data,
        _textSpan = null,
        _isRich = false;

  const Text.rich(
    m.InlineSpan textSpan, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaleFactor,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  })  : _data = null,
        _textSpan = textSpan,
        _isRich = true;

  final String? _data;
  final m.InlineSpan? _textSpan;
  final m.TextStyle? style;
  final m.StrutStyle? strutStyle;
  final m.TextAlign? textAlign;
  final m.TextDirection? textDirection;
  final m.Locale? locale;
  final bool? softWrap;
  final m.TextOverflow? overflow;
  final double? textScaleFactor;
  final int? maxLines;
  final String? semanticsLabel;
  final m.TextWidthBasis? textWidthBasis;
  final m.TextHeightBehavior? textHeightBehavior;
  final m.Color? selectionColor;
  final bool _isRich;

  @override
  m.Widget build(m.BuildContext context) {
    final m.TextStyle? effectiveStyle = _resolveStyle(context, style);

    if (_isRich) {
      return m.Text.rich(
        _textSpan!,
        style: effectiveStyle,
        strutStyle: strutStyle,
        textAlign: textAlign,
        textDirection: textDirection,
        locale: locale,
        softWrap: softWrap,
        overflow: overflow,
        textScaleFactor: textScaleFactor,
        maxLines: maxLines,
        semanticsLabel: semanticsLabel,
        textWidthBasis: textWidthBasis,
        textHeightBehavior: textHeightBehavior,
        selectionColor: selectionColor,
      );
    }

    return m.Text(
      _data ?? '',
      style: effectiveStyle,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaleFactor: textScaleFactor,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}

m.TextStyle? _resolveStyle(m.BuildContext context, m.TextStyle? incomingStyle) {
  final bool isLight = m.Theme.of(context).brightness == m.Brightness.light;
  if (!isLight) {
    return incomingStyle;
  }

  m.TextStyle workingStyle = incomingStyle ?? const m.TextStyle();

  final m.Color? currentColor = workingStyle.color;
  if (currentColor == null) {
    workingStyle = workingStyle.copyWith(color: m.Colors.black);
  } else if (_isWhiteTone(currentColor)) {
    workingStyle = workingStyle.copyWith(
      color: m.Colors.black.withOpacity(currentColor.opacity),
    );
  }

  final List<m.Shadow>? shadows = workingStyle.shadows;
  if (shadows != null && shadows.isNotEmpty) {
    final List<m.Shadow> updatedShadows = shadows
        .map<m.Shadow>((shadow) {
          final m.Color color = shadow.color;
          if (_isBlackTone(color)) {
            return m.Shadow(
              color: m.Colors.white.withOpacity(color.opacity),
              offset: shadow.offset,
              blurRadius: shadow.blurRadius,
            );
          }
          return shadow;
        })
        .toList(growable: false);
    workingStyle = workingStyle.copyWith(shadows: updatedShadows);
  }

  return workingStyle;
}

bool _isWhiteTone(m.Color color) =>
    color.red == 255 && color.green == 255 && color.blue == 255;

bool _isBlackTone(m.Color color) =>
    color.red == 0 && color.green == 0 && color.blue == 0;
