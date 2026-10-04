import 'dart:async';

/// A server signal that the locally retained FCM token belongs to another
/// installation. Rotation, rather than stealing that binding, is required.
class PushInstallationReset implements Exception {}

/// Serializes this installation's push ownership changes and persists the
/// generation before sending an intent. The server rejects late generations.
class PushTokenLifecycle {
  PushTokenLifecycle({
    required this.currentUid,
    required this.readState,
    required this.writeState,
    required this.newInstallationId,
    required this.acquireToken,
    required this.deleteToken,
    required this.register,
    required this.revoke,
    required this.clearNotifications,
    required this.onError,
    this.timeout = const Duration(seconds: 5),
  });

  final String? Function() currentUid;
  final Future<Map<String, dynamic>> Function() readState;
  final Future<void> Function(Map<String, dynamic>) writeState;
  final String Function() newInstallationId;
  final Future<String?> Function() acquireToken;
  final Future<void> Function() deleteToken;
  final Future<void> Function(Map<String, dynamic>) register;
  final Future<void> Function(Map<String, dynamic>) revoke;
  final Future<void> Function() clearNotifications;
  final void Function(Object) onError;
  final Duration timeout;

  Future<void> _tail = Future<void>.value();
  Future<void>? _deletingToken;
  String? _observedUid;
  bool _observed = false;
  bool _signedOut = false;
  int _epoch = 0;

  Future<void> _serial(Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.catchError((Object error) => onError(error));
    return result;
  }

  bool _current(String uid, int epoch) =>
      !_signedOut &&
      _observedUid == uid &&
      currentUid() == uid &&
      _epoch == epoch;

  Future<Map<String, dynamic>> _load() async {
    final stored = Map<String, dynamic>.from(
      await readState().timeout(timeout),
    );
    if (stored['installationId'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{24,128}$',
        ).hasMatch(stored['installationId'])) {
      final previouslyBound = stored['binding'] is Map;
      stored['installationId'] = newInstallationId();
      stored['generation'] = 0;
      stored['rotationRequired'] = previouslyBound;
    }
    if (stored['generation'] is! int || stored['generation'] < 0) {
      stored['generation'] = 0;
      stored['installationId'] = newInstallationId();
      stored['rotationRequired'] = true;
    }
    stored['pendingRevocations'] = [
      for (final value in stored['pendingRevocations'] as List? ?? const [])
        if (value is Map) Map<String, dynamic>.from(value),
    ];
    return stored;
  }

  Future<void> _persist(Map<String, dynamic> state) =>
      writeState(state).timeout(timeout);

  void _retainRevocation(Map<String, dynamic> state, dynamic binding) {
    if (binding is! Map ||
        binding['uid'] is! String ||
        binding['token'] is! String) {
      return;
    }
    final pending = state['pendingRevocations'] as List;
    if (!pending.any(
      (item) =>
          item['uid'] == binding['uid'] && item['token'] == binding['token'],
    )) {
      pending.add(Map<String, dynamic>.from(binding));
    }
  }

  Future<Map<String, dynamic>> _intent(
    Map<String, dynamic> state,
    String uid,
    String token, {
    String? installationId,
  }) async {
    state['generation'] = (state['generation'] as int) + 1;
    await _persist(state);
    return {
      'token': token,
      'expectedUid': uid,
      'installationId': installationId ?? state['installationId'],
      'generation': state['generation'],
    };
  }

  Future<void> _rotate(Map<String, dynamic> state) async {
    state['rotationRequired'] = true;
    await _persist(state);
    // Do not start a new registration while an SDK deletion that timed out is
    // still running: its late completion could otherwise invalidate the token.
    final work = _deletingToken ??= deleteToken();
    try {
      await work.timeout(timeout);
      if (identical(_deletingToken, work)) _deletingToken = null;
      state['rotationRequired'] = false;
      await _persist(state);
    } catch (_) {
      // An errored operation can be retried; an unfinished one remains a fence.
      unawaited(
        work.then(
          (_) {
            if (identical(_deletingToken, work)) _deletingToken = null;
          },
          onError: (Object _) {
            if (identical(_deletingToken, work)) _deletingToken = null;
          },
        ),
      );
      rethrow;
    }
  }

