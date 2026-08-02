# Production security baseline — 2026-08-01

Project: `orgami-66nxok`

This baseline was captured before the comprehensive hardening rollout. The
production web release was Hosting version `69a43a09e9e92b31`, finalized at
`2026-08-02T01:59:48Z`. Source commit `1645c6e` is tagged
`production-web-2026-08-01`.

## Function inventory

The deployed inventory contained 40 functions. Source/deployment comparison
found two live-only functions:

- `setSelfAdmin` — active callable, hash `84eb6e554a91abe8d093f943fb0200fcdef6ff68`
- `aggregateAttendance` — failed HTTP function, hash `4305b942277405bb64acb4a0b8471c50f6627779`

Both orphaned functions were deleted from `us-central1` on 2026-08-01 and a
follow-up inventory confirmed that neither remained deployed.

The remaining deployment includes payment, notification, messaging, Places,
analytics, account-lifecycle, scheduled, and admin functions. Several legacy
functions were already in the `FAILED` state; they are retained in this record
until source owners decide whether to repair or remove each one.

## Recovery boundaries

- Existing application and payment data must be preserved with additive
  migrations and verified backups before destructive cleanup.
- Facial templates are denied to all clients immediately. Quarantine and final
  deletion are separate, auditable operations.
- Unsafe payment and entitlement mutation paths remain disabled until the
  server-authoritative Stripe contract and signed webhook pass staging tests.
- Hosting rollback uses retained Firebase Hosting releases; the Git tag above
  identifies the matching source baseline.

