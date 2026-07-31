# Attendus Admin architecture and security design

## Scope and trust boundaries

`apps/attendus_admin` is an untrusted Windows client. It contains only the public Firebase Windows configuration, authenticates with Firebase Authentication, refreshes the Firebase ID token, and sends it as `Authorization: Bearer <token>` to `adminApi`. It never receives service-account, Stripe, GitHub, or other server credentials and does not use Firestore for privileged reads or writes.

`functions/admin` is the sole privileged administration boundary. Every `/v1` request receives a request ID, verifies the ID token, requires the coarse `admin: true` custom claim, loads `admin_roles/{uid}`, checks an endpoint permission, validates input, rate-limits the caller, and records every successful mutation in `admin_audit_logs`. Destructive calls additionally require `confirmed: true`, a human reason of at least 10 characters, and an idempotency key.

The Admin SDK bypasses Firestore rules, so server authorization is mandatory on every route. Firestore rules deny all client writes to admin, entitlement, aggregate, payment, and job collections. Audit documents are created with `DocumentReference.create`; neither the API nor clients expose an update/delete path.

## Roles

| Role | Intended permissions |
|---|---|
| `super_admin` | all permissions, including role management |
| `support` | account reads, disable/session-reset/password-reset/anonymization workflow |
| `billing_admin` | subscription reads and server-side Stripe mutations/refunds |
| `analyst` | aggregate analytics and CSV exports |
| `moderator` | reports, events, and organizations; moderation mutations |

Roles are additive. A role document has `roles`, `active`, `updatedAt`, and `updatedBy`. Only `super_admin` can assign roles. No endpoint permits `billing_admin` (or any other non-super role) to grant `super_admin`.

## API contract

The exported v2 HTTPS function is `adminApi`; routes are under `/v1`. Responses are JSON envelopes: `{data, meta:{requestId}}` or `{error:{code,message,details,requestId}}`. Lists use bounded `limit` and opaque page tokens. Mutations require `Idempotency-Key`; completed responses are cached in `admin_idempotency` under the caller/key hash.

Read routes cover the current administrator, dashboard/current and daily metrics, accounts/detail, subscriptions, reports, events, organizations, audit logs, and jobs. Mutation routes cover account disable/enable, token revocation, password-reset link generation, delete/anonymization job creation, role changes, subscription cancellation/reactivation/change/sync/refund, report resolution, and job cancellation.

Stripe is authoritative for billing status, prices, periods, cancellations, and refunds. The API accepts only configured plan aliases mapped to server-side Stripe price IDs. It never accepts an amount or entitlement flag. Firestore subscription entitlements are derived from Stripe objects.

## Existing schema inventory

The public application models and functions use `Customers` (`uid`, `name`, `email`, `username`, profile/contact fields, `createdAt`, creation counters), `users` plus notification/settings subcollections, `Events` (owner `customerUid`, title/status/date/location/privacy/ticket and organization fields), `Organizations` (`createdBy`, name/category/visibility/location) and Members/Feed/JoinRequests, `subscriptions` (user/plan/tier/status, Stripe IDs, period/trial/scheduled-change/payment fields), `Attendance`, `Tickets`, `Messages`, `Conversations`, `reports`, `event_analytics`, `user_analytics`, notification collections, `TicketPayments`, `TicketUpgradePayments`, and `FeaturePayments`. DTO serializers in the API select explicit fields and never return raw snapshots.

The known plan aliases are `basic_monthly`, `basic_6month`, `basic_yearly`, `premium_monthly`, `premium_6month`, and `premium_yearly`. Price IDs must be supplied as environment/secrets configuration; prices or entitlements are never taken from desktop input.

## Metrics

Dashboard reads use `admin_metrics_current/current` and range queries on `admin_metrics_daily/{yyyy-mm-dd}`. Scheduled aggregation computes user totals/growth, DAU/WAU/MAU, event/registration/check-in totals, active Basic/Premium, trial conversion, churn, MRR/ARR, refunds, failed payments, group growth, and open reports. The request path never performs full-database dashboard scans.

## Bootstrap and operations

`functions/admin/bootstrap-super-admin.js` is a local-only CLI using Application Default Credentials. It requires project ID and email flags plus an explicit confirmation phrase, verifies the Auth user, merges the coarse claim without deleting existing claims, creates the role document, and appends an audit record. It is not exported. Do not run it until the administrator email is explicitly confirmed.

Production rollout order is: provision secrets and plan-to-price mapping; run emulator/rules/backend/Flutter tests; deploy functions; smoke-test with a non-admin; explicitly bootstrap the first administrator; deploy rules; install a signed Windows build; monitor function errors/audits. Roll back by disabling admin role documents, reverting the function revision, reverting rules to the last reviewed production rules (never the development catch-all), and uninstalling the client. Audit logs must be retained.

## Audit findings

The prior deployed `firestore.rules` declared development rules and ended with authenticated read/write access to every unmatched path. It also allowed clients to write subscriptions. `setAdminByEmail` shadowed the Admin SDK with a boolean and relied only on a coarse claim; analytics backfill checked authentication only. The new design removes client admin/entitlement writes, corrects both functions, and adds role-aware server checks. Existing ticket-payment functions still accept client amount metadata and should be migrated to a server-side price/catalog lookup before a separate production payment security review.
