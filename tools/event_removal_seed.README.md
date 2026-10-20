# Supplemental removal fixture

This fixture supplies additional event-removal acceptance evidence. It does not replace any canonical release gate, observation, browser run, or device check.

Run it only against an exact, successfully deployed staging candidate whose committed source includes all four supplemental tools. The repository must be clean at that candidate's source SHA. The canonical seven-event pilot must already be seeded for the same candidate. Schedule this supplemental run between canonical collectors, before the canonical events close, with no concurrent fixture writers. The tools pin all seven canonical event versions and stop on any change, including a legitimate concurrent canonical operation.

The fixture uses a new standard `webqa-YYYYMMDD-hash` run ID with `purpose: event-removal-live`. It creates three new accounts, one community, six events, two memberships, and six explicitly synthetic history records. The viewer saves five events, including an unchanged private sentinel. The outsider has no community membership. No existing account, event, canonical binding, AppConfig, secret, or payment-provider setting is modified.

The first atomic commit creates the scope, ten bindings, and immutable `QualificationSetup` lineage with `state: provisioning`. Three account creates follow. The final atomic commit creates 21 business documents. Completion is recorded in a private local receipt and seeded fixture; no cloud update is needed. The immutable provisioning lineage remains usable for later explicit retirement even after a partial failure.

From the integrated repository, prepare a new private context:

```text
node tools/seed_event_removal_qualification.js prepare --repo <repo> --candidate <staging-candidate.json> --receipt <deployment-receipt.json> --canonical <canonical-private-context.json> --directory <repo>/build/<new-private-directory>
```

Preparation is local only. It copies the exact staging Firebase, real Enterprise App Check site key, and Maps configuration from the canonical private context. It generates new random account passwords. The directory must be new, under the repository's ignored `build` tree, and must remain private. Never copy credential contexts or journals to public outputs.

After reviewing the prepared context, use its path in the one-shot apply command:

```text
node tools/seed_event_removal_qualification.js apply --repo <repo> --candidate <staging-candidate.json> --receipt <deployment-receipt.json> --context <private-directory>/prepared-fixture-private.json
```

The prepared context must be less than two hours old. Read-only deployment capture requires the existing authorized Google ADC and Firebase CLI identity. Administrative fixture calls use fresh Google auth headers, or an already authorized `ATTENDUS_AUDIT_ACCESS_TOKEN` supplied only through the process environment. Native fetch performs each mutation once, rejects redirects, and never retries an authorization error or lost response. Tokens and passwords are never printed or included in public reports. Nested Firebase CLI output is captured inside a bounded worker.

Before creating data, apply checks exact deployment identity, empty ownership paths, account UID/email absence, and existing canonical events. The write-once journal records each mutation intent before the request. Readback verifies every seeded field, allowing only the discovery metadata fields added by the deployed event maintenance trigger. Seeded owner counters are six events and one group; current source increments these counters during publication callables rather than direct document creation.

On success, the command returns the path to `seeded-fixture-private.json`, which the browser harness consumes. The read-only observer checks only the supplemental scope and seven canonical event versions. It rejects another project, emulator/debug environments, incomplete or expanded scope bindings, and history reassigned to another attendee.

Any uncertain result or interrupted journal requires read-only reconciliation:

```text
node tools/seed_event_removal_qualification.js reconcile --repo <repo> --candidate <staging-candidate.json> --receipt <deployment-receipt.json> --context <private-directory>/prepared-fixture-private.json
```

Reconciliation reports missing, exact, and changed planned records and scoped account counts. It never resumes, retries, repairs, or deletes anything. Preserve the original context and journal. An operator must inspect acknowledged and uncertain outcomes before preparing any separately authorized recovery or retirement action.

Offline validation:

```text
node --test tools/event_removal_seed.test.js tools/event_removal_live.test.js
```

These tests use injected provider fakes and temporary local files. They perform no cloud calls. Live browser acceptance still requires real App Check, the actual deployed client, two online sessions, preserved history, and retained evidence from the exact candidate.
