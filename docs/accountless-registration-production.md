# Accountless registration production runbook

Accountless registration is additive and fails closed. Keep
`AppConfig/publicWeb.accountlessRegistrationEnabled` and
`paidTicketCheckoutEnabled` false until every prerequisite below passes.

## Infrastructure prerequisites

- Enable Firebase anonymous authentication and keep App Check enforcement enabled.
- Create a Cloud KMS symmetric encryption key and grant the Functions runtime service
  account `roles/cloudkms.cryptoKeyEncrypterDecrypter` on that key.
- Store the full KMS resource name in `GUEST_CONTACT_KMS_KEY_NAME` and a random 32-byte
  or longer value in `GUEST_CONTACT_HMAC_KEY`.
- Configure the Microsoft Entra application certificate and restrict its `Mail.Send`
  application permission to `support@attendus.app`. Store
  `MICROSOFT_TENANT_ID`, `MICROSOFT_CLIENT_ID`, the base64url SHA-1 certificate
  thumbprint in `MICROSOFT_CERT_THUMBPRINT`, and the PEM PKCS#8 private key in
  `MICROSOFT_PRIVATE_KEY`.
- Guest registration accepts a full name and email address only. Microsoft Graph is the
  sole transactional delivery provider; no SMS provider or phone-only guest flow is deployed.
- Keep the live `STRIPE_SECRET_KEY`, publishable key, signed webhook secret, and webhook
  event subscriptions from the public-web rollout healthy.

Secrets stay in Secret Manager. The Admin application intentionally exposes health and
delivery state, never raw provider credentials.

## Release gates

1. Deploy Firestore rules, indexes, and TTL policies and wait for index readiness.
2. Deploy Functions and Hosting while accountless flags remain false.
3. Verify the function manifest, anonymous Auth, App Check, KMS round-trip, Microsoft
   test delivery, and signed Stripe fixtures.
4. Run a harmless RSVP against a real eligible event and verify the originating browser,
   management link, calendar file, cancellation, roster visibility, and audit log.
5. Enable `accountlessRegistrationEnabled` and email delivery. Enable
   `paidTicketCheckoutEnabled` only after the payment configuration gate passes.
6. Monitor registration errors, duplicate claims, inventory counters, webhook failures,
   delivery dead letters, suppression callbacks, and claim failures for at least one hour.

Use `node functions/tools/set-public-web-rollout.js accountless` for RSVP/free ticket
registration and `paid` only after paid prerequisites pass. The tool preserves the public
semantic pages and existing inline-registration configuration.

## Rollback

Rollback is configuration-only and does not delete guest records:

1. Disable paid guest checkout.
2. Disable accountless registration, which restores the account-required V1 action.
3. Disable inline registration only if the entire inline experience is unhealthy.
4. Keep public semantic pages online unless rendering itself is affected.

Queued confirmations remain retryable from Attendus Admin. Never delete a confirmed
registration because its email delivery failed.
