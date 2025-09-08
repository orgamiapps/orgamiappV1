import 'package:flutter/material.dart';

/// Comprehensive responsive design utility for dynamic layouts across all device types
/// Supports phones, tablets, desktop, and various screen orientations
class ResponsiveHelper {
  static const double _phoneBreakpoint = 600;
  static const double _tabletBreakpoint = 900;
  static const double _desktopBreakpoint = 1200;
  static const double _largeDesktopBreakpoint = 1600;

  /// Device type enumeration
  enum DeviceType { phone, tablet, desktop, largeDesktop }

  /// Screen size category
  enum ScreenSize { small, medium, large, extraLarge }

  /// Get device type based on screen width
  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < _phoneBreakpoint) return DeviceType.phone;
    if (width < _tabletBreakpoint) return DeviceType.tablet;
    if (width < _largeDesktopBreakpoint) return DeviceType.desktop;
    return DeviceType.largeDesktop;
  }

  /// Get screen size category
  static ScreenSize getScreenSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < _phoneBreakpoint) return ScreenSize.small;
    if (width < _tabletBreakpoint) return ScreenSize.medium;
    if (width < _desktopBreakpoint) return ScreenSize.large;
    return ScreenSize.extraLarge;
  }

  /// Check if device is in landscape mode
  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  /// Get responsive padding based on device type and screen size
  static EdgeInsets getResponsivePadding(BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    final isLandscapeMode = isLandscape(context);
    
    double basePadding;
    switch (deviceType) {
      case DeviceType.phone:
        basePadding = phone ?? (isLandscapeMode ? 12.0 : 16.0);
        break;
      case DeviceType.tablet:
        basePadding = tablet ?? (isLandscapeMode ? 20.0 : 24.0);
        break;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        basePadding = desktop ?? 32.0;
        break;
    }
    
    return EdgeInsets.all(basePadding);
  }

  /// Get responsive margin
  static EdgeInsets getResponsiveMargin(BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    
    double baseMargin;
    switch (deviceType) {
      case DeviceType.phone:
        baseMargin = phone ?? 8.0;
        break;
      case DeviceType.tablet:
        baseMargin = tablet ?? 12.0;
        break;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        baseMargin = desktop ?? 16.0;
        break;
    }
    
    return EdgeInsets.all(baseMargin);
  }

  /// Get responsive font size
  static double getResponsiveFontSize(BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 14.0;
      case DeviceType.tablet:
        return tablet ?? 16.0;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? 18.0;
    }
  }

  /// Get responsive spacing
  static double getResponsiveSpacing(BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 8.0;
      case DeviceType.tablet:
        return tablet ?? 12.0;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? 16.0;
    }
  }

  /// Get responsive width percentage
  static double getResponsiveWidth(BuildContext context, {
    double phonePercent = 1.0,
    double tabletPercent = 0.8,
    double desktopPercent = 0.6,
  }) {
    final deviceType = getDeviceType(context);
    final screenWidth = MediaQuery.of(context).size.width;
    
    double percent;
    switch (deviceType) {
      case DeviceType.phone:
        percent = phonePercent;
        break;
      case DeviceType.tablet:
        percent = tabletPercent;
        break;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        percent = desktopPercent;
        break;
    }
    
    return screenWidth * percent;
  }

  /// Get responsive height percentage
  static double getResponsiveHeight(BuildContext context, {
    double phonePercent = 1.0,
    double tabletPercent = 0.9,
    double desktopPercent = 0.8,
  }) {
    final deviceType = getDeviceType(context);
    final screenHeight = MediaQuery.of(context).size.height;
    
    double percent;
    switch (deviceType) {
      case DeviceType.phone:
        percent = phonePercent;
        break;
      case DeviceType.tablet:
        percent = tabletPercent;
        break;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        percent = desktopPercent;
        break;
    }
    
    return screenHeight * percent;
  }

  /// Get responsive border radius
  static double getResponsiveBorderRadius(BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 12.0;
      case DeviceType.tablet:
        return tablet ?? 16.0;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? 20.0;
    }
  }

  /// Get responsive icon size
  static double getResponsiveIconSize(BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 24.0;
      case DeviceType.tablet:
        return tablet ?? 28.0;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? 32.0;
    }
  }

  /// Get responsive avatar size
  static double getResponsiveAvatarSize(BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 60.0;
      case DeviceType.tablet:
        return tablet ?? 80.0;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? 100.0;
    }
  }

  /// Get responsive button height
  static double getResponsiveButtonHeight(BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 36.0;
      case DeviceType.tablet:
        return tablet ?? 44.0;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? 48.0;
    }
  }

  /// Get responsive card elevation
  static double getResponsiveElevation(BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 2.0;
      case DeviceType.tablet:
        return tablet ?? 4.0;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? 8.0;
    }
  }

  /// Get responsive column count for grids
  static int getResponsiveColumnCount(BuildContext context, {
    int? phone,
    int? tablet,
    int? desktop,
  }) {
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 1;
      case DeviceType.tablet:
        return tablet ?? 2;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? 3;
    }
  }

  /// Get maximum content width for readability
  static double getMaxContentWidth(BuildContext context) {
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return double.infinity;
      case DeviceType.tablet:
        return 700.0;
      case DeviceType.desktop:
        return 900.0;
      case DeviceType.largeDesktop:
        return 1200.0;
    }
  }

  /// Get responsive aspect ratio for media
  static double getResponsiveAspectRatio(BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    final isLandscapeMode = isLandscape(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? (isLandscapeMode ? 2.0 : 16/9);
      case DeviceType.tablet:
        return tablet ?? (isLandscapeMode ? 2.5 : 16/9);
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? 21/9;
    }
  }

  /// Check if device should use compact layout
  static bool shouldUseCompactLayout(BuildContext context) {
    return getDeviceType(context) == DeviceType.phone && !isLandscape(context);
  }

  /// Check if device should show side navigation
  static bool shouldShowSideNavigation(BuildContext context) {
    final deviceType = getDeviceType(context);
    return deviceType == DeviceType.desktop || deviceType == DeviceType.largeDesktop;
  }

  /// Get responsive dialog width
  static double getResponsiveDialogWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return screenWidth * 0.9;
      case DeviceType.tablet:
        return screenWidth * 0.7;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return 600.0;
    }
  }

  /// Get responsive app bar height
  static double getResponsiveAppBarHeight(BuildContext context) {
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return kToolbarHeight;
      case DeviceType.tablet:
        return kToolbarHeight + 8;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return kToolbarHeight + 16;
    }
  }

  /// Get responsive safe area padding
  static EdgeInsets getResponsiveSafeAreaPadding(BuildContext context) {
    final safePadding = MediaQuery.of(context).padding;
    final deviceType = getDeviceType(context);
    
    // Add extra padding for larger devices
    final extraPadding = deviceType == DeviceType.desktop || 
                        deviceType == DeviceType.largeDesktop ? 16.0 : 0.0;
    
    return EdgeInsets.only(
      top: safePadding.top + extraPadding,
      bottom: safePadding.bottom + extraPadding,
      left: safePadding.left + extraPadding,
      right: safePadding.right + extraPadding,
    );
  }

  /// Get responsive text scale factor
  static double getResponsiveTextScaleFactor(BuildContext context) {
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return 1.0;
      case DeviceType.tablet:
        return 1.1;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return 1.2;
    }
  }

  /// Helper method to build responsive layouts with different widgets for different screen sizes
  static Widget buildResponsiveLayout({
    required BuildContext context,
    Widget? phone,
    Widget? tablet,
    Widget? desktop,
    Widget? fallback,
  }) {
    final deviceType = getDeviceType(context);
    
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? fallback ?? const SizedBox.shrink();
      case DeviceType.tablet:
        return tablet ?? phone ?? fallback ?? const SizedBox.shrink();
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? tablet ?? phone ?? fallback ?? const SizedBox.shrink();
    }
  }

  /// Get responsive grid delegate for GridView
  static SliverGridDelegate getResponsiveGridDelegate(BuildContext context, {
    double? childAspectRatio,
    double? crossAxisSpacing,
    double? mainAxisSpacing,
  }) {
    final columnCount = getResponsiveColumnCount(context);
    final spacing = getResponsiveSpacing(context);
    
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columnCount,
      childAspectRatio: childAspectRatio ?? 1.0,
      crossAxisSpacing: crossAxisSpacing ?? spacing,
      mainAxisSpacing: mainAxisSpacing ?? spacing,
    );
  }
}

