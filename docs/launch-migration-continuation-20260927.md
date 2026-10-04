# Migration continuation evidence — 2026-09-27

Status: implemented locally; four dedicated unit tests and targeted ESLint passed. The dedicated emulator test is handed to the integrator for the combined run. No migration CLI, production dry run, export, import, apply, or live recovery verification was executed in this segment. Existing saved inventory/dry-run reports were not changed.

## Implemented

- `functions/events/migration.js`: canonical version-2 source fingerprints tolerate document/field ordering; archive proof checks the original stamp, complete source/manager correction set and actual current source correspondence. Proof fingerprints include the affected historical records, correction documents, protected identity records and admission groups.
- `functions/tools/complete-launch-migration.js`: per-attendance checkpoints persist source/archive fingerprints. Resumption revalidates source and complete archive proof before reuse. Final counter/review-flag publication verifies every item transactionally and records the resulting source fingerprint, archive aggregate and attendance totals. `already_complete_verified` requires a transactional re-read matching those results; changed revisions, source records or archive/correction state block reuse. Concurrent item checkpoints cannot overwrite a completed checkpoint with `archiving`.
- Apply requires a new version-2 dry run with pre-migration archive-state fingerprints. Existing reports cannot silently pass the stronger contract. In addition to `--apply-report`, `--project` and `--backup-object`, apply requires explicit `--export-operation`, `--restore-operation`, `--restore-project`. Operation names identify existing completed operations; the script does not create exports/imports. It fetches their live status, rejects wrong source/destination/project/partial collection scope, requires the same export URI, and compares the live isolated restored Events/admission/attendance and affected archive/identity/group scope with the approved plan. Metadata size/generation is only supplemental object identity, not recovery proof.
- Missing approved events and changed/ambiguous/failed verification items are reported explicitly and set a nonzero result. Importing the module for tests no longer starts the CLI.

## Tests

`node --test test/launch-migration-continuation.test.js`: 4/4 passed (order stability/revision drift, completed checkpoint reuse, original/correction tampering, incomplete/wrong/partial recovery operation rejection).

`npx --no-install eslint events/migration.js tools/complete-launch-migration.js test/launch-migration-continuation*.test.js`: passed on the final owned-file candidate.

`test/launch-migration-continuation-emulator.test.js`: added local-only test for preserved source, item checkpoint, verified replay, revision change and correction tampering. Integrated result belongs in the main acceptance ledger.

## Remaining gates

- Live cloud export/import-operation validation and actual isolated restoration have not run. Recovery evidence covers the specified Firestore event/archive scope, not Auth/Storage or the full application. Source/configuration/artifact recovery and retained backup-object protections remain release requirements.
- Existing v1 dry-run report must be regenerated and reviewed. No production report refresh occurred here.
- Full per-event queries and final aggregate verification remain bounded by Firestore transaction limits; large-event stress and failure/restart/concurrent-source rehearsal are still required. Item checkpoints reduce repeated archival but are not a paginated source-inventory implementation.
- Orphaned records outside event-linked source queries, review/ambiguous link resolution, original legacy evidence provenance, permanent admission/re-entry reconciliation and schedule activation qualification remain open. Archive snapshots without verifiable current/original evidence fail closed.
- Named schedule ambiguity, verified backup/rehearsal, production reconciliation, signed/client acceptance, deployment and observation gates remain open.

The recovery fields follow the official [Firestore export metadata contract](https://docs.cloud.google.com/firestore/docs/reference/rest/Shared.Types/ExportDocumentsMetadata) and [import URI contract](https://firebase.google.com/docs/firestore/reference/rest/v1beta1/projects.databases/importDocuments). A successful operation plus live scope comparison is narrower than claiming all recovery requirements satisfied.
