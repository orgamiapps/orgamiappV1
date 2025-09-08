import 'package:flutter/material.dart';
import 'responsive_helper.dart';

/// Test helper for verifying responsive design across different screen sizes
class ResponsiveTestHelper {
  /// Common device screen sizes for testing
  static const Map<String, Size> testDevices = {
    // Phones
    'iPhone SE': Size(375, 667),
    'iPhone 12': Size(390, 844),
    'iPhone 12 Pro Max': Size(428, 926),
    'Samsung Galaxy S21': Size(360, 800),
    'Google Pixel 5': Size(393, 851),
    
    // Tablets
    'iPad': Size(768, 1024),
    'iPad Pro 11"': Size(834, 1194),
    'iPad Pro 12.9"': Size(1024, 1366),
    'Samsung Galaxy Tab': Size(800, 1280),
    
    // Desktop/Web
    'Small Desktop': Size(1024, 768),
    'Medium Desktop': Size(1366, 768),
    'Large Desktop': Size(1920, 1080),
    'Ultra-wide': Size(2560, 1440),
  };

  /// Test responsive values for a given screen size
  static Map<String, dynamic> testResponsiveValues(Size screenSize) {
    final context = _MockBuildContext(screenSize);
    
    return {
      'screenSize': screenSize,
      'deviceType': ResponsiveHelper.getDeviceType(context),
      'screenCategory': ResponsiveHelper.getScreenSize(context),
      'isLandscape': ResponsiveHelper.isLandscape(context),
      'shouldUseCompactLayout': ResponsiveHelper.shouldUseCompactLayout(context),
      'shouldShowSideNavigation': ResponsiveHelper.shouldShowSideNavigation(context),
      'responsivePadding': ResponsiveHelper.getResponsivePadding(context).left,
      'responsiveFontSize': ResponsiveHelper.getResponsiveFontSize(context),
      'responsiveSpacing': ResponsiveHelper.getResponsiveSpacing(context),
      'responsiveIconSize': ResponsiveHelper.getResponsiveIconSize(context),
      'responsiveAvatarSize': ResponsiveHelper.getResponsiveAvatarSize(context),
      'responsiveButtonHeight': ResponsiveHelper.getResponsiveButtonHeight(context),
      'responsiveBorderRadius': ResponsiveHelper.getResponsiveBorderRadius(context),
      'maxContentWidth': ResponsiveHelper.getMaxContentWidth(context),
      'columnCount': ResponsiveHelper.getResponsiveColumnCount(context),
    };
  }

  /// Generate a comprehensive test report for all device types
  static Map<String, Map<String, dynamic>> generateTestReport() {
    final report = <String, Map<String, dynamic>>{};
    
    for (final entry in testDevices.entries) {
      final deviceName = entry.key;
      final screenSize = entry.value;
      report[deviceName] = testResponsiveValues(screenSize);
    }
    
    return report;
  }

  /// Print a formatted test report to debug console
  static void printTestReport() {
    final report = generateTestReport();
    
    debugPrint('=== RESPONSIVE DESIGN TEST REPORT ===');
    debugPrint('');
    
    for (final entry in report.entries) {
      final deviceName = entry.key;
      final values = entry.value;
      
      debugPrint('📱 $deviceName (${values['screenSize']})');
      debugPrint('   Device Type: ${values['deviceType']}');
      debugPrint('   Screen Category: ${values['screenCategory']}');
      debugPrint('   Layout: ${values['shouldUseCompactLayout'] ? 'Compact' : 'Expanded'}');
      debugPrint('   Navigation: ${values['shouldShowSideNavigation'] ? 'Side' : 'Bottom'}');
      debugPrint('   Padding: ${values['responsivePadding']}px');
      debugPrint('   Font Size: ${values['responsiveFontSize']}px');
      debugPrint('   Icon Size: ${values['responsiveIconSize']}px');
      debugPrint('   Avatar Size: ${values['responsiveAvatarSize']}px');
      debugPrint('   Button Height: ${values['responsiveButtonHeight']}px');
      debugPrint('   Border Radius: ${values['responsiveBorderRadius']}px');
      debugPrint('   Max Content Width: ${values['maxContentWidth']}px');
      debugPrint('   Grid Columns: ${values['columnCount']}');
      debugPrint('');
    }
    
    debugPrint('=== END REPORT ===');
  }

