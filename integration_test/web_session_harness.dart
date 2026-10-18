// Browser-process regression harness for the production restoration service.
// Never uses production Firebase or exports credentials/browser storage.
import 'dart:js_interop';
import 'package:attendus/Services/web_auth_session.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  try {
    await runHarness();
  } catch (error) {
    final failure = web.HTMLDivElement()
      ..id = 'session-error'
      ..textContent = error.toString();
    web.document.body!.append(failure);
  }
}

Future<void> runHarness() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (web.window.location.hostname != '127.0.0.1') {
    throw StateError('This harness only runs on loopback.');
  }
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'fake-api-key',
      appId: '1:123:web:test',
      messagingSenderId: '123',
      projectId: 'demo-attendus-admin',
      authDomain: '127.0.0.1',
    ),
  );
  final auth = FirebaseAuth.instance;
  // The test server configures the emulator before FlutterFire hydrates Auth.
  final session = WebAuthSession(auth: auth, initialize: () async {});
  if (web.window.location.search == '?legacy=1') {
    // Simulate the previous release through a real SDK sign-in, not token injection.
    await auth.setPersistence(Persistence.LOCAL);
    await auth.authStateChanges().first;
  } else {
    await session.ready();
  }
  final status = web.HTMLDivElement()..id = 'session-status';
  final email = web.HTMLInputElement()..id = 'email';
  final register = web.HTMLButtonElement()..textContent = 'Create test account';
  final logout = web.HTMLButtonElement()..textContent = 'Log out';
  register.onclick = ((web.Event event) {
    auth.createUserWithEmailAndPassword(
      email: email.value,
      password: 'emulator-only-password',
    );
  }).toJS;
  logout.onclick = ((web.Event event) {
    auth.signOut();
  }).toJS;
  web.document.body!.append(status);
  web.document.body!.append(email);
  web.document.body!.append(register);
  web.document.body!.append(logout);
  auth.authStateChanges().listen((user) {
    status.textContent = user == null ? 'signed-out' : 'account:${user.uid}';
  });
}
