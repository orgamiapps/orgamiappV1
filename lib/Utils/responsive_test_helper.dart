import 'package:flutter/material.dart';
import 'package:attendus/Utils/responsive_helper.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/dimensions.dart';

class ResponsiveTestHelper {
  static Widget buildTestCard(BuildContext context, String title, Widget content) {
    return Container(
      margin: ResponsiveHelper.getResponsiveMargin(context),
      padding: ResponsiveHelper.getResponsivePadding(context),
      decoration: BoxDecoration(
        color: AppThemeColor.pureWhiteColor,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.getResponsiveBorderRadius(context),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: ResponsiveHelper.getResponsiveElevation(context),
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: ResponsiveHelper.getResponsiveFontSize(
                context,
                phone: 18,
                tablet: 20,
                desktop: 22,
              ),
              fontWeight: FontWeight.bold,
              color: AppThemeColor.darkBlueColor,
            ),
          ),
          SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
          content,
        ],
      ),
    );
  }

  static Widget buildDeviceInfo(BuildContext context) {
    final deviceType = ResponsiveHelper.getDeviceType(context);
    final screenSize = MediaQuery.of(context).size;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Device Type: ${deviceType.name}'),
        Text('Screen Width: ${screenSize.width.toStringAsFixed(1)}px'),
        Text('Screen Height: ${screenSize.height.toStringAsFixed(1)}px'),
        Text('Is Phone: ${context.isPhone}'),
        Text('Is Tablet: ${context.isTablet}'),
        Text('Is Desktop: ${context.isDesktop}'),
      ],
    );
  }

  static Widget buildResponsiveValues(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Font Size: ${ResponsiveHelper.getResponsiveFontSize(context)}'),
        Text('Padding: ${ResponsiveHelper.getResponsivePadding(context)}'),
        Text('Spacing: ${ResponsiveHelper.getResponsiveSpacing(context)}'),
        Text('Button Height: ${ResponsiveHelper.getResponsiveButtonHeight(context)}'),
        Text('Icon Size: ${ResponsiveHelper.getResponsiveIconSize(context)}'),
        Text('Avatar Size: ${ResponsiveHelper.getResponsiveAvatarSize(context)}'),
        Text('Border Radius: ${ResponsiveHelper.getResponsiveBorderRadius(context)}'),
        Text('Elevation: ${ResponsiveHelper.getResponsiveElevation(context)}'),
      ],
    );
  }

  static Widget buildSampleButton(BuildContext context) {
    return SizedBox(
      height: ResponsiveHelper.getResponsiveButtonHeight(context),
      child: ElevatedButton.icon(
        onPressed: () {},
        icon: Icon(
          Icons.touch_app,
          size: ResponsiveHelper.getResponsiveIconSize(context),
        ),
        label: Text(
          'Sample Button',
          style: TextStyle(
            fontSize: ResponsiveHelper.getResponsiveFontSize(context),
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppThemeColor.darkBlueColor,
          foregroundColor: AppThemeColor.pureWhiteColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              ResponsiveHelper.getResponsiveBorderRadius(context),
            ),
          ),
        ),
      ),
    );
  }

  static Widget buildSampleAvatar(BuildContext context) {
    final avatarSize = ResponsiveHelper.getResponsiveAvatarSize(context);
    return Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppThemeColor.darkBlueColor.withOpacity(0.1),
        border: Border.all(
          color: AppThemeColor.darkBlueColor,
          width: 2,
        ),
      ),
      child: Icon(
        Icons.person,
        size: avatarSize * 0.5,
        color: AppThemeColor.darkBlueColor,
      ),
    );
  }

  static Widget buildGridExample(BuildContext context) {
    return SizedBox(
      height: 200,
      child: GridView.builder(
        gridDelegate: ResponsiveHelper.getResponsiveGridDelegate(context),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: AppThemeColor.darkBlueColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(
                ResponsiveHelper.getResponsiveBorderRadius(context),
              ),
            ),
            child: Center(
              child: Text(
                'Item ${index + 1}',
                style: TextStyle(
                  fontSize: ResponsiveHelper.getResponsiveFontSize(context),
                  color: AppThemeColor.darkBlueColor,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}