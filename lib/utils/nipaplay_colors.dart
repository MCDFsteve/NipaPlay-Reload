import 'package:flutter/material.dart';

/// 自定义的 NipaPlay 颜色集合，用于在浅色/深色模式下提供统一的色彩语义。
class NipaplayColors extends ThemeExtension<NipaplayColors> {
  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color surface;
  final Color surfaceMuted;
  final Color overlay;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color iconPrimary;
  final Color iconSecondary;
  final Color border;
  final Color divider;
  final Color accent;

  const NipaplayColors({
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.surface,
    required this.surfaceMuted,
    required this.overlay,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.iconPrimary,
    required this.iconSecondary,
    required this.border,
    required this.divider,
    required this.accent,
  });

  static const NipaplayColors light = NipaplayColors(
    backgroundPrimary: Colors.white,
    backgroundSecondary: Color(0xFFF7F8FA),
    surface: Colors.white,
    surfaceMuted: Color(0xFFF1F1F4),
    overlay: Color(0xFFE6E9F0),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF94A3B8),
    iconPrimary: Color(0xFF1E293B),
    iconSecondary: Color(0xFF64748B),
    border: Color(0xFFD4D8E0),
    divider: Color(0xFFE2E8F0),
    accent: Color(0xFF2563EB),
  );

  static const NipaplayColors dark = NipaplayColors(
    backgroundPrimary: Color(0xFF0A0A0A),
    backgroundSecondary: Color(0xFF111111),
    surface: Color(0xFF1A1A1A),
    surfaceMuted: Color(0xFF232323),
    overlay: Color(0x33FFFFFF),
    textPrimary: Colors.white,
    textSecondary: Color(0xCCFFFFFF),
    textMuted: Color(0x99FFFFFF),
    iconPrimary: Colors.white,
    iconSecondary: Color(0xB3FFFFFF),
    border: Color(0x33FFFFFF),
    divider: Color(0x1FFFFFFF),
    accent: Color(0xFF60A5FA),
  );

  @override
  NipaplayColors copyWith({
    Color? backgroundPrimary,
    Color? backgroundSecondary,
    Color? surface,
    Color? surfaceMuted,
    Color? overlay,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? iconPrimary,
    Color? iconSecondary,
    Color? border,
    Color? divider,
    Color? accent,
  }) {
    return NipaplayColors(
      backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
      backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      overlay: overlay ?? this.overlay,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      iconPrimary: iconPrimary ?? this.iconPrimary,
      iconSecondary: iconSecondary ?? this.iconSecondary,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
    );
  }

  @override
  NipaplayColors lerp(ThemeExtension<NipaplayColors>? other, double t) {
    if (other is! NipaplayColors) return this;
    return NipaplayColors(
      backgroundPrimary: Color.lerp(backgroundPrimary, other.backgroundPrimary, t)!,
      backgroundSecondary: Color.lerp(backgroundSecondary, other.backgroundSecondary, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      iconPrimary: Color.lerp(iconPrimary, other.iconPrimary, t)!,
      iconSecondary: Color.lerp(iconSecondary, other.iconSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

extension NipaplayColorExtension on BuildContext {
  NipaplayColors get nipaplayColors =>
      Theme.of(this).extension<NipaplayColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? NipaplayColors.dark
          : NipaplayColors.light);

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
