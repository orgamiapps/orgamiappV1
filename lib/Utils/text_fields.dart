import 'package:flutter/material.dart';

import 'Colors.dart';
import 'dimensions.dart';

class AppTextFields {
  // static Widget TextField1({
  //   required String hintText,
  //   required String titleText,
  //   required Widget icon,
  //   required double width,
  //   required bool password,
  //   required bool passwordVisible,
  //   void Function(String?)? onSaved,
  //   Function? onEyeTap,
  //   String? Function(String?)? validator,
  // }) {
  //   return Stack(
  //     children: [
  //       Container(
  //         width: width,
  //         decoration: BoxDecoration(
  //           border: Border.all(
  //             color: AppThemeColor.borderColor,
  //             width: 0.8,
  //           ),
  //           borderRadius: BorderRadius.circular(10),
  //         ),
  //         padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
  //         margin: const EdgeInsets.symmetric(vertical: 11),
  //         child: Row(
  //           children: [
  //             icon,
  //             const SizedBox(
  //               width: 15,
  //             ),
  //             Expanded(
  //               child: TextFormField(
  //                 onSaved: onSaved,
  //                 obscureText: passwordVisible,
  //                 validator: validator,
  //                 decoration: InputDecoration(
  //                   hintText: hintText,
  //                   hintStyle: const TextStyle(
  //                     color: AppThemeColor.dullWhiteColor,
  //                   ),
  //                   border: InputBorder.none,
  //                   suffixIcon: password
  //                       ? GestureDetector(
  //                           onTap: () {
  //                             if (onEyeTap != null) {
  //                               onEyeTap();
  //                             }
  //                           },
  //                           child: Icon(
  //                             !passwordVisible
  //                                 ? Icons.visibility_off
  //                                 : Icons.visibility,
  //                             color: AppThemeColor.darkBlueColor,
  //                           ),
  //                         )
  //                       : const SizedBox(),
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //       Container(
  //         decoration: const BoxDecoration(color: AppThemeColor.backGroundColor),
  //         margin: const EdgeInsets.only(left: 20),
  //         padding: const EdgeInsets.symmetric(horizontal: 5),
  //         child: Text(
  //           titleText,
  //           style: const TextStyle(
  //             color: AppThemeColor.pureBlackColor,
  //             fontSize: Dimensions.fontSizeDefault,
  //           ),
  //         ),
  //       ),
  //     ],
  //   );
  // }

  static Widget textField2({
    required String hintText,
    required String titleText,
    required double width,
    int? maxLines = 1,
    TextEditingController? controller,
    void Function(String?)? onSaved,
    bool? enabled,
    String? Function(String?)? validator,
  }) {
    return Stack(
      children: [
        Container(
          width: width,
          decoration: BoxDecoration(
            border: Border.all(color: AppThemeColor.borderColor, width: 0.8),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          margin: const EdgeInsets.symmetric(vertical: 11),
          child: TextFormField(
            controller: controller,
            onSaved: onSaved,
            enabled: enabled,
            validator: validator,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: AppThemeColor.dullWhiteColor),
              border: InputBorder.none,
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(color: AppThemeColor.backGroundColor),
          margin: const EdgeInsets.only(left: 20),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Text(
            titleText,
            style: const TextStyle(
              color: AppThemeColor.pureBlackColor,
              fontSize: Dimensions.fontSizeDefault,
            ),
          ),
        ),
      ],
    );
  }

  //
  // static Widget TextFieldForTagInfo({
  //   required String hintText,
  //   required String titleText,
  //   required double width,
  //   int? maxLines = 1,
  //   void Function(String?)? onSaved,
  //   String? Function(String?)? validator,
  //   required TextInputType keyboardType,
  // }) {
  //   return Stack(
  //     children: [
  //       Container(
  //         width: width,
  //         decoration: BoxDecoration(
  //           border: Border.all(
  //             color: AppThemeColor.borderColor,
  //             width: 0.8,
  //           ),
  //           borderRadius: BorderRadius.circular(10),
  //         ),
  //         padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
  //         margin: const EdgeInsets.symmetric(vertical: 11),
  //         child: TextFormField(
  //           onSaved: onSaved,
  //           validator: validator,
  //           maxLines: maxLines,
  //           keyboardType: keyboardType,
  //           decoration: InputDecoration(
  //             hintText: hintText,
  //             hintStyle: const TextStyle(
  //               color: AppThemeColor.dullWhiteColor,
  //             ),
  //             border: InputBorder.none,
  //           ),
  //         ),
  //       ),
  //       Container(
  //         decoration: const BoxDecoration(color: AppThemeColor.backGroundColor),
  //         margin: const EdgeInsets.only(left: 20),
  //         padding: const EdgeInsets.symmetric(horizontal: 5),
  //         child: Text(
  //           titleText,
  //           style: const TextStyle(
  //             color: AppThemeColor.pureBlackColor,
  //             fontSize: Dimensions.fontSizeDefault,
  //           ),
  //         ),
  //       ),
  //     ],
  //   );
  // }
}