/// Extension methods for easier responsive design
extension ResponsiveContext on BuildContext {
  ResponsiveHelper.DeviceType get deviceType => ResponsiveHelper.getDeviceType(this);
  ResponsiveHelper.ScreenSize get screenSize => ResponsiveHelper.getScreenSize(this);
  bool get isLandscape => ResponsiveHelper.isLandscape(this);
  bool get isPhone => deviceType == ResponsiveHelper.DeviceType.phone;
  bool get isTablet => deviceType == ResponsiveHelper.DeviceType.tablet;
  bool get isDesktop => deviceType == ResponsiveHelper.DeviceType.desktop || 
                       deviceType == ResponsiveHelper.DeviceType.largeDesktop;
  bool get shouldUseCompactLayout => ResponsiveHelper.shouldUseCompactLayout(this);
  bool get shouldShowSideNavigation => ResponsiveHelper.shouldShowSideNavigation(this);
  
  double responsivePadding({double? phone, double? tablet, double? desktop}) =>
      ResponsiveHelper.getResponsivePadding(this, phone: phone, tablet: tablet, desktop: desktop).left;
  
  double responsiveFontSize({double? phone, double? tablet, double? desktop}) =>
      ResponsiveHelper.getResponsiveFontSize(this, phone: phone, tablet: tablet, desktop: desktop);
  
  double responsiveSpacing({double? phone, double? tablet, double? desktop}) =>
      ResponsiveHelper.getResponsiveSpacing(this, phone: phone, tablet: tablet, desktop: desktop);
  
  double responsiveWidth({double phonePercent = 1.0, double tabletPercent = 0.8, double desktopPercent = 0.6}) =>
      ResponsiveHelper.getResponsiveWidth(this, phonePercent: phonePercent, tabletPercent: tabletPercent, desktopPercent: desktopPercent);
  
  double responsiveHeight({double phonePercent = 1.0, double tabletPercent = 0.9, double desktopPercent = 0.8}) =>
      ResponsiveHelper.getResponsiveHeight(this, phonePercent: phonePercent, tabletPercent: tabletPercent, desktopPercent: desktopPercent);
}