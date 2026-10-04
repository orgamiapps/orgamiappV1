import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:attendus/firebase_options.dart';

/// Public links belong to the same environment as the records they identify.
class PublicLinkConfiguration {
  const PublicLinkConfiguration._(this.canonicalOrigin, this.acceptedOrigins);

  final String canonicalOrigin;
  final Set<String> acceptedOrigins;

  static const _production = PublicLinkConfiguration._('https://attendus.app', {
    'https://attendus.app',
  });
  static const _staging =
      PublicLinkConfiguration._('https://attendus-staging.web.app', {
        'https://attendus-staging.web.app',
        'https://attendus-staging.firebaseapp.com',
      });

  factory PublicLinkConfiguration.forEnvironment(
    String environment, {
    String emulatorPublicOrigin = 'http://127.0.0.1:4173',
    bool debug = false,
  }) {
    switch (environment) {
      case 'production':
        return _production;
      case 'staging':
        return _staging;
      case 'emulator':
        final uri = Uri.tryParse(emulatorPublicOrigin);
        if (!debug ||
            uri == null ||
            uri.scheme != 'http' ||
            !{'127.0.0.1', 'localhost', '::1', '[::1]'}.contains(uri.host) ||
            uri.userInfo.isNotEmpty ||
            (uri.path.isNotEmpty && uri.path != '/') ||
            uri.hasQuery ||
            uri.hasFragment ||
            uri.port < 1 ||
            uri.port > 65535) {
          throw StateError(
            'Emulator public links require a debug build and loopback HTTP origin.',
          );
        }
        return PublicLinkConfiguration._(
          uri.origin,
          Set.unmodifiable({uri.origin}),
        );
      default:
        throw StateError('Unsupported public link environment: $environment');
    }
  }

  bool accepts(Uri uri) {
    // Relative in-app routes already belong to the running Firebase project.
    if (!uri.hasScheme && !uri.hasAuthority) return true;
    if (!uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    return acceptedOrigins.contains(uri.origin);
  }
}

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

  // Browser-exposed keys are expected to be HTTP-referrer restricted. Supply
  // this with --dart-define=GOOGLE_MAPS_WEB_API_KEY=... for web builds.
  static const String googleMapsWebApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_WEB_API_KEY',
    defaultValue: '',
  );

  // Select release constants here so dart2js can discard the other environment's
  // origins. The runtime factory remains available for injected configurations
  // and the validated debug-only emulator origin.
  static final PublicLinkConfiguration publicLinks =
      DefaultFirebaseOptions.environment == 'production'
      ? PublicLinkConfiguration._production
      : DefaultFirebaseOptions.environment == 'staging'
      ? PublicLinkConfiguration._staging
      : PublicLinkConfiguration.forEnvironment(
          DefaultFirebaseOptions.environment,
          emulatorPublicOrigin: const String.fromEnvironment(
            'ATTENDUS_EMULATOR_PUBLIC_ORIGIN',
            defaultValue: 'http://127.0.0.1:4173',
          ),
          debug: kDebugMode,
        );
  static String get publicWebDomain => publicLinks.canonicalOrigin;
  static const String stripeReturnUrl = 'attendus://callback';
  static const String stripeMerchantDisplayName = 'Attendus';
  static const String applePayMerchantIdentifier = 'merchant.app.attendus';

  // Feature flags
  // Apple Sign-In is hidden until the Apple Developer Service ID, callback URL,
  // and Firebase provider settings are configured for AttendUs.
  static const bool enableAppleSignIn = bool.fromEnvironment(
    'ATTENDUS_ENABLE_APPLE_SIGN_IN',
    defaultValue: false,
  );

  // Web App Check is enabled in production builds with the score-based
  // reCAPTCHA Enterprise key registered for attendus.app.
  static const bool enableWebAppCheck = bool.fromEnvironment(
    'ATTENDUS_ENABLE_WEB_APP_CHECK',
    defaultValue: false,
  );
  static const String appCheckWebRecaptchaEnterpriseSiteKey =
      String.fromEnvironment(
        'ATTENDUS_RECAPTCHA_ENTERPRISE_SITE_KEY',
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

  static Uri buildEventUri(String eventId, {PublicLinkConfiguration? links}) {
    final encodedId = Uri.encodeComponent(eventId.trim());
    return Uri.parse(
      '${(links ?? publicLinks).canonicalOrigin}/event/$encodedId',
    );
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
