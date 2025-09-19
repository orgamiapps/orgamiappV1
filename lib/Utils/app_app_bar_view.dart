import 'package:flutter/material.dart';
import 'package:attendus/Utils/app_buttons.dart';
import 'package:attendus/Utils/colors.dart';
import 'package:attendus/Utils/dimensions.dart';

class AppAppBarView {
  static Widget appBarView({
    required BuildContext context,
    required String title,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            child: AppButtons.roundedButton(
              iconData: Icons.arrow_back_ios_rounded,
              iconColor: AppThemeColor.pureWhiteColor,
              backgroundColor: AppThemeColor.primaryIndigo,
            ),
          ),
          const SizedBox(width: 15),
          Text(
            title,
            style: const TextStyle(
              color: AppThemeColor.darkBlueColor,
              fontSize: Dimensions.paddingSizeLarge,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static Widget appBarWithOnlyBackButton({
    required BuildContext context,
    Color? backButtonColor,
    Color? iconColor,
  }) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 8.0),
        child: InkWell(
          onTap: () => Navigator.pop(context),
          child: AppButtons.roundedButton(
            iconData: Icons.arrow_back_ios_rounded,
            iconColor: iconColor ?? AppThemeColor.pureWhiteColor,
            backgroundColor: backButtonColor ?? AppThemeColor.primaryIndigo,
          ),
        ),
      ),
    );
  }
}
