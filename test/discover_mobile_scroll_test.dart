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
    final bottomNavFinder = find.byType(NavigationBar);
    final titleY = tester.getTopLeft(titleFinder).dy;
    final bottomNavY = tester.getTopLeft(bottomNavFinder).dy;

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -450),
    );
    await tester.pump();

    expect(tester.getTopLeft(titleFinder).dy, titleY);
    expect(tester.getTopLeft(bottomNavFinder).dy, bottomNavY);
    expect(find.byKey(const ValueKey('discover-shortcut-row')), findsNothing);
    expect(find.text('Discover events'), findsOneWidget);

    await tester.tap(find.text('Private groups'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Private group events'), findsOneWidget);
  });

  testWidgets('Discovery removes the legacy equal-weight shortcut row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(isGuestMode: false));

    expect(find.byKey(const ValueKey('discover-shortcut-row')), findsNothing);
    expect(find.text('Discover events'), findsOneWidget);
    expect(find.text('Public events'), findsOneWidget);
    expect(find.text('Private groups'), findsOneWidget);
  });

  testWidgets('guest Discovery stays focused on browseable public content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(isGuestMode: true));

    final titleFinder = find.text('Discover');
    final titleY = tester.getTopLeft(titleFinder).dy;

    expect(find.text('Private groups'), findsNothing);
    expect(find.text('Get more from Attendus'), findsNothing);
    expect(find.text('Discover events'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -450));
    await tester.pump();

    expect(tester.getTopLeft(titleFinder).dy, titleY);
    expect(find.text('Discover events'), findsOneWidget);
  });
}
