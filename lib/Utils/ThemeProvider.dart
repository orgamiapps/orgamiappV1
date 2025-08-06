import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { light, dark }

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  AppThemeMode _themeMode = AppThemeMode.light;
  bool _isInitialized = false;

  AppThemeMode get themeMode => _themeMode;

  bool get isDarkMode {
    switch (_themeMode) {
      case AppThemeMode.light:
        return false;
      case AppThemeMode.dark:
        return true;
    }
  }

  bool get isInitialized => _isInitialized;

  ThemeProvider() {
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt(_themeKey) ?? 0; // Default to light
      _themeMode = AppThemeMode.values[themeIndex];
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      print('Error loading theme mode: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_themeKey, mode.index);
      } catch (e) {
        print('Error saving theme mode: $e');
      }
    }
  }

  // Pre-computed theme data for faster access
  static final ThemeData _lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF9CC092),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFFAFBFC),
    cardColor: Colors.white,
    dividerColor: const Color(0xFFE1E5E9),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF1A1A1A),
      elevation: 0,
      iconTheme: IconThemeData(color: Color(0xFF1A1A1A)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF9CC092),
        foregroundColor: Colors.white,
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFF1A1A1A)),
      bodyMedium: TextStyle(color: Color(0xFF6E757C)),
      titleLarge: TextStyle(color: Color(0xFF1A1A1A)),
      titleMedium: TextStyle(color: Color(0xFF1A1A1A)),
      titleSmall: TextStyle(color: Color(0xFF1A1A1A)),
      labelLarge: TextStyle(color: Color(0xFF1A1A1A)),
      labelMedium: TextStyle(color: Color(0xFF6E757C)),
    ),
    iconTheme: const IconThemeData(color: Color(0xFF1A1A1A)),
    listTileTheme: const ListTileThemeData(
      textColor: Color(0xFF1A1A1A),
      iconColor: Color(0xFF9CC092),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF9CC092);
        }
        return Colors.grey;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF9CC092).withValues(alpha: 0.5);
        }
        return Colors.grey.withValues(alpha: 0.3);
      }),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      modalBackgroundColor: Colors.white,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      titleTextStyle: TextStyle(
        color: Color(0xFF1A1A1A),
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: TextStyle(color: Color(0xFF6E757C)),
    ),
  );

  static final ThemeData _darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF9CC092),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
    cardColor: const Color(0xFF1E1E1E),
    dividerColor: const Color(0xFF2C2C2C),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF9CC092),
        foregroundColor: Colors.white,
      ),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Color(0xFFB0B0B0)),
      titleLarge: TextStyle(color: Colors.white),
      titleMedium: TextStyle(color: Colors.white),
      titleSmall: TextStyle(color: Colors.white),
      labelLarge: TextStyle(color: Colors.white),
      labelMedium: TextStyle(color: Color(0xFFB0B0B0)),
    ),
    iconTheme: const IconThemeData(color: Colors.white),
    listTileTheme: const ListTileThemeData(
      textColor: Colors.white,
      iconColor: Color(0xFF9CC092),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF9CC092);
        }
        return Colors.grey;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF9CC092).withValues(alpha: 0.5);
        }
        return Colors.grey.withValues(alpha: 0.3);
      }),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF1E1E1E),
      modalBackgroundColor: Color(0xFF1E1E1E),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Color(0xFF1E1E1E),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: TextStyle(color: Color(0xFFB0B0B0)),
    ),
  );

  ThemeData getLightTheme() => _lightTheme;

  ThemeData getDarkTheme() => _darkTheme;

  ThemeData getTheme() {
    return isDarkMode ? _darkTheme : _lightTheme;
  }
}
