import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/Utils/theme_provider.dart';
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/screens/Home/account_screen.dart';
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

  testWidgets('account screen renders modern account shell', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: ChangeNotifierProvider<SubscriptionService>(
          create: (_) => SubscriptionService(),
          child: MaterialApp(
            theme: AttendUsTheme.light,
            home: const AccountScreen(),
          ),
        ),
      ),
    );

    expect(find.text('Account'), findsOneWidget);
    expect(
      find.text('Profile, subscription, privacy, and support.'),
      findsOneWidget,
    );
  });
}
