abstract interface class DeferredLoadRecovery {
  bool get canRefreshApp;

  bool claimAutomaticRefresh(String recoveryKey);

  void clearRecoveryGuard(String recoveryKey);

  void refreshApp();
}

typedef DeferredGuardReader = String? Function(String key);
typedef DeferredGuardWriter = void Function(String key, String value);
typedef DeferredGuardRemover = void Function(String key);

class DeferredReloadGuard {
  DeferredReloadGuard({
    required DeferredGuardReader read,
    required DeferredGuardWriter write,
    required DeferredGuardRemover remove,
  }) : _read = read,
       _write = write,
       _remove = remove;

  static const String _prefix = 'attendus:deferred-reload:';
  static const String _attempted = 'attempted';

  final DeferredGuardReader _read;
  final DeferredGuardWriter _write;
  final DeferredGuardRemover _remove;

  bool claim(String recoveryKey) {
    final key = _storageKey(recoveryKey);
    try {
      if (_read(key) == _attempted) return false;
      _write(key, _attempted);
      return true;
    } catch (_) {
      // Storage can be unavailable in private browsing. Do not auto-refresh
      // without a durable per-tab guard because that could create a loop.
      return false;
    }
  }

  void clear(String recoveryKey) {
    try {
      _remove(_storageKey(recoveryKey));
    } catch (_) {
      // Recovery storage is best-effort and must never block a loaded screen.
    }
  }

  String _storageKey(String recoveryKey) => '$_prefix$recoveryKey';
}
