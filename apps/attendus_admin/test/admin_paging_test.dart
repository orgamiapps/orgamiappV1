import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:attendus_admin/services/admin_api_client.dart';
import 'package:attendus_admin/ui/paged_resource_screen.dart';
import 'admin_api_client_test.dart' show TestAuth, TestUser;

void main() {
  testWidgets('newer page request wins and old data is cleared while loading', (
    tester,
  ) async {
    final auth = TestAuth(TestUser('owned-admin'));
    final responses = <Completer<http.Response>>[];
    final api = AdminApiClient(
      auth: auth,
      client: MockClient((_) {
        final response = Completer<http.Response>();
        responses.add(response);
        return response.future;
      }),
    );
    addTearDown(() async {
      api.dispose();
      await auth.changes.close();
    });
    await tester.pumpWidget(
      Provider.value(
        value: api,
        child: const MaterialApp(
          home: Scaffold(
            body: PagedResourceScreen(
              title: 'Accounts',
              path: '/v1/accounts',
              columns: ['name'],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(responses, hasLength(2));
    responses[1].complete(
      http.Response('{"data":[{"name":"current account"}]}', 200),
    );
    await tester.pumpAndSettle();
    expect(find.text('current account'), findsOneWidget);
    responses[0].complete(
      http.Response('{"data":[{"name":"stale account"}]}', 200),
    );
    await tester.pumpAndSettle();
    expect(find.text('current account'), findsOneWidget);
    expect(find.text('stale account'), findsNothing);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(find.text('current account'), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Export current page to CSV',
            ),
          )
          .onPressed,
      isNull,
    );
    responses[2].complete(http.Response('<html>offline</html>', 503));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });
}
