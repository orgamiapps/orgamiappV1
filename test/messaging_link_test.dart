import 'package:attendus/Services/account_access_service.dart';
import 'package:attendus/Services/pending_auth_intent_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'conversation link survives login intent and is consumed once',
    () async {
      await PendingAuthIntentService.rememberConversation('member-a_member-b');
      await PendingAuthIntentService.rememberHome();
      await PendingAuthIntentService.rememberFeature(AccountFeature.messages);
      final intent = await PendingAuthIntentService.consume();
      expect(intent?.action, PendingAuthAction.sharedConversation);
      expect(intent?.conversationId, 'member-a_member-b');
      expect(await PendingAuthIntentService.consume(), isNull);
    },
  );
  test('invalid conversation links cannot become pending navigation', () async {
    for (final id in ['', ' ', 'a/b', 'x' * 301]) {
      await PendingAuthIntentService.rememberConversation(id);
      expect(await PendingAuthIntentService.consume(), isNull);
    }
  });
  test('conversation link round trips through storage', () async {
    await PendingAuthIntentService.rememberConversation('group-123');
    final intent = (await PendingAuthIntentService.consume())!;
    expect(
      PendingAuthIntent.fromJson(intent.toJson())?.conversationId,
      'group-123',
    );
  });
}
