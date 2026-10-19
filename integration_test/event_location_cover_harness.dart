// Local UI-only fixture. Never initializes Firebase or writes production data.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendus/Utils/attendus_theme.dart';
import 'package:attendus/Services/event_wizard_service.dart';
import 'package:attendus/models/event_wizard_model.dart';
import 'package:attendus/screens/Events/event_creation_wizard_screen.dart';
import '../test/support/wizard_fake.dart';

class LocalCoverRepository extends TestWizardRepository {
  LocalCoverRepository(this.preferences);
  final SharedPreferences preferences;
  @override
  Future<EventWizardDraft> saveDraft(EventWizardDraft draft) async {
    await super.saveDraft(draft);
    await preferences.setString(
      'cover-fixture-draft',
      jsonEncode({
        'id': draft.draftId,
        'revision': draft.revision,
        'formData': draft.toFormJson(),
      }),
    );
    return draft;
  }

  @override
  Future<String> uploadDraftImage({
    required EventWizardDraft draft,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    return 'data:$contentType;base64,${base64Encode(bytes)}';
  }

  @override
  Future<EventWizardPublishResult> publish(
    EventWizardDraft draft, {
    int? expectedEventRevision,
    String? changeReason,
    String? changePreviewToken,
    String recurrenceScope = 'this_occurrence',
  }) async {
    await preferences.setString(
      'cover-fixture-event',
      jsonEncode(draft.toFormJson()),
    );
    return super.publish(draft);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(
    MaterialApp(
      theme: AttendUsTheme.light,
      home: CoverFixtureHome(preferences: preferences),
    ),
  );
}

class CoverFixtureHome extends StatefulWidget {
  const CoverFixtureHome({super.key, required this.preferences});
  final SharedPreferences preferences;
  @override
  State<CoverFixtureHome> createState() => _CoverFixtureHomeState();
}

class _CoverFixtureHomeState extends State<CoverFixtureHome> {
  @override
  Widget build(BuildContext context) {
    final saved = widget.preferences.getString('cover-fixture-event');
    final event = saved == null
        ? null
        : jsonDecode(saved) as Map<String, dynamic>;
    return Scaffold(
      appBar: AppBar(title: const Text('Local event cover verification')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'UI fixture only; no production writes. Reload to verify the saved cover.',
          ),
          if (event != null) ...[
            Text(event['title'] as String),
            Text(event['location'] as String),
            if ((event['imageUrl'] as String).isNotEmpty)
              Image.memory(
                base64Decode((event['imageUrl'] as String).split(',').last),
                height: 240,
                semanticLabel: 'Published event cover',
              ),
          ],
          FilledButton(
            onPressed: () async {
              final storedDraft = widget.preferences.getString(
                'cover-fixture-draft',
              );
              final draft = storedDraft == null
                  ? (EventWizardDraft.blank(
                        selectedDateTime: DateTime(2027, 6, 1, 12),
                      )
                      ..title = 'Text location and cover verification'
                      ..description = 'Local creation flow verification.'
                      ..primaryDiscoveryCategoryId = 'community-causes')
                  : EventWizardDraft.fromJson(
                      jsonDecode(storedDraft) as Map<String, dynamic>,
                    );
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => EventCreationWizardScreen(
                    initialDraft: draft,
                    service: LocalCoverRepository(widget.preferences),
                    pickCoverBytes: () async => (await rootBundle.load(
                      'attendus_logo.png',
                    )).buffer.asUint8List(),
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
            child: const Text('Open event editor'),
          ),
        ],
      ),
    );
  }
}
