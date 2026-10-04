# Public web production runbook

Attendus public event and opt-in community pages are served by the `publicWeb`
Gen 2 HTTP function through ordered Firebase Hosting rewrites. The Flutter shell
remains the fallback for `/app/event/{id}` and `/app/community/{id}`.

## Production controls

`AppConfig/publicWeb` contains three fail-closed flags:

- `publicPagesEnabled`: enables semantic event pages, opted-in community pages,
  and XML sitemaps.
- `inlineRegistrationEnabled`: enables inline RSVP and free-ticket actions.
- `paidTicketCheckoutEnabled`: enables paid Stripe checkout.

Use `npm --prefix functions run public-web:rollout -- --project orgami-66nxok
--mode disabled|pages|registration|paid`. Each broader mode includes the modes
before it. Missing or invalid configuration is treated as disabled.

## Required configuration

- Secret Manager: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, and
  `GOOGLE_PLACES_API_KEY`.
- `AppConfig/publicWeb.appCheckSiteKey`: production reCAPTCHA Enterprise site
  key used by the lightweight action bundle.
- `AppConfig/publicWeb.stripePublishableKey`: a live Stripe publishable key.
- Firebase Authentication authorized domains include `attendus.app` and
  `www.attendus.app`.
- Stripe webhook URL:
  `https://us-central1-orgami-66nxok.cloudfunctions.net/stripeWebhook`.

The webhook subscribes to `payment_intent.succeeded`,
`payment_intent.payment_failed`, `payment_intent.canceled`, `charge.refunded`,
and `charge.dispute.created`. Its signature is the sole authority for paid
ticket issuance and inventory release.

## Release checks

1. Run Functions lint/tests and the Flutter analyzer/tests.
2. Run `node tools/check_public_web_contract.js` and the Firestore query/index
   contract checks.
3. Deploy rules and indexes, then wait for the reservation index to be ready.
4. Deploy all Functions with every public-web flag disabled.
5. Run `public-web:backfill` first as a dry run, then with `--apply`; repeat until
   `changed: 0`. Run `public-web:validate` afterward.
6. Build and deploy Hosting, then enable pages, registration, and paid checkout
   one level at a time with verification between each change.

Public HTML must not request Flutter assets. Private, unpublished, pending,
moderated, or missing records must return the same noindex 404 response.

## Rollback

Roll back in this order: `paid` to `registration`, `registration` to `pages`,
then `pages` to `disabled`. If rendering is unhealthy, restore the previous
immutable Hosting release after disabling pages. Leave the Functions and
projections deployed for diagnosis.

## Payment validation limitation

The initial production release intentionally validates Stripe with automated
mocks, signed webhook fixtures, configuration inspection, and harmless negative
canaries only. It does not create a real charge. The first real paid transaction
therefore remains a monitored first-transaction risk.
