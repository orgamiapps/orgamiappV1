import 'package:flutter/material.dart';
import 'responsive_helper.dart';

class Dimensions {
  // Legacy static constants for backward compatibility
  static const double fontSizeExtraSmall = 10.0;
  static const double fontSizeSmall = 12.0;
  static const double fontSizeDefault = 14.0;
  static const double fontSizeLarge = 16.0;
  static const double fontSizeExtraLarge = 18.0;
  static const double fontSizeOverLarge = 24.0;

  static const double paddingSizeExtraSmall = 5.0;
  static const double paddingSizeSmall = 10.0;
  static const double paddingSizeDefault = 15.0;
  static const double paddingSizeLarge = 20.0;
  static const double paddingSizeExtraLarge = 25.0;

  static const double radiusSmall = 5.0;
  static const double radiusDefault = 10.0;
  static const double radiusLarge = 15.0;
  static const double radiusExtraLarge = 20.0;

  static const int messageInputLength = 250;

  static const double spaceSizeVerySmall = 5;
  static const double spaceSizeSmall = 10;
  static const double spaceSizedDefault = 15;
  static const double spaceSizedLarge = 20;
  static const double spaceSizedExtraLarge = 20;

  // New responsive methods - use these for new code
  
  /// Get responsive font size based on screen size
  static double responsiveFontSize(BuildContext context, {
    double? extraSmall,
    double? small,
    double? defaultSize,
    double? large,
    double? extraLarge,
    double? overLarge,
  }) {
    final deviceType = ResponsiveHelper.getDeviceType(context);
    
    switch (deviceType) {
      case ResponsiveHelper.DeviceType.phone:
        return defaultSize ?? fontSizeDefault;
      case ResponsiveHelper.DeviceType.tablet:
        return large ?? fontSizeLarge;
      case ResponsiveHelper.DeviceType.desktop:
      case ResponsiveHelper.DeviceType.largeDesktop:
        return extraLarge ?? fontSizeExtraLarge;
    }
  }

  /// Get responsive padding based on screen size
  static double responsivePadding(BuildContext context, {
    double? extraSmall,
    double? small,
    double? defaultSize,
    double? large,
    double? extraLarge,
  }) {
    final deviceType = ResponsiveHelper.getDeviceType(context);
    
    switch (deviceType) {
      case ResponsiveHelper.DeviceType.phone:
        return defaultSize ?? paddingSizeDefault;
      case ResponsiveHelper.DeviceType.tablet:
        return large ?? paddingSizeLarge;
      case ResponsiveHelper.DeviceType.desktop:
      case ResponsiveHelper.DeviceType.largeDesktop:
        return extraLarge ?? paddingSizeExtraLarge;
    }
  }

  /// Get responsive border radius based on screen size
  static double responsiveRadius(BuildContext context, {
    double? small,
    double? defaultSize,
    double? large,
    double? extraLarge,
  }) {
    final deviceType = ResponsiveHelper.getDeviceType(context);
    
    switch (deviceType) {
      case ResponsiveHelper.DeviceType.phone:
        return defaultSize ?? radiusDefault;
      case ResponsiveHelper.DeviceType.tablet:
        return large ?? radiusLarge;
      case ResponsiveHelper.DeviceType.desktop:
      case ResponsiveHelper.DeviceType.largeDesktop:
        return extraLarge ?? radiusExtraLarge;
    }
  }

  /// Get responsive spacing based on screen size
  static double responsiveSpacing(BuildContext context, {
    double? verySmall,
    double? small,
    double? defaultSize,
    double? large,
    double? extraLarge,
  }) {
    final deviceType = ResponsiveHelper.getDeviceType(context);
    
    switch (deviceType) {
      case ResponsiveHelper.DeviceType.phone:
        return defaultSize ?? spaceSizedDefault;
      case ResponsiveHelper.DeviceType.tablet:
        return large ?? spaceSizedLarge;
      case ResponsiveHelper.DeviceType.desktop:
      case ResponsiveHelper.DeviceType.largeDesktop:
        return extraLarge ?? spaceSizedExtraLarge;
    }
  }
}
