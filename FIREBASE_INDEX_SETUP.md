# Firestore Index Management

`firestore.indexes.json` is the source of truth for AttendUs composite indexes
in both `attendus-staging` and `orgami-66nxok`. Do not create a console-only
index as the permanent fix for a query failure: add it to the manifest, add or
update its query-contract test, and let the release workflow deploy it.

## Public Discover index

The public Discover feed runs this query against `Events`:

- `private == false`
- `selectedDateTime > <48-hour cutoff>`

It therefore requires the collection-scope composite index:

1. `private` — ascending
2. `selectedDateTime` — ascending

The contract is declared by `PublicEventsRepository.requiredIndex` and checked
by `test/public_events_repository_test.dart`.

## Deployment

Main-branch Hosting releases call the reusable Firestore index workflow first.
That workflow:

1. deploys `firestore.indexes.json` to staging;
2. waits for every manifest index to report `READY` and rejects drift;
3. repeats the deployment and verification in production; and
4. allows Hosting to continue only after both projects pass.

For an index-only repair, manually dispatch **Deploy and Verify Firestore
Indexes** and select staging, production, or both. The production job is
restricted to `main` and manual dispatches.

The Firebase console link included in a `failed-precondition` error is useful
for identifying the required fields. If it is used during an emergency, export
the resulting index into `firestore.indexes.json` immediately so source control
and the deployed database cannot drift.
