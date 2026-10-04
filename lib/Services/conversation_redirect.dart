/// Follow only server-owned conversation aliases. Membership remains enforced
/// by Firestore for every document read, including the destination.
Future<T> resolveConversationRedirect<T>(
  String initialId, {
  required Future<T> Function(String id) load,
  required String? Function(T value) redirect,
}) async {
  var id = initialId;
  final visited = <String>{};
  for (var depth = 0; depth < 8; depth++) {
    if (id.isEmpty || id.contains('/') || !visited.add(id)) {
      throw StateError('Conversation redirect is invalid');
    }
    final value = await load(id);
    final next = redirect(value);
    if (next == null) return value;
    id = next;
  }
  throw StateError('Conversation redirect limit exceeded');
}
