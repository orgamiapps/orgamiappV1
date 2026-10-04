import 'package:web/web.dart' as web;

import 'deferred_load_recovery_contract.dart';

DeferredLoadRecovery createDeferredLoadRecovery() => _WebDeferredLoadRecovery();

class _WebDeferredLoadRecovery implements DeferredLoadRecovery {
  _WebDeferredLoadRecovery()
    : _guard = DeferredReloadGuard(
        read: (key) => web.window.sessionStorage.getItem(key),
        write: (key, value) => web.window.sessionStorage.setItem(key, value),
        remove: (key) => web.window.sessionStorage.removeItem(key),
      );

  final DeferredReloadGuard _guard;

  @override
  bool get canRefreshApp => true;

  @override
  bool claimAutomaticRefresh(String recoveryKey) => _guard.claim(recoveryKey);

  @override
  void clearRecoveryGuard(String recoveryKey) => _guard.clear(recoveryKey);

  @override
  void refreshApp() => web.window.location.reload();
}
