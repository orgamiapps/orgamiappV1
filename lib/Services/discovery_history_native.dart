import 'discovery_history_port.dart';

class DiscoveryHistoryBackend implements DiscoveryHistoryPort {
  DiscoveryHistoryBackend({
    required void Function(Uri, double) onRestore,
    required bool Function() isActive,
  });
  @override
  Uri get currentUri => Uri();
  @override
  double get scroll => 0;
  @override
  bool get available => false;
  @override
  void write(Uri uri, double offset, {required bool push}) {}
  @override
  void dispose() {}
}
