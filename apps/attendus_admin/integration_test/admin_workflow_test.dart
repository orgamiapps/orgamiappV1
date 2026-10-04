import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:attendus_admin/services/admin_api_client.dart';
import 'package:attendus_admin/ui/paged_resource_screen.dart';
import '../test/admin_api_client_test.dart' show TestAuth, TestUser;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'desktop account list recovers from unavailable API and paginates',
    (tester) async {
      final auth = TestAuth(TestUser('owned-desktop-fixture'));
      final requests = <Uri>[];
      var unavailable = true;
      final api = AdminApiClient(
        auth: auth,
        client: MockClient((request) async {
          requests.add(request.url);
          if (unavailable) {
            return http.Response('<html>unavailable</html>', 503);
          }
          final next = request.url.queryParameters['pageToken'] == 'page-2';
          return http.Response(
            jsonEncode({
              'data': [
                {'name': next ? 'Second fixture' : 'First fixture'},
              ],
              'meta': {'nextPageToken': next ? null : 'page-2'},
            }),
            200,
          );
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
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      unavailable = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('First fixture'), findsOneWidget);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Second fixture'), findsOneWidget);
      expect(requests.last.queryParameters['pageToken'], 'page-2');
      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(find.text('First fixture'), findsOneWidget);
      expect(requests.last.queryParameters.containsKey('pageToken'), isFalse);
    },
  );
}
