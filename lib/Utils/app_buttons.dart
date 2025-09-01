import 'package:flutter/material.dart';
import 'package:attendus/Utils/colors.dart';

class AppButtons {
  static Widget button1({
    required double width,
    required double height,
    required bool buttonLoading,
    required String label,
    required double labelSize,
  }) {
    return Container(
      alignment: Alignment.center,
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppThemeColor.darkGreenColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: buttonLoading
          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
          : Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: labelSize,
                color: Colors.white,
              ),
            ),
    );
  }

  static Widget roundedButton({
    required IconData iconData,
    required Color iconColor,
    required Color backgroundColor,
  }) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(child: Icon(iconData, color: iconColor, size: 20)),
    );
  }
}
