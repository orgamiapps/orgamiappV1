class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.requestId, this.status});
  final String code, message;
  final String? requestId;
  final int? status;
  bool get isOffline => code == 'NETWORK_ERROR';
  @override
  String toString() => message;
}

class AdminPage {
  const AdminPage({required this.items, this.nextPageToken});
  final List<Map<String, dynamic>> items;
  final String? nextPageToken;
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
