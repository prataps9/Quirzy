import 'package:flutter/material.dart';

/// The app's colour tokens, in a light and a dark set.
///
/// Read them with `context.palette`. Two rules keep the lime accent
/// readable in both modes:
///
/// * [accent] is a *fill*. Anything drawn on it uses [onAccent], never
///   white.
/// * [accentText] is the accent as a *foreground* (text, icons, rings,
///   progress, outlines). It is lime on dark surfaces and a darker lime
///   on light ones.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color accentText;
  final Color success;
  final Color danger;
  final Color streak;
  final Color like;

  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.success,
    required this.danger,
    required this.streak,
    required this.like,
  });

  static const dark = AppPalette(
    bg: Color(0xFF0A0A0C),
    surface: Color(0xFF141418),
    surfaceHigh: Color(0xFF1C1C22),
    border: Color(0xFF26262E),
    text: Color(0xFFF4F4F6),
    textMuted: Color(0xFFA0A0AB),
    accent: Color(0xFFC6F432),
    onAccent: Color(0xFF0A0A0C),
    accentText: Color(0xFFC6F432),
    success: Color(0xFF22C55E),
    danger: Color(0xFFFF5A6A),
    streak: Color(0xFFFFB020),
    like: Color(0xFFFF4D6D),
  );

  static const light = AppPalette(
    bg: Color(0xFFF7F7F9),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF0F0F3),
    border: Color(0xFFE4E4EA),
    text: Color(0xFF0A0A0C),
    textMuted: Color(0xFF5E5E6B),
    accent: Color(0xFFC6F432),
    onAccent: Color(0xFF0A0A0C),
    accentText: Color(0xFF3F6212),
    success: Color(0xFF15803D),
    danger: Color(0xFFDC2626),
    streak: Color(0xFFB45309),
    like: Color(0xFFC81E45),
  );

  /// Readable foreground for something drawn on [fill] (dark or white,
  /// whichever contrasts more).
  Color onFill(Color fill) =>
      ThemeData.estimateBrightnessForColor(fill) == Brightness.dark ? Colors.white : onAccent;

  /// A soft tint of the accent for chips and highlights.
  Color get accentSoft => accentText.withValues(alpha: 0.14);
  Color get successSoft => success.withValues(alpha: 0.14);
  Color get dangerSoft => danger.withValues(alpha: 0.14);
  Color get streakSoft => streak.withValues(alpha: 0.16);

  @override
  AppPalette copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHigh,
    Color? border,
    Color? text,
    Color? textMuted,
    Color? accent,
    Color? onAccent,
    Color? accentText,
    Color? success,
    Color? danger,
    Color? streak,
    Color? like,
  }) {
    return AppPalette(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentText: accentText ?? this.accentText,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      streak: streak ?? this.streak,
      like: like ?? this.like,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      streak: Color.lerp(streak, other.streak, t)!,
      like: Color.lerp(like, other.like, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The active palette. Falls back to the matching built-in set when the
  /// theme has no [AppPalette] (e.g. a bare `MaterialApp` in a test).
  AppPalette get palette {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark ? AppPalette.dark : AppPalette.light);
  }
}

/// Corner radii used across the app.
class AppRadius {
  static const double chip = 12;
  static const double control = 16;
  static const double card = 20;
  static const double sheet = 28;
  static const double pill = 999;
}

/// A 4-point spacing scale.
class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}
