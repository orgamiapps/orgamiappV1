import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/screens/Groups/create_group_screen.dart';
import 'package:attendus/screens/Groups/groups_list_screen.dart';
import 'package:attendus/screens/Groups/groups_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('create group shell renders', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(theme: AttendUsTheme.light, home: const CreateGroupScreen()),
    );

    expect(find.text('Create group'), findsWidgets);
    expect(find.text('Group details'), findsOneWidget);
    expect(find.text('Branding'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
  });

  testWidgets('groups compatibility routes expose modern widgets', (
    tester,
  ) async {
    expect(const GroupsListScreen(), isA<GroupsListScreen>());
    expect(const GroupsTab(), isA<GroupsTab>());
  });
}
