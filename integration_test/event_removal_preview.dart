// Local-only production-flow qualification. Never deploy this entry point.
import 'dart:async';

import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/Utils/theme_provider.dart';
import 'package:attendus/screens/Events/shared_event_screen.dart';
import 'package:attendus/screens/Home/home_hub_screen.dart';
import 'package:attendus/widgets/attendus_scaffold.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../test/support/event_access_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!['localhost', '127.0.0.1'].contains(Uri.base.host)) {
    throw StateError('Event removal preview only runs on loopback.');
  }
  final fixture = EventAccessFixture();
  await fixture.install();
  final scenario = Uri.base.queryParameters['scenario'] ?? 'empty';
  runApp(RemovalPreview(fixture: fixture, scenario: scenario));
  // Activate browser accessibility after the first production layout settles.
  // This matches a browser accessibility request after application startup.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    WidgetsBinding.instance.ensureSemantics();
  });
}

class RemovalPreview extends StatefulWidget {
  const RemovalPreview({
    super.key,
    required this.fixture,
    required this.scenario,
  });

  final EventAccessFixture fixture;
  final String scenario;

  @override
  State<RemovalPreview> createState() => _RemovalPreviewState();
}

class _RemovalPreviewState extends State<RemovalPreview> {
  final _navigator = GlobalKey<NavigatorState>();
  final _diagnostics = ValueNotifier('Fixture ready');
  final _receipts = <String, Map<String, dynamic>>{};
  late final String _id = 'removal-${widget.scenario}';
  int _mutationCalls = 0;
  int _commits = 0;
  int _replays = 0;
  String _reason = '';
  bool get _populated => widget.scenario == 'populated';
  String get _title => _populated
      ? 'Registered community breakfast'
      : widget.scenario == 'lost-response'
      ? 'Lost response garden evening'
      : widget.scenario == 'remote'
      ? 'Remote removal garden evening'
      : 'Creator garden evening';

  @override
  void initState() {
    super.initState();
    widget.fixture.firestore.events[_id] = {
      ...discoveryEventFixture,
      'id': _id,
      'title': _title,
      'customerUid': 'map-widget-owner',
      'eventRevision': 5,
      'confirmedRegistrationCount': _populated ? 3 : 0,
    };
    widget.fixture.functions.handler = _handle;
    _updateDiagnostics();
  }

  void _updateDiagnostics() {
    _diagnostics.value =
        'Fixture ${widget.scenario}: calls=$_mutationCalls '
        'commits=$_commits replays=$_replays'
        '${_reason.isEmpty ? '' : ' reason=$_reason'}';
  }

