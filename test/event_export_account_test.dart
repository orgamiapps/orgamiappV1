import 'dart:async';
import 'package:attendus/Services/artifact_download_service.dart';
import 'package:attendus/Services/event_export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'account switch after export status prevents fetching the signed URL',
    () async {
      String? uid = 'a';
      final changes = StreamController<String?>.broadcast(sync: true);
      final status = Completer<Map<String, dynamic>>();
      var fetched = 0;
      var saved = 0;
      final service = EventExportService(
        currentUid: () => uid,
        accountChanges: () => changes.stream,
        call: (name, _) async =>
            name == 'createEventExportV2' ? {'jobId': 'job-a'} : status.future,
        fetch: (_) async {
          fetched++;
          return http.Response('private', 200);
        },
        save: (_, _) async {
          saved++;
          return const ArtifactDownloadResult(
            ArtifactDownloadStatus.downloadInitiated,
          );
        },
      );
      final result = service.download('event');
      await Future<void>.delayed(Duration.zero);
      uid = 'b';
      changes.add(uid);
      status.complete({
        'status': 'complete',
        'url': 'https://example.test/roster',
      });
      await expectLater(result, throwsStateError);
      expect(fetched, 0);
      expect(saved, 0);
      await changes.close();
    },
  );

  test(
    'switch away and back during HTTP cannot open the private export',
    () async {
      String? uid = 'a';
      final changes = StreamController<String?>.broadcast(sync: true);
      final response = Completer<http.Response>();
      final fetching = Completer<void>();
      var saved = 0;
      final service = EventExportService(
        currentUid: () => uid,
        accountChanges: () => changes.stream,
        call: (name, _) async => name == 'createEventExportV2'
            ? {'jobId': 'job-a'}
            : {'status': 'complete', 'url': 'https://example.test/roster'},
        fetch: (_) {
          fetching.complete();
          return response.future;
        },
        save: (_, _) async {
          saved++;
          return const ArtifactDownloadResult(
            ArtifactDownloadStatus.downloadInitiated,
          );
        },
      );
      final result = service.download('event');
      await fetching.future;
      uid = 'b';
      changes.add(uid);
      uid = 'a';
      changes.add(uid);
      response.complete(http.Response('private', 200));
      await expectLater(result, throwsStateError);
      expect(saved, 0);
      await changes.close();
    },
  );

  test(
    'same actor and filters resume the job, another actor gets a new job',
    () async {
      String? uid = 'a';
      final changes = StreamController<String?>.broadcast(sync: true);
      final jobs = <String>[];
      final observed = <String>[];
      var complete = false;
      final service = EventExportService(
        currentUid: () => uid,
        accountChanges: () => changes.stream,
        delay: (_) async {},
        call: (name, data) async {
          if (name == 'createEventExportV2') {
            jobs.add(uid!);
            return {'jobId': 'job-$uid'};
          }
          observed.add(data['jobId'] as String);
          return complete
              ? {'status': 'complete', 'url': 'https://example.test/roster'}
              : {'status': 'pending'};
        },
        fetch: (_) async => http.Response('private', 200),
        save: (_, _) async => const ArtifactDownloadResult(
          ArtifactDownloadStatus.downloadInitiated,
        ),
      );
      await expectLater(service.download('event'), throwsStateError);
      await expectLater(service.download('event'), throwsStateError);
      expect(jobs, ['a']);
      uid = 'b';
      changes.add(uid);
      complete = true;
      await service.download('event');
      expect(jobs, ['a', 'b']);
      expect(observed.last, 'job-b');
      await changes.close();
    },
  );

  test(
    'uncertain creation retry reuses the actor and filter idempotency key',
    () async {
      final keys = <String>[];
      final changes = StreamController<String?>.broadcast();
      final service = EventExportService(
        currentUid: () => 'a',
        accountChanges: () => changes.stream,
        call: (_, data) async {
          keys.add(data['idempotencyKey'] as String);
          throw StateError('offline');
        },
      );
      await expectLater(service.download('event'), throwsStateError);
      await expectLater(service.download('event'), throwsStateError);
      expect(keys[0], keys[1]);
      await expectLater(
        service.download('event', query: 'changed'),
        throwsStateError,
      );
      expect(keys[2], isNot(keys[0]));
      await changes.close();
    },
  );
}
