// Local-only preview; never deploy this entrypoint.
import 'package:flutter/material.dart';
import 'package:attendus/screens/Events/Widget/qr_dialogue.dart';
import '../test/support/qr_share_fixture.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!['localhost', '127.0.0.1'].contains(Uri.base.host)) {
    throw StateError('QR preview is restricted to loopback.');
  }
  WidgetsBinding.instance.ensureSemantics();
  runApp(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorSchemeSeed: const Color(0xFF13776C),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showEventQrShare(context, qrShareFixture()),
              child: const Text('Share event QR'),
            ),
          ),
        ),
      ),
    ),
  );
}
