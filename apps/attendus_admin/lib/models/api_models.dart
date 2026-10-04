class ApiException implements Exception {
  const ApiException(
    this.code,
    this.message, {
    this.requestId,
    this.status,
    this.idempotencyKey,
    this.outcomeUnknown = false,
  });
  final String code, message;
  final String? requestId;
  final int? status;
  final String? idempotencyKey;
  final bool outcomeUnknown;
  bool get isOffline => code == 'NETWORK_ERROR';
  @override
  String toString() => message;
}

class AdminPage {
  const AdminPage({required this.items, this.nextPageToken});
  final List<Map<String, dynamic>> items;
  final String? nextPageToken;
}

Map<String, dynamic> requireApiObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const ApiException(
    'INVALID_RESPONSE',
    'The Admin API returned invalid details. Please retry.',
  );
}

List<Map<String, dynamic>> requireApiRows(Object? value) {
  if (value is List && value.every((row) => row is Map<String, dynamic>)) {
    return value.cast<Map<String, dynamic>>();
  }
  throw const ApiException(
    'INVALID_RESPONSE',
    'The Admin API returned invalid rows. Please retry.',
  );
}

class PaginationCursor {
  final List<String?> _tokens = [null];
  int index = 0;
  String? get token => _tokens[index];
  bool get canGoBack => index > 0;
  void reset() {
    _tokens
      ..clear()
      ..add(null);
    index = 0;
  }

  bool forward(String? nextToken) {
    if (nextToken == null) return false;
    if (_tokens.length == index + 1) _tokens.add(nextToken);
    index++;
    return true;
  }

  bool back() {
    if (!canGoBack) return false;
    index--;
    return true;
  }
}
