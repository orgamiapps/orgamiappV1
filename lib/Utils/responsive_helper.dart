import 'package:flutter/material.dart';

enum DeviceType { phone, tablet, desktop, largeDesktop }

class ResponsiveHelper {
  // Device type breakpoints
  static const double phoneBreakpoint = 600;
  static const double tabletBreakpoint = 900;
  static const double desktopBreakpoint = 1600;

  // Get device type based on screen width
  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < phoneBreakpoint) {
      return DeviceType.phone;
    } else if (width < tabletBreakpoint) {
      return DeviceType.tablet;
    } else if (width < desktopBreakpoint) {
      return DeviceType.desktop;
    } else {
      return DeviceType.largeDesktop;
    }
  }

  // Check if device is phone
  static bool isPhone(BuildContext context) {
    return getDeviceType(context) == DeviceType.phone;
  }

  // Check if device is tablet
  static bool isTablet(BuildContext context) {
    return getDeviceType(context) == DeviceType.tablet;
  }

  // Check if device is desktop
  static bool isDesktop(BuildContext context) {
    final deviceType = getDeviceType(context);
    return deviceType == DeviceType.desktop ||
        deviceType == DeviceType.largeDesktop;
  }

  // Get responsive padding
  static EdgeInsets getResponsivePadding(
    BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return EdgeInsets.all(phone ?? 16);
      case DeviceType.tablet:
        return EdgeInsets.all(tablet ?? phone ?? 20);
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return EdgeInsets.all(desktop ?? tablet ?? phone ?? 24);
    }
  }

  // Get responsive margin
  static EdgeInsets getResponsiveMargin(
    BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return EdgeInsets.all(phone ?? 8);
      case DeviceType.tablet:
        return EdgeInsets.all(tablet ?? phone ?? 12);
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return EdgeInsets.all(desktop ?? tablet ?? phone ?? 16);
    }
  }

  // Get responsive font size
  static double getResponsiveFontSize(
    BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 16;
      case DeviceType.tablet:
        return tablet ?? phone ?? 18;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? tablet ?? phone ?? 20;
    }
  }

  // Get responsive spacing
  static double getResponsiveSpacing(
    BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 8;
      case DeviceType.tablet:
        return tablet ?? phone ?? 12;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? tablet ?? phone ?? 16;
    }
  }

  // Get responsive button height
  static double getResponsiveButtonHeight(
    BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 48;
      case DeviceType.tablet:
        return tablet ?? phone ?? 52;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? tablet ?? phone ?? 56;
    }
  }

  // Get responsive icon size
  static double getResponsiveIconSize(
    BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 24;
      case DeviceType.tablet:
        return tablet ?? phone ?? 28;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? tablet ?? phone ?? 32;
    }
  }

  // Get responsive avatar size
  static double getResponsiveAvatarSize(
    BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 80;
      case DeviceType.tablet:
        return tablet ?? phone ?? 100;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? tablet ?? phone ?? 120;
    }
  }

  // Get responsive border radius
  static double getResponsiveBorderRadius(
    BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 8;
      case DeviceType.tablet:
        return tablet ?? phone ?? 12;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? tablet ?? phone ?? 16;
    }
  }

  // Get responsive elevation
  static double getResponsiveElevation(
    BuildContext context, {
    double? phone,
    double? tablet,
    double? desktop,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return phone ?? 2;
      case DeviceType.tablet:
        return tablet ?? phone ?? 4;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? tablet ?? phone ?? 6;
    }
  }

  // Get responsive grid delegate
  static SliverGridDelegate getResponsiveGridDelegate(
    BuildContext context, {
    double? childAspectRatio,
    int? phoneCrossAxisCount,
    int? tabletCrossAxisCount,
    int? desktopCrossAxisCount,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: phoneCrossAxisCount ?? 1,
          childAspectRatio: childAspectRatio ?? 1.5,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        );
      case DeviceType.tablet:
        return SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: tabletCrossAxisCount ?? phoneCrossAxisCount ?? 2,
          childAspectRatio: childAspectRatio ?? 1.5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        );
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:
              desktopCrossAxisCount ??
              tabletCrossAxisCount ??
              phoneCrossAxisCount ??
              3,
          childAspectRatio: childAspectRatio ?? 1.5,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        );
    }
  }

  // Get responsive width
  static double getResponsiveWidth(
    BuildContext context, {
    double? phonePercent,
    double? tabletPercent,
    double? desktopPercent,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final deviceType = getDeviceType(context);

    switch (deviceType) {
      case DeviceType.phone:
        return screenWidth * (phonePercent ?? 1.0);
      case DeviceType.tablet:
        return screenWidth * (tabletPercent ?? phonePercent ?? 1.0);
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return screenWidth *
            (desktopPercent ?? tabletPercent ?? phonePercent ?? 1.0);
    }
  }

  // Get responsive height
  static double getResponsiveHeight(
    BuildContext context, {
    double? phonePercent,
    double? tabletPercent,
    double? desktopPercent,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;
    final deviceType = getDeviceType(context);

    switch (deviceType) {
      case DeviceType.phone:
        return screenHeight * (phonePercent ?? 1.0);
      case DeviceType.tablet:
        return screenHeight * (tabletPercent ?? phonePercent ?? 1.0);
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return screenHeight *
            (desktopPercent ?? tabletPercent ?? phonePercent ?? 1.0);
    }
  }

  // Get responsive dialog width
  static double getResponsiveDialogWidth(BuildContext context) {
    final deviceType = getDeviceType(context);
    final screenWidth = MediaQuery.of(context).size.width;

    switch (deviceType) {
      case DeviceType.phone:
        return screenWidth * 0.9;
      case DeviceType.tablet:
        return screenWidth * 0.7;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return 600;
    }
  }

  // Get max content width for large screens
  static double getMaxContentWidth(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
      case DeviceType.tablet:
        return double.infinity;
      case DeviceType.desktop:
        return 1200;
      case DeviceType.largeDesktop:
        return 1400;
    }
  }

  // Get responsive aspect ratio
  static double getResponsiveAspectRatio(BuildContext context) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return 16 / 9;
      case DeviceType.tablet:
        return 4 / 3;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return 21 / 9;
    }
  }

  // Check if should show side navigation
  static bool shouldShowSideNavigation(BuildContext context) {
    return isDesktop(context);
  }

  // Build responsive layout
  static Widget buildResponsiveLayout({
    required BuildContext context,
    required Widget phone,
    Widget? tablet,
    Widget? desktop,
  }) {
    final deviceType = getDeviceType(context);
    switch (deviceType) {
      case DeviceType.phone:
        return phone;
      case DeviceType.tablet:
        return tablet ?? phone;
      case DeviceType.desktop:
      case DeviceType.largeDesktop:
        return desktop ?? tablet ?? phone;
    }
  }
}

