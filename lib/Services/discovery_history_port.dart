abstract class DiscoveryHistoryPort {
  Uri get currentUri;
  double get scroll;
  bool get available;
  void write(Uri uri, double offset, {required bool push});
  void dispose();
}
