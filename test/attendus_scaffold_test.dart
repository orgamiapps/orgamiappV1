import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/widgets/attendus_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _destinations = [
  AttendUsNavDestination(
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
  ),
  AttendUsNavDestination(
    label: 'Groups',
    icon: Icons.apartment_outlined,
    selectedIcon: Icons.apartment,
  ),
  AttendUsNavDestination(
    label: 'Messages',
    icon: Icons.forum_outlined,
    selectedIcon: Icons.forum,
  ),
  AttendUsNavDestination(
    label: 'Profile',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
  ),
  AttendUsNavDestination(
    label: 'Account',
    icon: Icons.menu_outlined,
    selectedIcon: Icons.menu,
  ),
];

Widget _wrap(Widget child, {required Size size}) {
  return MaterialApp(
    theme: AttendUsTheme.light,
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

AttendUsScaffold _scaffold() {
  return AttendUsScaffold(
    title: 'Dashboard',
    subtitle: 'Operational shell',
    selectedIndex: 0,
    destinations: _destinations,
    onDestinationSelected: (_) {},
    onNotificationsPressed: () {},
    onProfilePressed: () {},
    profileName: 'Alex Rivera',
    body: const Center(child: Text('Shell body')),
  );
}

void main() {
  testWidgets('uses bottom navigation on mobile width', (tester) async {
    await tester.pumpWidget(_wrap(_scaffold(), size: const Size(390, 844)));

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Shell body'), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('uses persistent side navigation on tablet and desktop widths', (
    tester,
  ) async {
    for (final width in <double>[768, 1280, 1600]) {
      await tester.pumpWidget(_wrap(_scaffold(), size: Size(width, 900)));

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Shell body'), findsOneWidget);
      expect(find.byIcon(Icons.event_available), findsOneWidget);
    }
  });
}
