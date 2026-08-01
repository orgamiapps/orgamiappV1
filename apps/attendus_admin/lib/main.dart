import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'google_oauth_config.dart';
import 'services/admin_api_client.dart';
import 'services/session_controller.dart';
import 'ui/admin_shell.dart';
import 'ui/sign_in_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: AdminFirebaseOptions.windows);
  await initializeGoogleDesktopOAuth();
  runApp(const AttendusAdminApp());
}

class AttendusAdminApp extends StatefulWidget {
  const AttendusAdminApp({super.key});
  @override
  State<AttendusAdminApp> createState() => _AttendusAdminAppState();
}

class _AttendusAdminAppState extends State<AttendusAdminApp> {
  ThemeMode mode = ThemeMode.system;
  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3867D6);
    return MultiProvider(
      providers: [
        Provider(create: (_) => AdminApiClient()),
        ChangeNotifierProvider(create: (_) => SessionController()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Attendus Admin',
        themeMode: mode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: seed,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: Consumer<SessionController>(
          builder: (_, session, _) => switch (session.status) {
            SessionStatus.authorized => AdminShell(
              onThemeChanged: () => setState(
                () => mode = mode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark,
              ),
            ),
            SessionStatus.unauthorized => UnauthorizedScreen(
              onRetry: session.refreshAccess,
              onSignOut: session.signOut,
            ),
            SessionStatus.signedOut => const SignInScreen(),
            SessionStatus.error => AccessErrorScreen(
              message: session.error,
              onRetry: session.refreshAccess,
              onSignOut: session.signOut,
            ),
            _ => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          },
        ),
      ),
    );
  }
}
