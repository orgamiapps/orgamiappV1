# Production website release — 2026-09-27

The owner explicitly requested publication to attendus.app while deferring launch completion. The website is deployed; launch completion remains open.

- Artifact: `a41354df5c5d6232bbc8a0b3785cd5d7cd57accf7a8b6f8108ee9fb7245895a9`.
- Hosting release: `projects/951311475019/sites/orgami-66nxok/releases/1790547311174000`.
- Hosting version: `projects/951311475019/sites/orgami-66nxok/versions/945968711b33e5e1`.
- Previous version retained for rollback: `projects/951311475019/sites/orgami-66nxok/versions/e0b3b60897962a19`, previous release `1790476984806000`.
- Evidence: `build/production-web-20260927/`; frozen source/artifact hashes in `candidate.json`, live inventory in `after.json`.

## Deployment scope and checks

Built once with production Firebase, Maps and App Check configuration. Compilation passed; initial bundle 1.209 MB gzip against 1.800 MB budget. Native-association generation correctly stopped because verified Apple identity is unavailable. Resumed packaging of the same compiled artifact after copying the two existing production association files byte-for-byte; verified those bytes after publication. No fabricated signing identity or native qualification claim.

548 files published, including 63 current immutable assets and seven retained releases. Local and both-domain checks passed for 525 immutable assets and 14 current deferred chunks. Source/artifact drift and previous-release checks passed immediately before publication; postflight drift was empty. Browser guest homepage rendered Discover, login, categories and live event cards. Authenticated workflows, responsive/device matrix and full functional acceptance remain unqualified.

Compatibility review uncovered a real inventory defect: `Object.assign(exports, ...)` endpoints were omitted by the regex manifest checker, and the event-change preview was not exported. Replaced the dynamic assignments with explicit exports, added the preview export, and added a regression test comparing parsed inventory with actual runtime Firebase endpoints. Three manifest tests and backend lint passed. Earlier reports that all expected staging Functions were present referred to an incomplete inventory and must not be treated as complete backend coverage.

Before publishing Hosting, deployed 24 additive website dependencies: launch-operation callables, roster projection triggers, announcement/export workers and retry worker, plus event-change preview. Exact targets are in `backend-targets.txt`. All 24 verified ACTIVE; production now has 135 Functions. All original 111 Functions retain their previous revisions/update timestamps. Anonymous requests to capabilities, admissions and change-preview endpoints returned the expected 401 UNAUTHENTICATED. This does not qualify authenticated operations or provider delivery.

No production migration apply, existing backend replacement, rules update, native signing/distribution, Wallet activation or launch-completion claim was made in this pass. New triggers/workers can maintain derived data as their source records change; this is not a claim that backend data will remain static. Previous additive indexes remain available. Existing backend behavior is still older than portions of the local candidate, so full end-to-end compatibility remains a separate gate.

## Remaining gates

Production counter/schedule reconciliation, isolated backup/recovery rehearsal, unfinished lifecycle/export/deletion implementation, retention review, authenticated acceptance, signed TestFlight/Play builds including iPad coverage, owned offline-device pilot and event-close plus 24-hour observation remain open. Staging needs the corrected complete runtime inventory reconciled before it can serve as full backend qualification evidence. Source changes are preserved without commit or push.

Rollback should restore the previous Hosting version and gate affected entry points while retaining compatible additive APIs, indexes and history. Do not delete user data or blindly remove new workers to roll back the website.
