import 'dart:async';
import 'package:attendus/Services/messaging_feed.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty success differs from failure, and retry recovers', () async {
    final feed = MessagingFeed<int>();
    final first = StreamController<List<int>>();
    await feed.bind('a', () async => first.stream);
    first.addError(
      FirebaseException(plugin: 'firestore', code: 'failed-precondition'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(feed.error, contains('service update'));
    expect(feed.loading, false);
    final second = StreamController<List<int>>();
    await feed.bind('a', () async => second.stream);
    second.add([]);
    await Future<void>.delayed(Duration.zero);
    expect(feed.error, null);
    expect(feed.items, isEmpty);
    feed.dispose();
    await first.close();
    await second.close();
  });

  test(
    'network errors retain content; account changes and access errors clear it',
    () async {
      final feed = MessagingFeed<int>();
      final controller = StreamController<List<int>>();
      await feed.bind('a', () async => controller.stream);
      controller.add([1]);
      await Future<void>.delayed(Duration.zero);
      controller.addError(
        FirebaseException(plugin: 'firestore', code: 'unavailable'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(feed.items, [1]);
      expect(feed.error, contains('connection'));
      controller.add([2]);
      await Future<void>.delayed(Duration.zero);
      expect(feed.error, null);
      controller.addError(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(feed.items, isEmpty);
      await feed.bind(null, () async => controller.stream);
      expect(feed.items, isEmpty);
      expect(feed.error, contains('sign in'));
      feed.dispose();
      await controller.close();
    },
  );

  test(
    'late asynchronous setup cannot subscribe after retry or disposal',
    () async {
      final feed = MessagingFeed<int>();
      final delayed = Completer<Stream<List<int>>>();
      final obsolete = feed.bind('a', () => delayed.future);
      await Future<void>.delayed(Duration.zero);
      await feed.bind('b', () async => Stream.value([2]));
      await Future<void>.delayed(Duration.zero);
      delayed.complete(Stream.value([1]));
      await obsolete;
      expect(feed.items, [2]);
      final pending = Completer<Stream<List<int>>>();
      final finalBind = feed.bind('b', () => pending.future);
      await Future<void>.delayed(Duration.zero);
      feed.dispose();
      pending.complete(Stream.value([3]));
      await finalBind;
      expect(feed.items, [2]);
    },
  );

  testWidgets('timeout can recover when the stream subsequently connects', (
    tester,
  ) async {
    final feed = MessagingFeed<int>(timeout: const Duration(seconds: 2));
    final controller = StreamController<List<int>>();
    await feed.bind('a', () async => controller.stream);
    await tester.pump(const Duration(seconds: 3));
    expect(feed.loading, false);
    expect(feed.error, contains('timed out'));
    controller.add([1]);
    await tester.pump();
    expect(feed.error, null);
    expect(feed.items, [1]);
    feed.dispose();
    unawaited(controller.close());
    await tester.pump();
  });
}
