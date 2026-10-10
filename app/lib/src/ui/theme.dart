import 'package:flutter/material.dart';

/// "Night instrument" palette: a dark, low-glare panel with a warm amber
/// trace, meant to sit next to the bed without lighting up the room.
abstract final class Palette {
  static const background = Color(0xFF070B14);
  static const surface = Color(0xFF0E1424);
  static const surfaceHigh = Color(0xFF151D31);
  static const outline = Color(0xFF222C44);
  static const grid = Color(0xFF18213A);

  static const amber = Color(0xFFFFB347);
  static const amberDim = Color(0xFF8A5E22);
  static const red = Color(0xFFFF5E4D);
  static const teal = Color(0xFF5ED6C4);

  static const text = Color(0xFFE9EDF7);
  static const muted = Color(0xFF8792AE);
  static const faint = Color(0xFF4D5772);

  /// Colour for a Modified Mercalli intensity, from calm amber to red.
  static Color forMmi(double mmi) {
    if (mmi < 3) return const Color(0xFFFFD27A);
    if (mmi < 4) return amber;
    if (mmi < 5) return const Color(0xFFFF8C42);
    return red;
  }
}

const _sans = 'SpaceGrotesk';
const mono = 'JetBrainsMono';

/// Small upper-case label used above sections and readouts.
const labelStyle = TextStyle(
  fontFamily: _sans,
  fontSize: 11,
  fontWeight: FontWeight.w500,
  letterSpacing: 1.8,
  color: Palette.muted,
);

/// Figures in readouts: monospaced so values don't jitter as they change.
const readoutStyle = TextStyle(
  fontFamily: mono,
  fontSize: 18,
  fontWeight: FontWeight.w600,
  color: Palette.text,
  fontFeatures: [FontFeature.tabularFigures()],
);

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Palette.amber,
    onPrimary: Color(0xFF231400),
    primaryContainer: Color(0xFF3A2708),
    onPrimaryContainer: Palette.amber,
    secondary: Palette.teal,
    onSecondary: Color(0xFF00201C),
    secondaryContainer: Color(0xFF173A36),
    onSecondaryContainer: Palette.teal,
    tertiary: Palette.teal,
    error: Palette.red,
    onError: Color(0xFF2B0500),
    errorContainer: Color(0xFF4A1610),
    onErrorContainer: Color(0xFFFFB4A8),
    surface: Palette.surface,
    onSurface: Palette.text,
    onSurfaceVariant: Palette.muted,
    surfaceContainerHighest: Palette.surfaceHigh,
    outline: Palette.faint,
    outlineVariant: Palette.outline,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: _sans,
    scaffoldBackgroundColor: Palette.background,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Palette.text,
      displayColor: Palette.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: _sans,
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: Palette.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: Palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Palette.outline),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Palette.muted,
      subtitleTextStyle: TextStyle(fontFamily: _sans, fontSize: 13, color: Palette.muted),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? const Color(0xFF231400) : Palette.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.amber : Palette.surfaceHigh,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.amber : Palette.outline,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: const WidgetStatePropertyAll(BorderSide(color: Palette.outline)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? const Color(0xFF3A2708) : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Palette.amber : Palette.muted,
        ),
      ),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      textStyle: TextStyle(fontFamily: mono, color: Palette.text),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.surfaceHigh,
      contentTextStyle: const TextStyle(fontFamily: _sans, color: Palette.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: Palette.outline, space: 1),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
  );
}
