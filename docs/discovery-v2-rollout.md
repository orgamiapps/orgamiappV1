# Discovery V2 rollout

Discovery V2 is disabled unless `AppConfig/discovery` explicitly contains:

```json
{
  "useLegacyFeed": false,
  "marketplaceExperienceVersion": 2
}
```

Missing or invalid configuration selects V1. A failed V2 callable also falls back to V1 for the current app session. `useLegacyFeed: true` remains the emergency rollback and prevents marketplace initialization.

## Staging

1. Deploy Functions while V1 remains selected.
2. Run the category backfill as a dry run:

   ```sh
   cd functions
   node tools/backfill-discovery-categories.js --project attendus-staging
   ```

3. Review the eligible and changed counts, then repeat with `--apply`.
4. Seed active public events across all 15 category IDs.
5. Enable V2 explicitly:

   ```sh
   node tools/set-discovery-rollout.js --project attendus-staging --marketplace --experience-version 2
   ```

6. Verify home, category filtering, search pagination, saves, navigation, empty states, App Check, and Authentication.

## Production

Repeat the dry run and applied backfill for `orgami-66nxok`, deploy Functions and hosting from the same tested revision, then enable V2:

```sh
cd functions
node tools/backfill-discovery-categories.js --project orgami-66nxok
node tools/backfill-discovery-categories.js --project orgami-66nxok --apply
node tools/set-discovery-rollout.js --project orgami-66nxok --marketplace --experience-version 2
```

Monitor callable errors, category no-result rate, event-detail CTR, saves, and registrations. To return to V1 without using the legacy feed, set `--experience-version 1`. For an emergency rollback:

```sh
node tools/set-discovery-rollout.js --project orgami-66nxok --legacy --experience-version 1
```

Keep the V1 callables and legacy feed deployed for one full release cycle.
