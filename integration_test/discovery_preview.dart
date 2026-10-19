// Local-only visual preview of the actual production widgets with fixture data.
// Build separately from lib/main.dart; never publish this entry point.
import 'package:attendus/controller/customer_controller.dart';
import 'package:attendus/models/customer_model.dart';
import 'package:attendus/screens/MyProfile/my_profile_screen.dart';
import 'package:flutter/material.dart';
import '../test/support/discovery_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!['localhost', '127.0.0.1'].contains(Uri.base.host)) {
    throw StateError('The discovery preview only runs on loopback.');
  }
  final query = Uri.base.queryParameters;
  final fixture = DiscoveryFixture();
  final guest = query['guest'] == '1';
  await fixture.install(
    guest: guest,
    city: query['long'] == '1'
        ? 'A very long coastal community location name'
        : 'Bonita Springs',
  );
  CustomerController.logeInCustomer = guest
      ? null
      : CustomerModel(
          uid: 'map-widget-owner',
          name: 'Preview Member',
          email: '',
          createdAt: DateTime(2026),
        );
  runApp(
    fixture.app(
      textScale: double.tryParse(query['scale'] ?? '') ?? 1,
      body: !guest && query['profile'] == '1'
          ? const MyProfileScreen(showBackButton: false)
          : null,
    ),
  );
}
