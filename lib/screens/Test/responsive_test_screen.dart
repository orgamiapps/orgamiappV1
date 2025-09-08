import 'package:flutter/material.dart';
import 'package:attendus/Utils/responsive_helper.dart';
import 'package:attendus/Utils/colors.dart';

/// Test screen to validate responsive design across different device types
class ResponsiveTestScreen extends StatelessWidget {
  const ResponsiveTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Responsive Design Test'),
        backgroundColor: AppThemeColor.darkBlueColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: ResponsiveHelper.getResponsivePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDeviceInfo(context),
              SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
              _buildResponsiveGrid(context),
              SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
              _buildResponsiveCards(context),
              SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
              _buildResponsiveButtons(context),
              SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
              _buildResponsiveText(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceInfo(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final deviceType = ResponsiveHelper.getDeviceType(context);
    final screenCategory = ResponsiveHelper.getScreenSize(context);
    
    return Card(
      child: Padding(
        padding: ResponsiveHelper.getResponsivePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Information',
              style: TextStyle(
                fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 18, tablet: 22, desktop: 26),
                fontWeight: FontWeight.bold,
                color: AppThemeColor.darkBlueColor,
              ),
            ),
            SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
            _buildInfoRow(context, 'Screen Size', '${screenSize.width.toInt()} x ${screenSize.height.toInt()}'),
            _buildInfoRow(context, 'Device Type', deviceType.name),
            _buildInfoRow(context, 'Screen Category', screenCategory.name),
            _buildInfoRow(context, 'Orientation', context.isLandscape ? 'Landscape' : 'Portrait'),
            _buildInfoRow(context, 'Compact Layout', context.shouldUseCompactLayout ? 'Yes' : 'No'),
            _buildInfoRow(context, 'Side Navigation', context.shouldShowSideNavigation ? 'Yes' : 'No'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.getResponsiveSpacing(context, phone: 2, tablet: 4, desktop: 6)),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: ResponsiveHelper.getResponsiveFontSize(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: TextStyle(
                fontSize: ResponsiveHelper.getResponsiveFontSize(context),
                color: AppThemeColor.dullFontColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveGrid(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Responsive Grid',
          style: TextStyle(
            fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 18, tablet: 22, desktop: 26),
            fontWeight: FontWeight.bold,
            color: AppThemeColor.darkBlueColor,
          ),
        ),
        SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: ResponsiveHelper.getResponsiveGridDelegate(context),
          itemCount: 6,
          itemBuilder: (context, index) {
            return Card(
              color: AppThemeColor.darkBlueColor.withValues(alpha: 0.1),
              child: Center(
                child: Text(
                  'Item ${index + 1}',
                  style: TextStyle(
                    fontSize: ResponsiveHelper.getResponsiveFontSize(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildResponsiveCards(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Responsive Cards',
          style: TextStyle(
            fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 18, tablet: 22, desktop: 26),
            fontWeight: FontWeight.bold,
            color: AppThemeColor.darkBlueColor,
          ),
        ),
        SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
        ...List.generate(3, (index) {
          return Container(
            margin: EdgeInsets.only(bottom: ResponsiveHelper.getResponsiveSpacing(context)),
            child: Card(
              elevation: ResponsiveHelper.getResponsiveElevation(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ResponsiveHelper.getResponsiveBorderRadius(context)),
              ),
              child: Padding(
                padding: ResponsiveHelper.getResponsivePadding(context),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: ResponsiveHelper.getResponsiveAvatarSize(context, phone: 24, tablet: 32, desktop: 40),
                      backgroundColor: AppThemeColor.darkBlueColor,
                      child: Icon(
                        Icons.person,
                        size: ResponsiveHelper.getResponsiveIconSize(context),
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.getResponsiveSpacing(context)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Card Title ${index + 1}',
                            style: TextStyle(
                              fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 16, tablet: 18, desktop: 20),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 4, tablet: 6, desktop: 8)),
                          Text(
                            'This is a sample card description that adapts to different screen sizes.',
                            style: TextStyle(
                              fontSize: ResponsiveHelper.getResponsiveFontSize(context),
                              color: AppThemeColor.dullFontColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildResponsiveButtons(BuildContext context) {
    final buttonHeight = ResponsiveHelper.getResponsiveButtonHeight(context);
    final fontSize = ResponsiveHelper.getResponsiveFontSize(context);
    final borderRadius = ResponsiveHelper.getResponsiveBorderRadius(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Responsive Buttons',
          style: TextStyle(
            fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 18, tablet: 22, desktop: 26),
            fontWeight: FontWeight.bold,
            color: AppThemeColor.darkBlueColor,
          ),
        ),
        SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
        ResponsiveHelper.buildResponsiveLayout(
          context: context,
          phone: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: buttonHeight,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemeColor.darkBlueColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                  ),
                  child: Text('Primary Button', style: TextStyle(fontSize: fontSize)),
                ),
              ),
              SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
              SizedBox(
                width: double.infinity,
                height: buttonHeight,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppThemeColor.darkBlueColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                  ),
                  child: Text('Secondary Button', style: TextStyle(fontSize: fontSize)),
                ),
              ),
            ],
          ),
          tablet: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: buttonHeight,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeColor.darkBlueColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(borderRadius),
                      ),
                    ),
                    child: Text('Primary Button', style: TextStyle(fontSize: fontSize)),
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.getResponsiveSpacing(context)),
              Expanded(
                child: SizedBox(
                  height: buttonHeight,
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppThemeColor.darkBlueColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(borderRadius),
                      ),
                    ),
                    child: Text('Secondary Button', style: TextStyle(fontSize: fontSize)),
                  ),
                ),
              ),
            ],
          ),
          desktop: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: ResponsiveHelper.getResponsiveWidth(context, desktopPercent: 0.2),
                height: buttonHeight,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppThemeColor.darkBlueColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                  ),
                  child: Text('Primary Button', style: TextStyle(fontSize: fontSize)),
                ),
              ),
              SizedBox(width: ResponsiveHelper.getResponsiveSpacing(context)),
              SizedBox(
                width: ResponsiveHelper.getResponsiveWidth(context, desktopPercent: 0.2),
                height: buttonHeight,
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppThemeColor.darkBlueColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                  ),
                  child: Text('Secondary Button', style: TextStyle(fontSize: fontSize)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResponsiveText(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Responsive Typography',
          style: TextStyle(
            fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 18, tablet: 22, desktop: 26),
            fontWeight: FontWeight.bold,
            color: AppThemeColor.darkBlueColor,
          ),
        ),
        SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
        Text(
          'Heading Text',
          style: TextStyle(
            fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 20, tablet: 24, desktop: 28),
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 8, tablet: 12, desktop: 16)),
        Text(
          'Subheading Text',
          style: TextStyle(
            fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 16, tablet: 18, desktop: 20),
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 8, tablet: 12, desktop: 16)),
        Text(
          'Body text that adapts to different screen sizes. This paragraph demonstrates how text scales appropriately across phones, tablets, and desktop devices to maintain readability and visual hierarchy.',
          style: TextStyle(
            fontSize: ResponsiveHelper.getResponsiveFontSize(context),
            height: 1.5,
          ),
        ),
        SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context, phone: 8, tablet: 12, desktop: 16)),
        Text(
          'Small text for captions and secondary information.',
          style: TextStyle(
            fontSize: ResponsiveHelper.getResponsiveFontSize(context, phone: 12, tablet: 14, desktop: 16),
            color: AppThemeColor.dullFontColor,
          ),
        ),
      ],
    );
  }
}