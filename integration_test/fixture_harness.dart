import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class BrowserFixtures {
  static const runId = String.fromEnvironment('ATTENDUS_BROWSER_RUN_ID');
  static const token = String.fromEnvironment('ATTENDUS_FIXTURE_TOKEN');
  static final origin = Uri.parse('http://127.0.0.1:4173');
  static Map<String, String> get headers => {
    'content-type': 'application/json',
    'x-fixture-token': token,
  };

  static Future<Map<String, dynamic>> post(
    String path, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (!RegExp(r'^browser-[a-f0-9]{16}$').hasMatch(runId) ||
        token.length != 64) {
      throw StateError('Use the isolated browser fixture runner.');
    }
    final response = await http.post(
      origin.resolve(path),
      headers: headers,
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      throw StateError(
        'Local fixture request failed (${response.statusCode}) at $path',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  static Future<void> track({String? eventId}) async {
    final user = FirebaseAuth.instance.currentUser;
    await post('/__track', {
      if (user != null) 'idToken': await user.getIdToken(),
      'eventId': ?eventId,
    });
  }
}
