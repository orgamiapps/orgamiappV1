import 'deferred_load_recovery_contract.dart';
import 'deferred_load_recovery_stub.dart'
    if (dart.library.html) 'deferred_load_recovery_web.dart'
    as implementation;

export 'deferred_load_recovery_contract.dart';

DeferredLoadRecovery createDeferredLoadRecovery() =>
    implementation.createDeferredLoadRecovery();
