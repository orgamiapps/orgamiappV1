import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/screens/Home/home_hub_screen.dart';
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

class _TestScrollContent extends StatelessWidget {
  final String label;

  const _TestScrollContent(this.label);

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      primary: true,
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            height: 900,
            padding: const EdgeInsets.all(20),
            alignment: Alignment.topLeft,
            child: Text(label),
          ),
        ),
      ],
    );
  }
}

Widget _app({required bool isGuestMode}) {
  return MaterialApp(
    theme: AttendUsTheme.light,
    home: AttendUsScaffold(
      title: 'Discover',
      subtitle: 'Find events, check in, and manage what is next.',
      selectedIndex: 0,
      destinations: _destinations,
      onDestinationSelected: (_) {},
      body: HomeHubScreen.test(
        isGuestMode: isGuestMode,
        publicContent: const _TestScrollContent('Discover events'),
        privateContent: const _TestScrollContent('Private group events'),
      ),
    ),
  );
}

void main() {
  testWidgets('signed-in Discover content scrolls below fixed app chrome', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(isGuestMode: false));

    final titleFinder = find.text('Discover');
    final searchFinder = find.text('Search Attendus');
    final bottomNavFinder = find.byType(NavigationBar);
    final titleY = tester.getTopLeft(titleFinder).dy;
    final bottomNavY = tester.getTopLeft(bottomNavFinder).dy;

    await tester.drag(find.byType(NestedScrollView), const Offset(0, -450));
    await tester.pump();

    expect(tester.getTopLeft(titleFinder).dy, titleY);
    expect(tester.getTopLeft(bottomNavFinder).dy, bottomNavY);
    expect(searchFinder, findsNothing);
    expect(find.text('Discover events'), findsOneWidget);

    await tester.drag(find.byType(NestedScrollView), const Offset(0, 450));
    await tester.pump();
    await tester.tap(find.text('Private groups'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Private group events'), findsOneWidget);
  });

  testWidgets('guest Discover banner joins the same continuous scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(isGuestMode: true));

    const guestMessage =
        'Create an account to create events, join groups, and access private attendance tools.';
    final titleFinder = find.text('Discover');
    final guestFinder = find.text(guestMessage);
    final titleY = tester.getTopLeft(titleFinder).dy;
    final guestY = tester.getTopLeft(guestFinder).dy;

    expect(find.text('Private groups'), findsNothing);
    expect(find.text('Sign up'), findsOneWidget);

    await tester.drag(find.byType(NestedScrollView), const Offset(0, -450));
    await tester.pump();

    expect(tester.getTopLeft(titleFinder).dy, titleY);
    expect(tester.getTopLeft(guestFinder).dy, lessThan(guestY));
    expect(find.text('Discover events'), findsOneWidget);
  });
}
