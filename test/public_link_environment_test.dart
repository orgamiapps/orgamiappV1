import 'package:attendus/Services/community_share_service.dart';
import 'package:attendus/Services/event_share_service.dart';
import 'package:attendus/Utils/app_constants.dart';
import 'package:attendus/firebase_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final environments = <String, String>{
    'production': 'https://attendus.app',
    'staging': 'https://attendus-staging.web.app',
    'emulator': 'http://127.0.0.1:4173',
  };
  for (final entry in environments.entries) {
    test(
      '${entry.key} builds and resolves only its own absolute record links',
      () {
        final links = PublicLinkConfiguration.forEnvironment(
          entry.key,
          debug: true,
        );
        final event = EventShareService.eventUri('shared-id', links: links);
        final community = CommunityShareService.communityUri(
          'shared-id',
          links: links,
        );
        expect(event.toString(), '${entry.value}/event/shared-id');
        expect(community.toString(), '${entry.value}/community/shared-id');
        expect(
          EventShareService.eventIdFromUri(event, links: links),
          'shared-id',
        );
        expect(
          CommunityShareService.communityIdFromUri(community, links: links),
          'shared-id',
        );
        for (final other in environments.entries.where(
          (item) => item.key != entry.key,
        )) {
          expect(
            EventShareService.eventIdFromUri(
              Uri.parse('${other.value}/event/shared-id'),
              links: links,
            ),
            isNull,
          );
          expect(
            CommunityShareService.communityIdFromUri(
              Uri.parse('${other.value}/community/shared-id'),
              links: links,
            ),
            isNull,
          );
        }
      },
    );
  }
  test('compiled public origin follows the selected Firebase environment', () {
    expect(
      AppConstants.publicWebDomain,
      environments[DefaultFirebaseOptions.environment],
    );
  });
  test(
    'staging accepts its secondary Hosting hostname without changing canonical links',
    () {
      final staging = PublicLinkConfiguration.forEnvironment('staging');
      final production = PublicLinkConfiguration.forEnvironment('production');
      final event = Uri.parse(
        'https://attendus-staging.firebaseapp.com/app/event/e1',
      );
      final community = Uri.parse(
        'https://attendus-staging.firebaseapp.com/app/community/g1',
      );
      expect(EventShareService.eventIdFromUri(event, links: staging), 'e1');
      expect(
        CommunityShareService.communityIdFromUri(community, links: staging),
        'g1',
      );
      expect(
        EventShareService.eventIdFromUri(event, links: production),
        isNull,
      );
      expect(
        CommunityShareService.communityIdFromUri(community, links: production),
        isNull,
      );
      expect(staging.canonicalOrigin, 'https://attendus-staging.web.app');
    },
  );
  test('relative application routes stay in the running environment', () {
    for (final environment in environments.keys) {
      final links = PublicLinkConfiguration.forEnvironment(
        environment,
        debug: true,
      );
      expect(
        EventShareService.eventIdFromUri(
          Uri.parse('/app/event/e1?action=ticket'),
          links: links,
        ),
        'e1',
      );
      expect(
        CommunityShareService.communityIdFromUri(
          Uri.parse('/community/g1'),
          links: links,
        ),
        'g1',
      );
    }
  });
  test(
    'parsers reject hostile schemes credentials authorities ports and encoded IDs',
    () {
      final links = PublicLinkConfiguration.forEnvironment('production');
      for (final url in [
        'http://attendus.app',
        'ftp://attendus.app',
        '//attendus.app',
        'https://attendus.app:8443',
        'https://attendus.app.evil.test',
        'https://user:password@attendus.app',
        'attendus://attendus.app',
      ]) {
        expect(
          EventShareService.eventIdFromUri(
            Uri.parse('$url/event/e1'),
            links: links,
          ),
          isNull,
          reason: url,
        );
        expect(
          CommunityShareService.communityIdFromUri(
            Uri.parse('$url/community/g1'),
            links: links,
          ),
          isNull,
          reason: url,
        );
      }
      expect(
        EventShareService.eventIdFromUri(
          Uri.parse('/event/a%2Fb'),
          links: links,
        ),
        isNull,
      );
      expect(
        CommunityShareService.communityIdFromUri(
          Uri.parse('/community/a%2Fb'),
          links: links,
        ),
        isNull,
      );
    },
  );
  test(
    'emulator origin overrides are debug-only local origins with exact ports',
    () {
      for (final origin in ['http://localhost:5000/', 'http://[::1]:5000']) {
        final links = PublicLinkConfiguration.forEnvironment(
          'emulator',
          debug: true,
          emulatorPublicOrigin: origin,
        );
        expect(
          links.accepts(Uri.parse('${links.canonicalOrigin}/event/e1')),
          isTrue,
        );
        expect(
          links.accepts(Uri.parse('http://127.0.0.1:4173/event/e1')),
          isFalse,
        );
        expect(
          () => PublicLinkConfiguration.forEnvironment(
            'emulator',
            emulatorPublicOrigin: origin,
          ),
          throwsStateError,
        );
      }
      for (final origin in [
        'https://attendus.app',
        'https://attendus-staging.web.app',
        'http://example.test',
        'http://127.0.0.1:4173/event',
        'http://user@localhost:4173',
        'http://localhost:4173?x=1',
        'http://localhost:4173#event',
        'http://localhost:0',
        'http://localhost:70000',
      ]) {
        expect(
          () => PublicLinkConfiguration.forEnvironment(
            'emulator',
            debug: true,
            emulatorPublicOrigin: origin,
          ),
          throwsStateError,
          reason: origin,
        );
      }
    },
  );
  test('unknown environments never default to production links', () {
    for (final environment in ['', 'development', 'stagging']) {
      expect(
        () => PublicLinkConfiguration.forEnvironment(environment),
        throwsStateError,
      );
    }
  });
}
