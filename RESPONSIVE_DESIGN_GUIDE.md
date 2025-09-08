# Responsive Design Guide

This guide explains how to implement responsive design throughout the AttendUs app to ensure optimal user experience across all device types.

## Overview

The app now includes a comprehensive responsive design system that automatically adapts layouts, typography, spacing, and UI elements based on device type and screen size.

## Device Categories

The system recognizes four main device categories:

- **Phone** (< 600px width): Compact layouts, single-column grids, bottom navigation
- **Tablet** (600-900px width): Medium layouts, 2-column grids, larger touch targets
- **Desktop** (900-1600px width): Expanded layouts, 3-column grids, side navigation
- **Large Desktop** (> 1600px width): Wide layouts, constrained content width for readability

## Key Components

### 1. ResponsiveHelper Class

The main utility class providing responsive design methods:

```dart
import 'package:attendus/Utils/responsive_helper.dart';

// Get device type
final deviceType = ResponsiveHelper.getDeviceType(context);

// Get responsive values
final padding = ResponsiveHelper.getResponsivePadding(context);
final fontSize = ResponsiveHelper.getResponsiveFontSize(context);
final spacing = ResponsiveHelper.getResponsiveSpacing(context);
```

### 2. Context Extensions

Convenient extension methods for quick responsive checks:

```dart
// Check device type
if (context.isPhone) {
  // Phone-specific layout
} else if (context.isTablet) {
  // Tablet-specific layout
} else if (context.isDesktop) {
  // Desktop-specific layout
}

// Get responsive values
final padding = context.responsivePadding();
final fontSize = context.responsiveFontSize();
```

### 3. Responsive Layout Builder

Build different layouts for different screen sizes:

```dart
ResponsiveHelper.buildResponsiveLayout(
  context: context,
  phone: _buildPhoneLayout(),
  tablet: _buildTabletLayout(),
  desktop: _buildDesktopLayout(),
)
```

## Implementation Examples

### Responsive Padding and Margins

```dart
Container(
  padding: ResponsiveHelper.getResponsivePadding(context),
  margin: ResponsiveHelper.getResponsiveMargin(context),
  child: YourWidget(),
)
```

### Responsive Typography

```dart
Text(
  'Your Text',
  style: TextStyle(
    fontSize: ResponsiveHelper.getResponsiveFontSize(
      context,
      phone: 16,
      tablet: 18,
      desktop: 20,
    ),
  ),
)
```

### Responsive Grids

```dart
GridView.builder(
  gridDelegate: ResponsiveHelper.getResponsiveGridDelegate(context),
  itemBuilder: (context, index) => YourGridItem(),
)
```

### Responsive Buttons

```dart
SizedBox(
  height: ResponsiveHelper.getResponsiveButtonHeight(context),
  child: ElevatedButton(
    child: Text('Button'),
    onPressed: () {},
  ),
)
```

### Responsive Dialogs

```dart
// For phones/tablets: Use bottom sheet
// For desktop: Use dialog
if (context.isDesktop) {
  showDialog(context: context, builder: (context) => YourDialog());
} else {
  showModalBottomSheet(context: context, builder: (context) => YourBottomSheet());
}
```

## Best Practices

### 1. Content Width Constraints

Always constrain content width on larger screens for better readability:

```dart
Container(
  constraints: BoxConstraints(
    maxWidth: ResponsiveHelper.getMaxContentWidth(context),
  ),
  child: YourContent(),
)
```

### 2. Responsive Images and Media

Use appropriate aspect ratios for different screen sizes:

```dart
AspectRatio(
  aspectRatio: ResponsiveHelper.getResponsiveAspectRatio(context),
  child: YourImage(),
)
```

### 3. Navigation Patterns

Implement appropriate navigation for each device type:

```dart
// Bottom navigation for phones/tablets
// Side navigation for desktop
if (ResponsiveHelper.shouldShowSideNavigation(context)) {
  // Show side navigation
} else {
  // Show bottom navigation
}
```

### 4. Touch Targets

Ensure touch targets are appropriately sized:

```dart
Container(
  width: ResponsiveHelper.getResponsiveIconSize(context, phone: 44, tablet: 48, desktop: 52),
  height: ResponsiveHelper.getResponsiveIconSize(context, phone: 44, tablet: 48, desktop: 52),
  child: IconButton(
    icon: Icon(Icons.menu),
    onPressed: () {},
  ),
)
```

