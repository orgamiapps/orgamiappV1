import 'package:flutter/material.dart';

class AppThemeColor {
  static const Color dullWhiteColor = Color(0xFFE5E5E5);
  static const Color pureWhiteColor = Color(0xFFFFFFFF);
  static const Color pureBlackColor = Color(0xFF000000);

  // AttendUs professional palette
  static const Color primaryIndigo = Color(0xFF2563EB); // Blue
  static const Color primaryPurple = Color(0xFF0F766E); // Teal accent
  // Backwards-compat aliases for deprecated green naming
  // These now point to the modern palette to keep the UI consistent
  static const Color darkGreenColor = primaryIndigo;
  static const Color deepGreenColor = primaryPurple;
  static const Color darkBlueColor = Color(0xFF1D4ED8);
  static const Color transparentBlueColor = Color(0x600C0C0C);
  static const Color orangeColor = Color(0xFFF27423);
  static const Color yellowColor = Colors.yellow;
  static const Color dullBlueColor = Color(0xFF93C5FD);
  static const Color lightBlueColor = Color(0xFFEFF6FF);
  static const Color dullFontColor = Color(0xFF64748B);
  static const Color dullIconColor = Color(0xFF94A3B8);
  static const Color dullFontColor1 = Color(0xFFCBD5E1);
  static const Color borderColor = Color(0xFFE2E8F0);
  static const Color transparentGreenColor = Color(0x99022E2E);

  static const Color backGroundColor = Color(0xFFF8FAFC);
  static const Color cardBackGroundColor = Color(0xFFFFFFFF);
  static const Color grayColor = Color(0xFF475569);
  static const Color lightGrayColor = Color(0xFF94A3B8);

  static const Gradient buttonGradient = LinearGradient(
    colors: [
      primaryIndigo,
      primaryPurple,
      primaryIndigo,
    ],
    tileMode: TileMode.clamp,
  );

  static const Gradient backgroundGradient1 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment(0.8, 1),
    colors: <Color>[
      orangeColor,
      yellowColor,
    ], // Gradient from https://learnui.design/tools/gradient-generator.html
    tileMode: TileMode.mirror,
  );

  static const Gradient backgroundGradient2 = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment(0.8, 1),
    colors: <Color>[
      pureBlackColor,
      pureWhiteColor,
    ], // Gradient from https://learnui.design/tools/gradient-generator.html
    tileMode: TileMode.mirror,
  );
}

// Alias used by new Badge UI components
class AppColors {
  // Primary accent used in badge UI
  static const Color primaryColor = Color(0xFF667EEA);
  // Background color used in badge screen
  static const Color backgroundColor = AppThemeColor.backGroundColor;
}
