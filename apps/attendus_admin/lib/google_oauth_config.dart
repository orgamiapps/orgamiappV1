import 'package:google_sign_in_dartio/google_sign_in_dartio.dart';

const googleDesktopOAuthClientId = String.fromEnvironment(
  'ATTENDUS_GOOGLE_OAUTH_CLIENT_ID',
);

bool get isGoogleDesktopOAuthConfigured =>
    googleDesktopOAuthClientId.isNotEmpty;

Future<void> initializeGoogleDesktopOAuth() async {
  if (!isGoogleDesktopOAuthConfigured) return;
  await GoogleSignInDart.register(clientId: googleDesktopOAuthClientId);
}