  Future<void> synchronize() {
    final uid = currentUid();
    if (!_observed || uid != _observedUid) {
      _observed = true;
      _observedUid = uid;
      _signedOut = false;
      _epoch++;
    }
    if (_signedOut) return Future<void>.value();
    final epoch = _epoch;
    return _serial(() async {
      if (_epoch != epoch || currentUid() != uid || _signedOut) return;
      final state = await _load();
      if (_epoch != epoch || currentUid() != uid || _signedOut) return;
      final binding = state['binding'];
      if (binding is Map && binding['uid'] != uid) {
        _retainRevocation(state, binding);
        state['binding'] = null;
        state['rotationRequired'] = true;
        try {
          await clearNotifications().timeout(timeout);
        } catch (error) {
          onError(error);
        }
      }
      if (state['rotationRequired'] == true) await _rotate(state);
      if (uid == null || !_current(uid, epoch)) return;
      final pending = state['pendingRevocations'] as List;
      for (final item in List<Map<String, dynamic>>.from(pending)) {
        if (item['uid'] != uid || !_current(uid, epoch)) continue;
        try {
          final intent = await _intent(
            state,
            uid,
            item['token'],
            installationId: item['installationId'],
          );
          if (!_current(uid, epoch)) return;
          await revoke(intent).timeout(timeout);
          pending.remove(item);
          await _persist(state);
        } catch (error) {
          onError(error);
        }
      }
      if (!_current(uid, epoch)) return;
      final token = await acquireToken().timeout(timeout);
      if (token == null || !_current(uid, epoch)) return;
      await _register(state, uid, epoch, token);
    });
  }

  Future<void> _register(
    Map<String, dynamic> state,
    String uid,
    int epoch,
    String token, {
    bool resetAllowed = true,
  }) async {
    if (!_current(uid, epoch)) return;
    // Retain the attempted binding before the request: a lost response must
    // still be revocable after restart or logout.
    state['binding'] = {
      'uid': uid,
      'token': token,
      'installationId': state['installationId'],
    };
    final intent = await _intent(state, uid, token);
    if (!_current(uid, epoch)) return;
    try {
      await register(intent).timeout(timeout);
    } on PushInstallationReset {
      if (!resetAllowed || !_current(uid, epoch)) rethrow;
      _retainRevocation(state, state['binding']);
      state['binding'] = null;
      state['installationId'] = newInstallationId();
      await _rotate(state);
      if (!_current(uid, epoch)) return;
      final replacement = await acquireToken().timeout(timeout);
      if (replacement != null && _current(uid, epoch)) {
        await _register(state, uid, epoch, replacement, resetAllowed: false);
      }
    }
  }

  Future<void> tokenRefreshed(String token) {
    final uid = currentUid();
    final epoch = _epoch;
    if (uid == null || !_current(uid, epoch)) return Future<void>.value();
    return _serial(() async {
      if (!_current(uid, epoch)) return;
      final state = await _load();
      if (state['rotationRequired'] == true || _deletingToken != null) return;
      await _register(state, uid, epoch, token);
    });
  }

  /// Local logout proceeds even offline. Unconfirmed revocations remain stored
  /// for the next matching account session; the next owner uses a newer intent.
  Future<void> clearForSignOut() {
    final uid = currentUid();
    _signedOut = true;
    _observed = true;
    _observedUid = uid;
    _epoch++;
    return _serial(() async {
      try {
        await clearNotifications().timeout(timeout);
      } catch (error) {
        onError(error);
      }
      final state = await _load();
      final binding = state['binding'];
      _retainRevocation(state, binding);
      state['binding'] = null;
      state['rotationRequired'] = true;
      await _persist(state);
      if (uid != null && binding is Map && binding['uid'] == uid) {
        try {
          final intent = await _intent(
            state,
            uid,
            binding['token'],
            installationId: binding['installationId'],
          );
          if (currentUid() == uid) {
            await revoke(intent).timeout(timeout);
            (state['pendingRevocations'] as List).removeWhere(
              (item) => item['uid'] == uid && item['token'] == binding['token'],
            );
            await _persist(state);
          }
        } catch (error) {
          onError(error);
        }
      }
      try {
        await _rotate(state);
      } catch (error) {
        onError(error);
      }
    }).catchError((Object error) => onError(error));
  }
}
