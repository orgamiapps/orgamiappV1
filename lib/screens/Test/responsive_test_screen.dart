import 'package:flutter/material.dart';
import 'package:attendus/Utils/responsive_helper.dart';
import 'package:attendus/Utils/responsive_test_helper.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/dimensions.dart';

class ResponsiveTestScreen extends StatelessWidget {
  const ResponsiveTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFC),
      appBar: AppBar(
        title: const Text('Responsive Design Test'),
        backgroundColor: AppThemeColor.darkBlueColor,
        foregroundColor: AppThemeColor.pureWhiteColor,
        elevation: 0,
      ),
      body: Container(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.getMaxContentWidth(context),
        ),
        child: SingleChildScrollView(
          padding: ResponsiveHelper.getResponsivePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device Information
              ResponsiveTestHelper.buildTestCard(
                context,
                'Device Information',
                ResponsiveTestHelper.buildDeviceInfo(context),
              ),
              
              SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
              
              // Responsive Values
              ResponsiveTestHelper.buildTestCard(
                context,
                'Responsive Values',
                ResponsiveTestHelper.buildResponsiveValues(context),
              ),
              
              SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
              
              // Layout Examples
              ResponsiveTestHelper.buildTestCard(
                context,
                'Layout Examples',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Responsive Layout:'),
                    SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
                    ResponsiveHelper.buildResponsiveLayout(
                      context: context,
                      phone: _buildPhoneLayout(context),
                      tablet: _buildTabletLayout(context),
                      desktop: _buildDesktopLayout(context),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
              
              // Button Examples
              ResponsiveTestHelper.buildTestCard(
                context,
                'Button Examples',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ResponsiveTestHelper.buildSampleButton(context),
                    SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {},
                            style: OutlinedButton.styleFrom(
                              minimumSize: Size(
                                0,
                                ResponsiveHelper.getResponsiveButtonHeight(context),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  ResponsiveHelper.getResponsiveBorderRadius(context),
                                ),
                              ),
                            ),
                            child: Text(
                              'Outlined',
                              style: TextStyle(
                                fontSize: ResponsiveHelper.getResponsiveFontSize(context),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.getResponsiveSpacing(context)),
                        Expanded(
                          child: TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              minimumSize: Size(
                                0,
                                ResponsiveHelper.getResponsiveButtonHeight(context),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  ResponsiveHelper.getResponsiveBorderRadius(context),
                                ),
                              ),
                            ),
                            child: Text(
                              'Text Button',
                              style: TextStyle(
                                fontSize: ResponsiveHelper.getResponsiveFontSize(context),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
              
              // Avatar Examples
              ResponsiveTestHelper.buildTestCard(
                context,
                'Avatar Examples',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ResponsiveTestHelper.buildSampleAvatar(context),
                        SizedBox(width: ResponsiveHelper.getResponsiveSpacing(context)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'User Name',
                              style: TextStyle(
                                fontSize: ResponsiveHelper.getResponsiveFontSize(
                                  context,
                                  phone: 16,
                                  tablet: 18,
                                  desktop: 20,
                                ),
                                fontWeight: FontWeight.bold,
                                color: AppThemeColor.darkBlueColor,
                              ),
                            ),
                            Text(
                              '@username',
                              style: TextStyle(
                                fontSize: ResponsiveHelper.getResponsiveFontSize(
                                  context,
                                  phone: 14,
                                  tablet: 16,
                                  desktop: 18,
                                ),
                                color: AppThemeColor.dullFontColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
              
              // Grid Examples
              ResponsiveTestHelper.buildTestCard(
                context,
                'Grid Examples',
                ResponsiveTestHelper.buildGridExample(context),
              ),
              
              SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context)),
              
              // Typography Examples
              ResponsiveTestHelper.buildTestCard(
                context,
                'Typography Examples',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Heading 1',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getResponsiveFontSize(
                          context,
                          phone: 24,
                          tablet: 28,
                          desktop: 32,
                        ),
                        fontWeight: FontWeight.bold,
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context) / 2),
                    Text(
                      'Heading 2',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getResponsiveFontSize(
                          context,
                          phone: 20,
                          tablet: 24,
                          desktop: 28,
                        ),
                        fontWeight: FontWeight.w600,
                        color: AppThemeColor.darkBlueColor,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context) / 2),
                    Text(
                      'Body Text - This is a sample paragraph to demonstrate responsive typography. The font size adapts based on the device type and screen size.',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getResponsiveFontSize(context),
                        color: AppThemeColor.darkFontColor,
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.getResponsiveSpacing(context) / 2),
                    Text(
                      'Caption Text',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getResponsiveFontSize(
                          context,
                          phone: 12,
                          tablet: 14,
                          desktop: 16,
                        ),
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
  }
  
  Widget _buildPhoneLayout(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColor.darkBlueColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        children: [
          Icon(Icons.phone_android, size: 32),
          SizedBox(height: 8),
          Text('Phone Layout'),
          Text('Single column, compact spacing'),
        ],
      ),
    );
  }
  
  Widget _buildTabletLayout(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppThemeColor.darkBlueColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.tablet, size: 36),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tablet Layout'),
                Text('Two columns, medium spacing'),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDesktopLayout(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppThemeColor.darkBlueColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.desktop_mac, size: 40),
          SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Desktop Layout'),
                Text('Three columns, expanded spacing'),
              ],
            ),
          ),
          Icon(Icons.keyboard_arrow_right, size: 24),
        ],
      ),
    );
  }
}