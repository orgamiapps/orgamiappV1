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
      shadowColor: Colors.black.withOpacity(0.1),
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
        shadowColor: Colors.black.withOpacity(0.1),
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
        color: const Color(0xFF49454F).withOpacity(0.6),
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

  // Modern Material 3 Dark Theme
  ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      brightness: Brightness.dark,
      primary: Color(0xFF7B8EF0),
      onPrimary: Color(0xFF001D34),
      primaryContainer: Color(0xFF002D4C),
      onPrimaryContainer: Color(0xFFB8D0FF),
      secondary: Color(0xFF9A7FB8),
      onSecondary: Color(0xFF332640),
      secondaryContainer: Color(0xFF493C56),
      onSecondaryContainer: Color(0xFFD6BEF3),
      tertiary: Color(0xFFE4BAD0),
      onTertiary: Color(0xFF472532),
      tertiaryContainer: Color(0xFF603B48),
      onTertiaryContainer: Color(0xFFFFD8E4),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF0F0F0F),
      onSurface: Color(0xFFE6E1E5),
      surfaceContainerHighest: Color(0xFF1A1A1A),
      onSurfaceVariant: Color(0xFFCAC4D0),
      outline: Color(0xFF938F99),
      outlineVariant: Color(0xFF49454F),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE6E1E5),
      onInverseSurface: Color(0xFF313033),
      inversePrimary: Color(0xFF667EEA),
      surfaceTint: Color(0xFF7B8EF0),
    ),
    scaffoldBackgroundColor: const Color(0xFF0F0F0F),
    cardTheme: CardThemeData(
      color: const Color(0xFF1A1A1A),
      surfaceTintColor: const Color(0xFF7B8EF0),
      shadowColor: Colors.black.withValues(alpha: 0.4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1A1A1A),
      foregroundColor: Color(0xFFE6E1E5),
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 22,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      iconTheme: IconThemeData(color: Color(0xFFE6E1E5), size: 24),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF7B8EF0),
        foregroundColor: const Color(0xFF001D34),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF7B8EF0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF7B8EF0),
        side: const BorderSide(color: Color(0xFF7B8EF0), width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF49454F)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF49454F)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF7B8EF0), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFFB4AB), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFFB4AB), width: 2),
      ),
      labelStyle: const TextStyle(color: Color(0xFFCAC4D0)),
      hintStyle: TextStyle(
        color: const Color(0xFFCAC4D0).withValues(alpha: 0.6),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1A1A1A),
      selectedItemColor: Color(0xFF7B8EF0),
      unselectedItemColor: Color(0xFF938F99),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF49454F),
      thickness: 1,
      space: 1,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 57,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      displayMedium: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 45,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      displaySmall: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 36,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      headlineLarge: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 32,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      headlineMedium: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 28,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      headlineSmall: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 24,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      titleLarge: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 22,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      titleMedium: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 16,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
      titleSmall: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 14,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
      bodyLarge: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 16,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      bodyMedium: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 14,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      bodySmall: TextStyle(
        color: Color(0xFFCAC4D0),
        fontSize: 12,
        fontWeight: FontWeight.w400,
        fontFamily: 'Roboto',
      ),
      labelLarge: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 14,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
      labelMedium: TextStyle(
        color: Color(0xFFE6E1E5),
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFamily: 'Roboto',
      ),
      labelSmall: TextStyle(
        color: Color(0xFFCAC4D0),
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
            const Color(0xFF1E3A5F),
            const Color(0xFF2C5A96),
            const Color(0xFF4A90E2),
          ]
        : [const Color(0xFF667EEA), const Color(0xFF764BA2)];
  }
}
