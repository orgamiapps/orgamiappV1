import 'package:attendus/Services/conversation_redirect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'old links resolve through aliases to the surviving conversation',
    () async {
      final reads = <String>[];
      final result = await resolveConversationRedirect<String>(
        'old',
        load: (id) async {
          reads.add(id);
          return id;
        },
        redirect: (id) =>
            {'old': 'intermediate', 'intermediate': 'current'}[id],
      );
      expect(result, 'current');
      expect(reads, ['old', 'intermediate', 'current']);
    },
  );
  test('cycles, invalid paths and excessive redirects fail closed', () async {
    for (final next in [
      (String id) => id,
      (String id) => 'bad/path',
      (String id) => '${id}x',
    ]) {
      await expectLater(
        resolveConversationRedirect<String>(
          'old',
          load: (id) async => id,
          redirect: next,
        ),
        throwsStateError,
      );
    }
  });
  test(
    'destination authorization failures propagate without fallback',
    () async {
      await expectLater(
        resolveConversationRedirect<String>(
          'old',
          load: (id) async {
            if (id == 'new') throw StateError('permission denied');
            return id;
          },
          redirect: (_) => 'new',
        ),
        throwsStateError,
      );
    },
  );
}
