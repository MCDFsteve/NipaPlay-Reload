import 'dart:ui';

import 'package:flutter/material.dart';

extension ColorWithValuesCompat on Color {
  Color withValues({double? alpha, double? opacity}) {
    final double resolvedAlpha = (alpha ?? opacity ?? (this.alpha / 255)).clamp(0.0, 1.0);
    final int channel = (resolvedAlpha * 255).round();
    return withAlpha(channel);
  }
}

extension MaterialAccentColorWithValuesCompat on MaterialAccentColor {
  Color withValues({double? alpha, double? opacity}) {
    return Color(value).withValues(alpha: alpha, opacity: opacity);
  }
}
