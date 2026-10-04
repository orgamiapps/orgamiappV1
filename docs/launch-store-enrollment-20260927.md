# Attendus store enrollment - owner steps

The owner requested help setting up Apple and Google developer accounts on 2026-09-27. The individual/company choice is pending. These owner steps do not block staging web/backend deployment. They do block signed store distribution and device qualification.

## First: choose the legal account owner

Use the actual legal owner of the app. For an existing registered company, review organization enrollment; otherwise review individual/personal enrollment. Do not invent a company identity or a D-U-N-S number. Apple's individual enrollment lists the individual legal name as seller; organizations use the legal entity name. Organization verification requires additional information, including a D-U-N-S number in the ordinary case.

Enter legal identity, address, payment and verification documents only in the provider's official enrollment interface. Do not send them or passwords, recovery codes, signing keys or certificates in chat.

## Enrollment

1. Apple: [Apple Developer Program enrollment](https://developer.apple.com/programs/enroll/). Sign in with the Apple Account the owner will retain, enable required two-factor authentication, choose the correct enrollment type, complete verification and membership payment. Apple lists USD 99 per membership year (local pricing can differ). Use the standard Apple Developer Program for App Store/TestFlight distribution.
2. Google: [Play Console setup instructions](https://support.google.com/googleplay/android-developer/answer/6112435?hl=en), then [Play Console](https://play.google.com/console/signup). The owner may use the existing `orgamiapps@gmail.com` Google account. Choose the truthful account type, complete identity/contact/device verification shown by Google and the USD 25 one-time registration payment. [Account-type guidance](https://support.google.com/googleplay/android-developer/answer/13634885?hl=en).
3. Report only whether each enrollment is pending/approved and the account owner/type. Membership approval is not app approval or device qualification.

New personal Play accounts have an additional production-access requirement: a closed test with at least 12 testers continuously opted in for at least 14 days, followed by a production-access application. An owned Galaxy alone does not satisfy it. [Google's current testing requirement](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en). This is separate from the Attendus owned-device pilot and its event-close plus 24-hour replay observation.

## After enrollment is approved

We will check existing app records and ownership before registering or replacing any permanent application identifier. Then create/verify separate staging and production Firebase/store app configuration, authentication providers and domains; configure protected GitHub environment signing credentials; run the local/CI preflight; create the signed TestFlight/Play internal builds; and guide installation on the owner's iPhone and Galaxy. An iPad tester remains outstanding.

The precise protected configuration names are in `launch-native-continuation-20260927.md`. Do not begin by pasting its secret values into chat. Store credentials directly in protected GitHub environments or another agreed protected store, and share only the locations/access status.

No account enrollment, legal agreement, purchase, signing upload or app-store submission has been performed by this agent.
