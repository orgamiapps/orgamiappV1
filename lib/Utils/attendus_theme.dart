import 'package:flutter/material.dart';

class AttendUsTokens {
  static const Color blue = Color(0xFF2563EB);
  static const Color blueDark = Color(0xFF1D4ED8);
  static const Color navy = Color(0xFF0F172A);
  static const Color slate = Color(0xFF475569);
  static const Color muted = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color canvas = Color(0xFFF8FAFC);
  static const Color softBlue = Color(0xFFEFF6FF);
  static const Color teal = Color(0xFF0F766E);
  static const Color softTeal = Color(0xFFCCFBF1);
  static const Color amber = Color(0xFFF59E0B);
  static const Color softAmber = Color(0xFFFEF3C7);
  static const Color red = Color(0xFFDC2626);
  static const Color softRed = Color(0xFFFEE2E2);

  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double pageMaxWidth = 1280;
  static const double sidebarWidth = 256;

  static const EdgeInsets pagePadding = EdgeInsets.all(20);

  static List<BoxShadow> softShadow({bool dark = false}) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.26 : 0.06),
          blurRadius: dark ? 18 : 14,
          offset: const Offset(0, 8),
        ),
      ];
}

class AttendUsTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: AttendUsTokens.blue,
      onPrimary: Colors.white,
      primaryContainer: AttendUsTokens.softBlue,
      onPrimaryContainer: AttendUsTokens.navy,
      secondary: AttendUsTokens.teal,
      onSecondary: Colors.white,
      secondaryContainer: AttendUsTokens.softTeal,
      onSecondaryContainer: Color(0xFF042F2E),
      tertiary: AttendUsTokens.amber,
      onTertiary: AttendUsTokens.navy,
      tertiaryContainer: AttendUsTokens.softAmber,
      onTertiaryContainer: Color(0xFF451A03),
      error: AttendUsTokens.red,
      onError: Colors.white,
      errorContainer: AttendUsTokens.softRed,
      onErrorContainer: Color(0xFF450A0A),
      surface: AttendUsTokens.surface,
      onSurface: AttendUsTokens.navy,
      surfaceContainerHighest: Color(0xFFF1F5F9),
      onSurfaceVariant: AttendUsTokens.slate,
      outline: Color(0xFFCBD5E1),
      outlineVariant: AttendUsTokens.border,
      shadow: Colors.black,
    );

    return _base(scheme, Brightness.light).copyWith(
      scaffoldBackgroundColor: AttendUsTokens.canvas,
      cardTheme: CardThemeData(
        color: AttendUsTokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
          side: const BorderSide(color: AttendUsTokens.border),
        ),
      ),
    );
  }

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: Color(0xFF93C5FD),
      onPrimary: Color(0xFF082F49),
      primaryContainer: Color(0xFF1E3A8A),
      onPrimaryContainer: Color(0xFFDBEAFE),
      secondary: Color(0xFF5EEAD4),
      onSecondary: Color(0xFF042F2E),
      secondaryContainer: Color(0xFF115E59),
      onSecondaryContainer: Color(0xFFCCFBF1),
      tertiary: Color(0xFFFCD34D),
      onTertiary: Color(0xFF451A03),
      tertiaryContainer: Color(0xFF92400E),
      onTertiaryContainer: Color(0xFFFEF3C7),
      error: Color(0xFFFCA5A5),
      onError: Color(0xFF450A0A),
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: Color(0xFFFEE2E2),
      surface: Color(0xFF111827),
      onSurface: Color(0xFFE5E7EB),
      surfaceContainerHighest: Color(0xFF1F2937),
      onSurfaceVariant: Color(0xFFCBD5E1),
      outline: Color(0xFF475569),
      outlineVariant: Color(0xFF334155),
      shadow: Colors.black,
    );

    return _base(scheme, Brightness.dark).copyWith(
      scaffoldBackgroundColor: const Color(0xFF0B1120),
      cardTheme: CardThemeData(
        color: const Color(0xFF111827),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
          side: const BorderSide(color: Color(0xFF334155)),
        ),
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final textColor = scheme.onSurface;
    final mutedColor = scheme.onSurfaceVariant;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        labelStyle: TextStyle(color: mutedColor),
        hintStyle: TextStyle(color: mutedColor.withValues(alpha: 0.72)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AttendUsTokens.radiusMd),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AttendUsTokens.radiusSm),
        ),
        labelStyle: TextStyle(color: textColor, fontWeight: FontWeight.w600),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: textColor,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          height: 1.12,
        ),
        headlineMedium: TextStyle(
          color: textColor,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          height: 1.16,
        ),
        headlineSmall: TextStyle(
          color: textColor,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: textColor,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: textColor, fontSize: 16, height: 1.45),
        bodyMedium: TextStyle(color: textColor, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: mutedColor, fontSize: 12, height: 1.35),
        labelLarge: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: TextStyle(
          color: mutedColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
