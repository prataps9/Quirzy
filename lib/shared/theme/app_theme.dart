import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

/// The one place the app's Material theme is built, from [AppPalette].
class AppTheme {
  static ThemeData get dark => _build(AppPalette.dark, Brightness.dark);
  static ThemeData get light => _build(AppPalette.light, Brightness.light);

  static ThemeData _build(AppPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final textTheme = _textTheme(p);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.accentText,
      onPrimary: isDark ? p.onAccent : Colors.white,
      primaryContainer: p.accent,
      onPrimaryContainer: p.onAccent,
      secondary: p.accentText,
      onSecondary: isDark ? p.onAccent : Colors.white,
      error: p.danger,
      onError: isDark ? p.onAccent : Colors.white,
      surface: p.surface,
      onSurface: p.text,
      onSurfaceVariant: p.textMuted,
      surfaceContainerHighest: p.surfaceHigh,
      surfaceContainerHigh: p.surfaceHigh,
      surfaceContainer: p.surface,
      outline: p.border,
      outlineVariant: p.border,
    );

    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.pill),
    );
    final buttonText = textTheme.labelLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w800);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [p],
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      dividerColor: p.border,
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: p.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          disabledBackgroundColor: p.surfaceHigh,
          disabledForegroundColor: p.textMuted,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: pill,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          disabledBackgroundColor: p.surfaceHigh,
          disabledForegroundColor: p.textMuted,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: pill,
          textStyle: buttonText,
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: pill,
          side: BorderSide(color: p.border, width: 1.5),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accentText,
          shape: pill,
          textStyle: buttonText.copyWith(fontSize: 14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.text),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: textTheme.bodyMedium!.copyWith(color: p.textMuted),
        labelStyle: textTheme.bodyMedium!.copyWith(color: p.textMuted),
        border: _inputBorder(p.border),
        enabledBorder: _inputBorder(p.border),
        focusedBorder: _inputBorder(p.accentText, width: 2),
        errorBorder: _inputBorder(p.danger),
        focusedErrorBorder: _inputBorder(p.danger, width: 2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(size: 26, color: selected ? p.accentText : p.textMuted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall!.copyWith(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? p.accentText : p.textMuted,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surfaceHigh,
        contentTextStyle: textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
        actionTextColor: p.accentText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.onAccent : p.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.accent : p.surfaceHigh,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.accent : p.border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.accent : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(p.onAccent),
        side: BorderSide(color: p.textMuted, width: 1.5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.accent,
        disabledColor: p.surfaceHigh,
        side: BorderSide(color: p.border),
        shape: pill,
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium!.copyWith(color: p.onAccent),
        checkmarkColor: p.onAccent,
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? p.accent : p.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? p.onAccent : p.text,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: p.border)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accentText,
        linearTrackColor: p.surfaceHigh,
        circularTrackColor: p.surfaceHigh,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textMuted,
        textColor: p.text,
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall!.copyWith(color: p.textMuted),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accentText,
        selectionColor: p.accent.withValues(alpha: 0.35),
        selectionHandleColor: p.accentText,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceHigh,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        textStyle: textTheme.labelSmall!.copyWith(color: p.text),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1.5}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(AppPalette p) {
    TextStyle style(double size, FontWeight weight, {Color? color, double? height}) =>
        TextStyle(fontSize: size, fontWeight: weight, color: color ?? p.text, height: height);

    return GoogleFonts.plusJakartaSansTextTheme(
      TextTheme(
        displayLarge: style(40, FontWeight.w800, height: 1.1),
        displayMedium: style(34, FontWeight.w800, height: 1.15),
        displaySmall: style(30, FontWeight.w800, height: 1.15),
        headlineLarge: style(28, FontWeight.w800, height: 1.2),
        headlineMedium: style(24, FontWeight.w800, height: 1.2),
        headlineSmall: style(20, FontWeight.w800, height: 1.25),
        titleLarge: style(20, FontWeight.w800, height: 1.25),
        titleMedium: style(16, FontWeight.w700, height: 1.3),
        titleSmall: style(14, FontWeight.w700, height: 1.3),
        bodyLarge: style(16, FontWeight.w500, height: 1.45),
        bodyMedium: style(14, FontWeight.w500, height: 1.45),
        bodySmall: style(12, FontWeight.w500, color: p.textMuted, height: 1.4),
        labelLarge: style(14, FontWeight.w700),
        labelMedium: style(12, FontWeight.w700),
        labelSmall: style(11, FontWeight.w600),
      ),
    );
  }
}
