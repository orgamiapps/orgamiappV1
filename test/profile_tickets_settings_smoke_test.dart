import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/Utils/theme_provider.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/screens/Home/settings_screen.dart';
import 'package:attendus/screens/MyProfile/my_tickets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('tickets screen renders modern wallet shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AttendUsTheme.light, home: const MyTicketsScreen()),
    );

    expect(find.text('My Tickets'), findsOneWidget);
    expect(
      find.text('Active passes, used tickets, and QR check-in codes.'),
      findsOneWidget,
    );
  });

  testWidgets('settings screen renders modern settings shell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: ChangeNotifierProvider<SubscriptionService>(
          create: (_) => SubscriptionService(),
          child: MaterialApp(
            theme: AttendUsTheme.light,
            home: const SettingsScreen(),
          ),
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(
      find.text('Manage your profile, plan, preferences, and privacy.'),
      findsOneWidget,
    );
    expect(find.text('Membership'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Support & Information'), findsOneWidget);
    expect(find.text('Account & Legal'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('settings shell header remains opt-out for embedded routes', () {
    expect(const SettingsScreen().showShellHeader, isTrue);
    expect(
      const SettingsScreen(showShellHeader: false).showShellHeader,
      isFalse,
    );
  });
}
