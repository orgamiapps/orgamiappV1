import 'deferred_load_recovery_contract.dart';

DeferredLoadRecovery createDeferredLoadRecovery() =>
    const _NativeDeferredLoadRecovery();

class _NativeDeferredLoadRecovery implements DeferredLoadRecovery {
  const _NativeDeferredLoadRecovery();

  @override
  bool get canRefreshApp => false;

  @override
  bool claimAutomaticRefresh(String recoveryKey) => false;

  @override
  void clearRecoveryGuard(String recoveryKey) {}

  @override
  void refreshApp() {}
}
