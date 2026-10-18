# Persistent login deployment recovery

The October 18 candidate failed before deployment. Its Chromium accessibility trace shows the native dialog `close` event was absent at 24842.913 ms and present at 24851.151 ms. Dialog visibility and focus had already changed. The test now waits for the asynchronous event and still requires exactly one close plus trusted Escape input; no application behavior or assertion was removed.

Staging's retirement manifest expected 63 records but only 61 remained. Both missing records were retired QualificationScopes. Historical evidence for the first retained an October 7 expiry after retirement, and the collection has TTL enabled; this supports an expiry hypothesis, not a proven deletion cause.

With deployment recovery authorized, a read-only inventory validated all 61 retained records against their exact pinned content/version and confirmed only the two expected scope paths were absent. A single atomic commit created two new retirement markers using `exists: false` preconditions. They contain no actors, recipients, or expiry and are explicitly labeled as recreated markers with the original document hashes. No binding, setup, user, event, or production record was changed. These are new acknowledged writes, not claimed restoration of original document versions.

The exact plan, commit acknowledgement, and readback are in `web-retired-scope-repair-20261018.json`, canonical receipt SHA256 `6ec856558b4fdc7553e5e93309497f7fa952a76364831c310bfa944a7f97f9bf`. The manifest pins the new versions and retains each original hash and receipt linkage. All 63 records and the complete empty-staging prerequisite passed after repair at `2026-10-18T20:29:32.743Z`. All 27 retirement/rehearsal tests pass; release guards remain unchanged. Original failure and trace evidence are retained in workflow 39160955560 and the release worktree's build directory.

This repair permits a fresh candidate attempt; it does not qualify or promote production. Same-candidate executable acceptance and observation requirements still apply.
