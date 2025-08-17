import 'package:flutter/material.dart';

class AppThemeColor {
  static const Color dullWhiteColor = Color(0xFFE5E5E5);
  static const Color pureWhiteColor = Color(0xFFFFFFFF);
  static const Color pureBlackColor = Color(0xFF000000);

  static const Color darkGreenColor = Color(0xFF9CC092);
  // Deeper, more saturated green for emphasis in call-to-action text
  static const Color deepGreenColor = Color(0xFF2E7D32);
  static const Color darkBlueColor = Color(0xFF2C5A96);
  static const Color transparentBlueColor = Color(0x600C0C0C);
  static const Color orangeColor = Color(0xFFF27423);
  static const Color yellowColor = Colors.yellow;
  static const Color greenColor = Colors.green;
  static const Color dullBlueColor = Color(0xFF73ABE4);
  static const Color lightBlueColor = Color(0xFFF3F8FC);
  static const Color dullFontColor = Color(0xFF6E757C);
  static const Color dullIconColor = Color(0xFFAFB4B6);
  static const Color dullFontColor1 = Color(0xFFB9B9B9);
  static const Color borderColor = Color(0xFFE8E8E8);
  static const Color transparentGreenColor = Color(0x99022E2E);

  static const Color backGroundColor = Color(0xFFFFFFFF);
  static const Color cardBackGroundColor = Color(0xFFF5F8FD);
  static const Color grayColor = Color(0xFF60676C);
  static const Color lightGrayColor = Color(0xFF99999A);

  static const Gradient buttonGradient = LinearGradient(
    colors: [
      darkBlueColor,
      darkGreenColor,
      darkBlueColor,
      darkGreenColor,
      darkBlueColor,
      darkGreenColor,
      darkBlueColor,
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

// Compatibility shim: add Color.withValues(alpha: ...) used throughout the codebase
extension ColorWithValues on Color {
  Color withValues({double? alpha}) {
    if (alpha == null) return this;
    // If alpha is provided as 0.0–1.0, use withOpacity; if >1, treat as 0–255 and use withAlpha
    if (alpha <= 1.0) {
      return withOpacity(alpha);
    }
    final int a = alpha.round().clamp(0, 255);
    return withAlpha(a);
  }
}