// Extension methods for convenient access
extension ResponsiveContext on BuildContext {
  DeviceType get deviceType => ResponsiveHelper.getDeviceType(this);

  bool get isPhone => ResponsiveHelper.isPhone(this);
  bool get isTablet => ResponsiveHelper.isTablet(this);
  bool get isDesktop => ResponsiveHelper.isDesktop(this);

  EdgeInsets responsivePadding({
    double? phone,
    double? tablet,
    double? desktop,
  }) => ResponsiveHelper.getResponsivePadding(
    this,
    phone: phone,
    tablet: tablet,
    desktop: desktop,
  );
  EdgeInsets responsiveMargin({
    double? phone,
    double? tablet,
    double? desktop,
  }) => ResponsiveHelper.getResponsiveMargin(
    this,
    phone: phone,
    tablet: tablet,
    desktop: desktop,
  );
  double responsiveFontSize({double? phone, double? tablet, double? desktop}) =>
      ResponsiveHelper.getResponsiveFontSize(
        this,
        phone: phone,
        tablet: tablet,
        desktop: desktop,
      );
  double responsiveSpacing({double? phone, double? tablet, double? desktop}) =>
      ResponsiveHelper.getResponsiveSpacing(
        this,
        phone: phone,
        tablet: tablet,
        desktop: desktop,
      );
  double responsiveButtonHeight({
    double? phone,
    double? tablet,
    double? desktop,
  }) => ResponsiveHelper.getResponsiveButtonHeight(
    this,
    phone: phone,
    tablet: tablet,
    desktop: desktop,
  );
  double responsiveIconSize({double? phone, double? tablet, double? desktop}) =>
      ResponsiveHelper.getResponsiveIconSize(
        this,
        phone: phone,
        tablet: tablet,
        desktop: desktop,
      );
  double responsiveAvatarSize({
    double? phone,
    double? tablet,
    double? desktop,
  }) => ResponsiveHelper.getResponsiveAvatarSize(
    this,
    phone: phone,
    tablet: tablet,
    desktop: desktop,
  );
  double responsiveBorderRadius({
    double? phone,
    double? tablet,
    double? desktop,
  }) => ResponsiveHelper.getResponsiveBorderRadius(
    this,
    phone: phone,
    tablet: tablet,
    desktop: desktop,
  );
  double responsiveElevation({
    double? phone,
    double? tablet,
    double? desktop,
  }) => ResponsiveHelper.getResponsiveElevation(
    this,
    phone: phone,
    tablet: tablet,
    desktop: desktop,
  );
  double maxContentWidth() => ResponsiveHelper.getMaxContentWidth(this);
  double responsiveAspectRatio() =>
      ResponsiveHelper.getResponsiveAspectRatio(this);
  bool shouldShowSideNavigation() =>
      ResponsiveHelper.shouldShowSideNavigation(this);
}
