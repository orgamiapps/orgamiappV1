import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:attendus/Utils/logger.dart';

String messagingErrorMessage(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Please sign in again to view messages.';
      case 'permission-denied':
        return 'This conversation is unavailable for your account.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Connection interrupted. Check your connection and try again.';
      case 'failed-precondition':
        return 'Messages need a service update. Please try again shortly.';
      case 'resource-exhausted':
        return 'Please wait a moment before trying again.';
    }
  }
  if (error is TimeoutException) {
    return 'Connection timed out. Check your connection and try again.';
  }
  return 'Could not load messages. Please try again.';
}

/// Owns a single subscription, including asynchronous setup and retry races.
class MessagingFeed<T> extends ChangeNotifier {
  MessagingFeed({this.timeout = const Duration(seconds: 20)});
  final Duration timeout;
  List<T> items = [];
  bool loading = true;
  String? error;
  String? _session;
  int _generation = 0;
  bool _disposed = false;
  Timer? _timer;
  StreamSubscription<List<T>>? _subscription;

  Future<void> bind(
    String? session,
    Future<Stream<List<T>>> Function() source, {
    bool clearItems = false,
  }) async {
    final generation = ++_generation;
    _timer?.cancel();
    final previous = _subscription;
    _subscription = null;
    if (clearItems || _session != session) items = [];
    _session = session;
    error = null;
    loading = items.isEmpty;
    if (session == null) {
      items = [];
      loading = false;
      error = 'Please sign in to view messages.';
    }
    notifyListeners();
    await previous?.cancel();
    if (!_active(generation) || session == null) return;
    void failed(Object failure) {
      if (!_active(generation)) return;
      _timer?.cancel();
      loading = false;
      error = messagingErrorMessage(failure);
      if (failure is FirebaseException &&
          ['permission-denied', 'unauthenticated'].contains(failure.code)) {
        items = [];
      }
      Logger.error(
        'messaging_feed: ${failure is FirebaseException ? failure.code : failure.runtimeType}',
      );
      notifyListeners();
    }

    _timer = Timer(timeout, () => failed(TimeoutException('messages')));
    try {
      final stream = await source();
      if (!_active(generation)) return;
      _subscription = stream.listen((value) {
        if (!_active(generation)) return;
        _timer?.cancel();
        items = value;
        loading = false;
        error = null;
        notifyListeners();
      }, onError: failed);
    } catch (failure) {
      failed(failure);
    }
  }

  bool _active(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
