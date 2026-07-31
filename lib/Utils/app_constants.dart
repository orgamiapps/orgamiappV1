import 'package:intl/intl.dart';

class AppConstants {
  static const appName = 'Attendus';
  static const appVersion = '1.0.0';

  static const privacyPolicyUrl = 'https://attendus.app/privacy';
  static const termsConditionsUrl = 'https://attendus.app/terms';

  static const companyEmail = 'support@attendus.app';
  static const supportUrl = 'https://attendus.app/support';
  static const cloudFunctionsRegion = 'us-central1';

  static DateFormat dateFormat = DateFormat("dd MMM yyyy, hh:mm a");
  static DateFormat dateFormat1 = DateFormat("dd MMM yyyy");
  static DateFormat dateFormat2 = DateFormat("dd-MM-yyyy");

  // Google Places API key used for client-side autocomplete in signup.
  // NOTE: Keep this key restricted to Places APIs only. This mirrors the key
  // present in AndroidManifest for Maps SDK usage.
  static const String googlePlacesApiKey =
      'AIzaSyAf1t5cToh1UoF7R52vTSJxMajw8CvmVUA';

  // Browser-exposed keys are expected to be HTTP-referrer restricted. Supply
  // this with --dart-define=GOOGLE_MAPS_WEB_API_KEY=... for web builds.
  static const String googleMapsWebApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_WEB_API_KEY',
    defaultValue: '',
  );

  // Public web/deep-link configuration.
  static const String publicWebDomain = 'https://attendus.app';
  static const String dynamicLinksDomain = 'https://attendus.app';
  static const String androidPackageName = 'com.stormdeve.orgami';
  static const String iosBundleId = 'com.stormdeve.orgami';
  static const String stripeReturnUrl = 'attendus://callback';
  static const String stripeMerchantDisplayName = 'Attendus';
  static const String applePayMerchantIdentifier = 'merchant.app.attendus';

  // Feature flags
  // Apple Sign-In is hidden until the Apple Developer Service ID, callback URL,
  // and Firebase provider settings are configured for AttendUs.
  static const bool enableAppleSignIn = false;

  // Web App Check is intentionally opt-in until a real reCAPTCHA v3 key is
  // configured in Firebase Console for attendus.app.
  static const bool enableWebAppCheck = bool.fromEnvironment(
    'ATTENDUS_ENABLE_WEB_APP_CHECK',
    defaultValue: false,
  );
  static const String appCheckWebRecaptchaSiteKey = String.fromEnvironment(
    'ATTENDUS_RECAPTCHA_V3_SITE_KEY',
    defaultValue: '',
  );
  static const String appleServiceId = String.fromEnvironment(
    'ATTENDUS_APPLE_SERVICE_ID',
    defaultValue: '',
  );
  static const String appleRedirectUrl = String.fromEnvironment(
    'ATTENDUS_APPLE_REDIRECT_URL',
    defaultValue: '',
  );

  static Uri buildInviteUri(String eventId) {
    return Uri.parse('$publicWebDomain/invite?eventId=$eventId');
  }

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