  /// Verify that responsive values are within expected ranges
  static List<String> validateResponsiveValues() {
    final issues = <String>[];
    final report = generateTestReport();
    
    for (final entry in report.entries) {
      final deviceName = entry.key;
      final values = entry.value;
      
      // Validate font sizes are reasonable
      final fontSize = values['responsiveFontSize'] as double;
      if (fontSize < 12.0 || fontSize > 24.0) {
        issues.add('$deviceName: Font size $fontSize is outside reasonable range (12-24px)');
      }
      
      // Validate padding is reasonable
      final padding = values['responsivePadding'] as double;
      if (padding < 8.0 || padding > 48.0) {
        issues.add('$deviceName: Padding $padding is outside reasonable range (8-48px)');
      }
      
      // Validate icon sizes are reasonable
      final iconSize = values['responsiveIconSize'] as double;
      if (iconSize < 16.0 || iconSize > 48.0) {
        issues.add('$deviceName: Icon size $iconSize is outside reasonable range (16-48px)');
      }
      
      // Validate button heights are reasonable
      final buttonHeight = values['responsiveButtonHeight'] as double;
      if (buttonHeight < 32.0 || buttonHeight > 64.0) {
        issues.add('$deviceName: Button height $buttonHeight is outside reasonable range (32-64px)');
      }
      
      // Validate grid columns make sense
      final columns = values['columnCount'] as int;
      final deviceType = values['deviceType'] as ResponsiveHelper.DeviceType;
      if (deviceType == ResponsiveHelper.DeviceType.phone && columns > 2) {
        issues.add('$deviceName: Too many grid columns ($columns) for phone');
      }
      if (deviceType == ResponsiveHelper.DeviceType.desktop && columns < 2) {
        issues.add('$deviceName: Too few grid columns ($columns) for desktop');
      }
    }
    
    return issues;
  }
}

/// Mock BuildContext for testing responsive values
class _MockBuildContext implements BuildContext {
  final Size _screenSize;
  
  _MockBuildContext(this._screenSize);

  @override
  Size get size => _screenSize;

  @override
  MediaQueryData get mediaQuery => MediaQueryData(
    size: _screenSize,
    devicePixelRatio: 2.0,
    padding: const EdgeInsets.all(0),
  );

  // Implement other required BuildContext methods with minimal implementations
  @override
  Widget get widget => throw UnimplementedError();

  @override
  BuildOwner? get owner => throw UnimplementedError();

  @override
  InheritedWidget dependOnInheritedElement(InheritedElement ancestor, {Object? aspect}) {
    throw UnimplementedError();
  }

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>({Object? aspect}) {
    if (T == MediaQuery) {
      return MediaQuery(data: mediaQuery, child: const SizedBox()) as T;
    }
    throw UnimplementedError();
  }

  @override
  DiagnosticsNode describeElement(String name, {DiagnosticsTreeStyle style = DiagnosticsTreeStyle.errorProperty}) {
    throw UnimplementedError();
  }

  @override
  List<DiagnosticsNode> describeMissingAncestor({required Type expectedAncestorType}) {
    throw UnimplementedError();
  }

  @override
  DiagnosticsNode describeOwnershipChain(String name) {
    throw UnimplementedError();
  }

  @override
  DiagnosticsNode describeWidget(String name, {DiagnosticsTreeStyle style = DiagnosticsTreeStyle.errorProperty}) {
    throw UnimplementedError();
  }

  @override
  void dispatchNotification(Notification notification) {
    throw UnimplementedError();
  }

  @override
  T? findAncestorRenderObjectOfType<T extends RenderObject>() {
    throw UnimplementedError();
  }

  @override
  T? findAncestorStateOfType<T extends State<StatefulWidget>>() {
    throw UnimplementedError();
  }

  @override
  T? findAncestorWidgetOfExactType<T extends Widget>() {
    throw UnimplementedError();
  }

  @override
  RenderObject? findRenderObject() {
    throw UnimplementedError();
  }

  @override
  T? findRootAncestorStateOfType<T extends State<StatefulWidget>>() {
    throw UnimplementedError();
  }

  @override
  InheritedElement? getElementForInheritedWidgetOfExactType<T extends InheritedWidget>() {
    throw UnimplementedError();
  }

  @override
  void visitAncestorElements(bool Function(Element element) visitor) {
    throw UnimplementedError();
  }

  @override
  void visitChildElements(ElementVisitor visitor) {
    throw UnimplementedError();
  }

  @override
  bool get debugDoingBuild => false;

  @override
  bool get mounted => true;
}