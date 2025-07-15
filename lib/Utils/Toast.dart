import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import 'Colors.dart';

class ShowToast {
  // void showSnackBar({required BuildContext context, required String msg}) {
  //   var snackBar = SnackBar(content: Text(msg));
  //   ScaffoldMessenger.of(context).showSnackBar(snackBar);
  // }

  void showNormalToast({required String msg}) {
    Fluttertoast.showToast(
        msg: msg,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
//          timeInSecForIos: 1,
        backgroundColor: const Color(0xff666666),
        textColor: AppThemeColor.pureWhiteColor,
        fontSize: 16.0);
  }

  void showLongToast({required String msg}) {
    Fluttertoast.showToast(
        msg: msg,
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
//          timeInSecForIos: 1,
        backgroundColor: const Color(0xff666666),
        textColor: AppThemeColor.pureWhiteColor,
        fontSize: 16.0);
  }

  void showSnackBar(String content, BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(content),
          duration: const Duration(seconds: 1),
        ),
      );
  }
}