  Future<Map<String, dynamic>> _handle(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    if (name.startsWith('searchDiscoveryEvents')) {
      return {
        'feedVersion': 1,
        'radiusMiles': 25,
        'events': [
          for (final event in widget.fixture.firestore.events.values)
            if (const ['scheduled', 'active'].contains(event['status'])) event,
        ],
      };
    }
    if (name == 'getEventCapabilitiesV1') {
      if (!widget.fixture.firestore.events.containsKey(arguments['eventId'])) {
        throw FirebaseFunctionsException(
          code: 'not-found',
          message: 'Event not found.',
        );
      }
      return {
        'permissions': {'manageEvent': true, 'operateDoor': true},
        if (arguments['includeRemovalEligibility'] == true)
          'removalEligibility': {'canDelete': !_populated, 'eventRevision': 5},
      };
    }
    if (name == 'previewEventCancellationV1') {
      if (arguments['recurrenceScope'] != 'this_occurrence') {
        throw StateError('The nonrecurring preview must use this occurrence.');
      }
      return {'previewToken': 'local-preview-$_id', 'count': 3};
    }
    if (name == 'deleteEmptyEventV1' || name == 'cancelEventV1') {
      _mutationCalls++;
      final request = arguments['requestId'] as String;
      final previous = _receipts[request];
      if (previous != null) {
        _replays++;
        _updateDiagnostics();
        return previous;
      }
      if (arguments['expectedEventRevision'] != 5) {
        throw StateError('Fixture expected current event revision.');
      }
      if (name == 'deleteEmptyEventV1' && _populated) {
        throw StateError('Populated events must not be permanently deleted.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final cancelled = name == 'cancelEventV1';
      if (cancelled) {
        if (arguments['previewToken'] != 'local-preview-$_id') {
          throw StateError('Cancellation must use the reviewed preview.');
        }
        _reason = arguments['reason'] as String;
        widget.fixture.firestore.emitEvent({
          ...widget.fixture.firestore.events[_id]!,
          'status': 'cancelled',
          'eventRevision': 6,
        });
      } else {
        widget.fixture.firestore.events.remove(_id);
        widget.fixture.firestore.eventChanges.add(_id);
      }
      final result = <String, dynamic>{
        'status': cancelled ? 'cancelled' : 'deleted',
        'affectedEventIds': [_id],
      };
      _receipts[request] = result;
      _commits++;
      _updateDiagnostics();
      if (widget.scenario == 'lost-response') {
        throw FirebaseFunctionsException(
          code: 'unavailable',
          message: 'Fixture drops the first response after committing.',
        );
      }
      return result;
    }
    // The preview intentionally never sends registrations, messages, payments
    // or provider calls. Ancillary production widgets see empty read results.
    return {'admissions': <dynamic>[], 'registrations': <dynamic>[]};
  }

  void _remoteDelete() {
    widget.fixture.firestore.events.remove(_id);
    widget.fixture.firestore.eventChanges.add(_id);
    _diagnostics.value = 'Fixture remote deletion delivered';
  }

  Widget _discover() => AttendUsScaffold(
    title: 'Discover',
    selectedIndex: 0,
    destinations: const [
      AttendUsNavDestination(
        label: 'Home',
        icon: Icons.home_outlined,
        selectedIcon: Icons.home,
      ),
      AttendUsNavDestination(
        label: 'Groups',
        icon: Icons.apartment_outlined,
        selectedIcon: Icons.apartment,
      ),
      AttendUsNavDestination(
        label: 'Messages',
        icon: Icons.forum_outlined,
        selectedIcon: Icons.forum,
      ),
      AttendUsNavDestination(
        label: 'Profile',
        icon: Icons.person_outline,
        selectedIcon: Icons.person,
      ),
    ],
    onDestinationSelected: (_) {},
    onNotificationsPressed: () {},
    body: const HomeHubScreen(),
  );

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider.value(value: SubscriptionService()),
    ],
    child: MaterialApp(
      navigatorKey: _navigator,
      theme: AttendUsTheme.light,
      home: _withToolbar(
        widget.scenario == 'direct'
            ? SharedEventScreen(eventId: _id)
            : _discover(),
      ),
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '/');
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _withToolbar(
            uri.path.startsWith('/app/event/')
                ? SharedEventScreen(eventId: uri.pathSegments.last)
                : _discover(),
          ),
        );
      },
    ),
  );

  Widget _withToolbar(Widget child) => Column(
    children: [
      Material(
        color: const Color(0xFFFFF3CD),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ValueListenableBuilder<String>(
                valueListenable: _diagnostics,
                builder: (_, text, _) =>
                    Text(text, style: const TextStyle(fontSize: 11)),
              ),
              if (widget.scenario == 'remote')
                TextButton(
                  onPressed: _remoteDelete,
                  child: const Text('Remote delete fixture event'),
                ),
              TextButton(
                onPressed: () =>
                    _navigator.currentState!.pushNamed('/app/event/$_id'),
                child: const Text('Open fixture link'),
              ),
            ],
          ),
        ),
      ),
      Expanded(child: child),
    ],
  );

  @override
  void dispose() {
    _diagnostics.dispose();
    super.dispose();
  }
}
