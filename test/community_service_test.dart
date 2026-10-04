import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/Services/community_service.dart';

void main() {
  test('uncertain retry reuses comment id and desired like state', () async {
    final calls = <Map<String, dynamic>>[];
    final service = CommunityService(
      currentUid: () => 'member',
      caller: (data) async {
        calls.add(data);
        if (calls.length == 1) {
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'Temporary outage',
          );
        }
        return {'success': true};
      },
    );
    await service.mutate('addComment', {
      'organizationId': 'org',
      'postId': 'post',
      'commentId': 'stable',
      'comment': 'Hello',
    });
    expect(calls, hasLength(2));
    expect(calls[0], calls[1]);
    expect(calls.last['commentId'], 'stable');
  });
  test(
    'account switch rejects delayed mutation result without replay under new account',
    () async {
      String? uid = 'a';
      final result = Completer<Map<String, dynamic>>();
      final service = CommunityService(
        currentUid: () => uid,
        caller: (_) => result.future,
      );
      final pending = service.mutate('setLike', {'liked': true});
      uid = 'b';
      result.complete({'success': true});
      await expectLater(pending, throwsStateError);
    },
  );
  test('closed, expired and malformed poll deadlines fail closed', () {
    final now = DateTime.utc(2026, 10, 3);
    expect(CommunityService.isPollClosed({'isClosed': true}, now: now), true);
    expect(CommunityService.isPollClosed({'isActive': false}, now: now), true);
    expect(
      CommunityService.isPollClosed({
        'endDate': now.toIso8601String(),
      }, now: now),
      true,
    );
    expect(CommunityService.isPollClosed({'endDate': 'bad'}, now: now), true);
    expect(
      CommunityService.isPollClosed({
        'endDate': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      }, now: now),
      false,
    );
  });
}