## Common Patterns

### Profile Screen Pattern

```dart
// Avatar size adapts to screen size
Container(
  width: ResponsiveHelper.getResponsiveAvatarSize(context),
  height: ResponsiveHelper.getResponsiveAvatarSize(context),
  child: CircleAvatar(child: YourAvatar()),
)

// Action buttons adapt layout
ResponsiveHelper.buildResponsiveLayout(
  context: context,
  phone: Column(children: [FollowButton(), MessageButton()]),
  tablet: Row(children: [FollowButton(), MessageButton()]),
  desktop: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [FollowButton(), MessageButton()],
  ),
)
```

### Card Layout Pattern

```dart
Card(
  elevation: ResponsiveHelper.getResponsiveElevation(context),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(
      ResponsiveHelper.getResponsiveBorderRadius(context)
    ),
  ),
  child: Padding(
    padding: ResponsiveHelper.getResponsivePadding(context),
    child: YourCardContent(),
  ),
)
```

### Form Pattern

```dart
TextField(
  style: TextStyle(
    fontSize: ResponsiveHelper.getResponsiveFontSize(context),
  ),
  decoration: InputDecoration(
    prefixIcon: Icon(
      Icons.email,
      size: ResponsiveHelper.getResponsiveIconSize(context),
    ),
  ),
)
```

## Testing Responsive Design

### Using the Test Screen

Navigate to the `ResponsiveTestScreen` to see how different elements adapt:

```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => ResponsiveTestScreen()),
)
```

### Manual Testing

Test your responsive design on different screen sizes:

1. **Phone sizes**: 375x667 (iPhone SE), 390x844 (iPhone 12)
2. **Tablet sizes**: 768x1024 (iPad), 834x1194 (iPad Pro 11")
3. **Desktop sizes**: 1024x768, 1366x768, 1920x1080

### Flutter Inspector

Use Flutter's device preview to test different screen sizes during development.

## Migration Guide

### For Existing Code

1. **Replace static dimensions** with responsive alternatives:
   ```dart
   // Old
   padding: EdgeInsets.all(16),
   
   // New
   padding: ResponsiveHelper.getResponsivePadding(context),
   ```

2. **Update font sizes** to be responsive:
   ```dart
   // Old
   fontSize: 16,
   
   // New
   fontSize: ResponsiveHelper.getResponsiveFontSize(context),
   ```

3. **Add layout variations** for different screen sizes:
   ```dart
   // Old
   Column(children: widgets),
   
   // New
   ResponsiveHelper.buildResponsiveLayout(
     context: context,
     phone: Column(children: widgets),
     tablet: Row(children: widgets),
   )
   ```

### For New Code

Always use responsive utilities from the start:

```dart
class YourNewScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.getMaxContentWidth(context),
        ),
        padding: ResponsiveHelper.getResponsivePadding(context),
        child: ResponsiveHelper.buildResponsiveLayout(
          context: context,
          phone: _buildPhoneLayout(),
          tablet: _buildTabletLayout(),
          desktop: _buildDesktopLayout(),
        ),
      ),
    );
  }
}
```

## Performance Considerations

1. **Avoid excessive MediaQuery calls** - cache responsive values when possible
2. **Use const constructors** where possible to reduce rebuilds
3. **Consider using LayoutBuilder** for complex responsive logic
4. **Test performance** on lower-end devices

## Accessibility

Ensure responsive design maintains accessibility:

1. **Maintain minimum touch target sizes** (44px on iOS, 48px on Android)
2. **Ensure sufficient color contrast** at all screen sizes
3. **Test with screen readers** on different device types
4. **Verify keyboard navigation** works on desktop layouts

## Future Enhancements

The responsive system can be extended with:

1. **Orientation-specific layouts** for landscape/portrait modes
2. **Platform-specific adaptations** for iOS/Android/Web
3. **User preference integration** for text scaling and reduced motion
4. **Advanced breakpoint management** for specific use cases

## Support

For questions or issues with responsive design implementation:

1. Check existing responsive screens for reference patterns
2. Use the `ResponsiveTestScreen` for debugging
3. Review this guide for best practices
4. Test thoroughly across device types before deployment