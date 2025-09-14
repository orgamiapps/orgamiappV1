import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  late SharedPreferences _prefs;

  bool get isDarkMode => _isDarkMode;
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  // Modern Material 3 Light Theme
  ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      brightness: Brightness.light,
      primary: Color(0xFF667EEA),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFE6EEFF),
      onPrimaryContainer: Color(0xFF001D34),
      secondary: Color(0xFF764BA2),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFE8DEF8),
      onSecondaryContainer: Color(0xFF1D192B),
      tertiary: Color(0xFF7D5260),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFFFD8E4),
      onTertiaryContainer: Color(0xFF31111D),
      error: Color(0xFFE53E3E),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFFFBFE),
      onSurface: Color(0xFF1A1A1A),
      surfaceContainerHighest: Color(0xFFF4F4F4),
      onSurfaceVariant: Color(0xFF49454F),
      outline: Color(0xFF79747E),
      outlineVariant: Color(0xFFCAC4D0),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF313033),
      onInverseSurface: Color(0xFFF4EFF4),
      inversePrimary: Color(0xFF667EEA),
      surfaceTint: Color(0xFF667EEA),
    ),
    scaffoldBackgroundColor: const Color(0xFFFFFBFE),
    cardTheme: CardThemeData(
      color: const Color(0xFFFFFFFF),
      surfaceTintColor: const Color(0xFF667EEA),
      shadowColor: Colors.black.withValues(alpha: 0.1),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF667EEA),
      foregroundColor: Color(0xFFFFFFFF),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: 22,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      iconTheme: IconThemeData(color: Color(0xFFFFFFFF), size: 24),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF667EEA),
        foregroundColor: const Color(0xFFFFFFFF),
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF667EEA),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF667EEA),
        side: const BorderSide(color: Color(0xFF667EEA), width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF4F4F4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE1E5E9)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE1E5E9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF667EEA), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE53E3E), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE53E3E), width: 2),
      ),
      labelStyle: const TextStyle(color: Color(0xFF49454F)),
      hintStyle: TextStyle(
        color: const Color(0xFF49454F).withValues(alpha: 0.6),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFFFFFFFF),
      selectedItemColor: Color(0xFF667EEA),
      unselectedItemColor: Color(0xFF79747E),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE1E5E9),
      thickness: 1,
      space: 1,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 57,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      displayMedium: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 45,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      displaySmall: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 36,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      headlineLarge: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 32,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      headlineMedium: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 28,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      headlineSmall: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 24,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      titleLarge: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 22,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      titleMedium: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 16,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
      titleSmall: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 14,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
      bodyLarge: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 16,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      bodyMedium: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 14,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      bodySmall: TextStyle(
        color: Color(0xFF49454F),
        fontSize: 12,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      labelLarge: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 14,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
      labelMedium: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
      labelSmall: TextStyle(
        color: Color(0xFF49454F),
        fontSize: 11,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
    ),
  );

  // Modern Material 3 Dark Theme with enhanced aesthetics
  ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: Color(0xFF8B9EFF), // Brighter, more vibrant primary
      onPrimary: Color(0xFF001122),
      primaryContainer: Color(0xFF1A2B5C),
      onPrimaryContainer: Color(0xFFD4E1FF),
      secondary: Color(0xFFB39DDB), // More purple secondary
      onSecondary: Color(0xFF2A1F3D),
      secondaryContainer: Color(0xFF413A56),
      onSecondaryContainer: Color(0xFFE0CFFF),
      tertiary: Color(0xFFFFB3D1),
      onTertiary: Color(0xFF4A1E35),
      tertiaryContainer: Color(0xFF653049),
      onTertiaryContainer: Color(0xFFFFD9E7),
      error: Color(0xFFFF8A80),
      onError: Color(0xFF5F0016),
      errorContainer: Color(0xFF8B0000),
      onErrorContainer: Color(0xFFFFDAD4),
      surface: Color(0xFF0A0A0A), // Deeper black for better contrast
      onSurface: Color(0xFFECECEC), // Slightly brighter text
      surfaceContainerHighest: Color(0xFF1E1E1E), // Better card background
      onSurfaceVariant: Color(0xFFBDBDBD),
      outline: Color(0xFF757575),
      outlineVariant: Color(0xFF424242),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFECECEC),
      onInverseSurface: Color(0xFF1A1A1A),
      inversePrimary: Color(0xFF667EEA),
      surfaceTint: Color(0xFF8B9EFF),
    ),
    scaffoldBackgroundColor: const Color(0xFF0A0A0A),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E1E1E),
      surfaceTintColor: const Color(0xFF8B9EFF),
      shadowColor: Colors.black.withValues(alpha: 0.5),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Color(0xFFECECEC),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 22,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      iconTheme: IconThemeData(color: Color(0xFFECECEC), size: 24),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF8B9EFF),
        foregroundColor: const Color(0xFF001122),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF8B9EFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF8B9EFF),
        side: const BorderSide(color: Color(0xFF8B9EFF), width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1E1E1E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF424242)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF424242)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF8B9EFF), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF8A80), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF8A80), width: 2),
      ),
      labelStyle: const TextStyle(color: Color(0xFFBDBDBD)),
      hintStyle: TextStyle(
        color: const Color(0xFFBDBDBD).withValues(alpha: 0.6),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1E1E1E),
      selectedItemColor: Color(0xFF8B9EFF),
      unselectedItemColor: Color(0xFF757575),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF424242),
      thickness: 1,
      space: 1,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 57,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      displayMedium: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 45,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      displaySmall: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 36,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      headlineLarge: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 32,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      headlineMedium: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 28,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      headlineSmall: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 24,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      titleLarge: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 22,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      titleMedium: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 16,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
      titleSmall: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 14,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
      bodyLarge: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 16,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      bodyMedium: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 14,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      bodySmall: TextStyle(
        color: Color(0xFFBDBDBD),
        fontSize: 12,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      labelLarge: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 14,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
      labelMedium: TextStyle(
        color: Color(0xFFECECEC),
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
      labelSmall: TextStyle(
        color: Color(0xFFBDBDBD),
        fontSize: 11,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
    ),
  );

  // Legacy getters for backward compatibility
  ThemeData get getTheme => _isDarkMode ? darkTheme : lightTheme;

  void loadTheme(bool isDark) {
    _isDarkMode = isDark;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    await _saveTheme();
    if (kDebugMode) {
      debugPrint('Theme toggled to: ${_isDarkMode ? 'Dark' : 'Light'}');
    }
    notifyListeners();
  }

  Future<void> setTheme(bool isDark) async {
    _isDarkMode = isDark;
    await _saveTheme();
    if (kDebugMode) {
      debugPrint('Theme set to: ${isDark ? 'Dark' : 'Light'}');
    }
    notifyListeners();
  }

  Future<void> _saveTheme() async {
    _prefs = await SharedPreferences.getInstance();
    await _prefs.setBool('isDarkMode', _isDarkMode);
  }

  // Utility methods for theme-aware colors
  Color primaryColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  Color onPrimaryColor(BuildContext context) {
    return Theme.of(context).colorScheme.onPrimary;
  }

  Color surfaceColor(BuildContext context) {
    return Theme.of(context).colorScheme.surface;
  }

  Color onSurfaceColor(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  Color cardColor(BuildContext context) {
    return Theme.of(context).cardColor;
  }

  Color backgroundColor(BuildContext context) {
    return Theme.of(context).scaffoldBackgroundColor;
  }

  // Gradient colors for app branding
  List<Color> getGradientColors(BuildContext context) {
    return _isDarkMode
        ? [
            const Color(0xFF2A1B3D), // Deep purple-blue
            const Color(0xFF44318D), // Medium purple
            const Color(0xFF8B9EFF), // Bright primary
          ]
        : [const Color(0xFF667EEA), const Color(0xFF764BA2)];
  }

  // Additional theme-aware helper methods
  Color getCardElevationColor(BuildContext context) {
    return _isDarkMode 
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFFFFFFF);
  }

  Color getSuccessColor(BuildContext context) {
    return _isDarkMode
        ? const Color(0xFF4CAF50)
        : const Color(0xFF2E7D32);
  }

  Color getWarningColor(BuildContext context) {
    return _isDarkMode
        ? const Color(0xFFFFA726)
        : const Color(0xFFF57C00);
  }

  Color getInfoColor(BuildContext context) {
    return _isDarkMode
        ? const Color(0xFF29B6F6)
        : const Color(0xFF0277BD);
  }

  // Enhanced shadow for elevated components in dark mode
  List<BoxShadow> getElevatedShadow(BuildContext context, {double elevation = 2}) {
    return _isDarkMode
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: elevation * 3,
              offset: Offset(0, elevation),
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: elevation * 2,
              offset: Offset(0, elevation),
            ),
          ];
  }
}
