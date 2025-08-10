import 'package:intl/intl.dart';

class AppConstants {
  static const appName = 'Orgami';
  static const appVersion = '1.0.0';

  static const privacyPolicyUrl = 'https://myorgami.com/privacy-policy';
  static const termsConditionsUrl = 'https://myorgami.com/terms-conditions/';

  static const companyEmail = 'orgami@myorgami.com';

  static DateFormat dateFormat = DateFormat("dd MMM yyyy, hh:mm a");
  static DateFormat dateFormat1 = DateFormat("dd MMM yyyy");
  static DateFormat dateFormat2 = DateFormat("dd-MM-yyyy");

  // Google Places API key used for client-side autocomplete in signup.
  // NOTE: Keep this key restricted to Places APIs only. This mirrors the key
  // present in AndroidManifest for Maps SDK usage.
  static const String googlePlacesApiKey =
      'AIzaSyAf1t5cToh1UoF7R52vTSJxMajw8CvmVUA';

  static String getMilesSliderLabel(double value) {
    switch (value.round()) {
      case 0:
        return '0 miles';
      case 1:
        return '1 miles';
      case 166:
        return '167 miles';
      case 333:
        return '333 miles';
      case 500:
        return '500 miles';
      case 667:
        return '667 miles';
      case 833:
        return '833 miles';
      case 1000:
        return '1000 miles';
      default:
        return '${value.round()} miles';
    }
  }
}
