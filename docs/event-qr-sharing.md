# Organizer event QR sharing

The organizer action is **Share event QR**. It opens a bottom sheet below 600px and a centered dialog on larger screens. Both offer Event card (default) and QR only, plus Share image, Save image, Copy image, and Copy link.

## Implementation

- Images are generated locally as opaque 1080px PNGs, with integer-sized QR modules and at least four modules of clear margin. The card includes title, event-local date/time, branding, and a scan instruction.
- All destinations come from EventShareService.eventUri: production uses attendus.app; staging keeps its own origin. No attendance credentials or internal IDs appear in the artwork.
- Browser image operations run from the click with prepared PNG bytes. File sharing uses the browser share sheet; unsupported sharing gives explicit download/attachment instructions. Clipboard denial never silently substitutes link copying.
- Saving reports download initiation, not Photos completion. The manual-save fallback opens an actual image in a browser tab for long-press/right-click saving.
- Native sharing and saving retain the existing share_plus/system-sheet behavior. Native image copying remains unsupported in this website-first phase.
- The in-app scanner accepts validated website event URLs and maps them into the existing details-only route. Legacy codes remain supported; sharing does not check anyone in.
- No backend or dependency changes. Existing creator/manager authorization and private-event access controls remain in place.

## Verification

46 targeted Flutter tests passed across QR exports/dialog, event links, artifact downloads, creator access, event access controller, and event schedules. Includes 320px layout at 200% text, landscape, retry after render failure, and disposal during preparation. Scoped analysis passed. The production entrypoint compiled successfully in release mode into `build/qr-share-production` (including the Wasm compatibility dry run).

Local Chromium browser checks at desktop and phone viewport sizes verified real image/png clipboard content, copied links, both downloadable PNGs, and an actual browser image tab. Controlled browser adapter tests cover sharing payloads, cancellation, unsupported sharing, and clipboard denial. They do not establish OS delivery into Mail or Messages.

Evidence is under `build/qr-share-evidence/`; browser results are in `browser-results.json`. PNG decoding uses zxing-cpp installed only in `build/qr-python`, not an app dependency.

## Reproduce the local preview

```powershell
flutter build web --release --no-pub --target integration_test/qr_share_preview.dart --output build/qr-share-preview
node tests/browser/qr-share-preview.cjs
```

The preview entrypoint refuses non-loopback hosts. Never deploy that entrypoint. The browser test starts and closes its own local server and browser.

## Remaining device acceptance

Production deployment is not part of this change. Before release acceptance, verify real iPhone Safari and Android Chrome: download/long-press saving, clipboard paste into a supported app, sharing into Messages/Mail, scanning with the system camera, and opening the correct authorized event page. Desktop Safari, Firefox, and Edge require their own browser passes. Confirm a private event remains inaccessible to an unauthorized recipient. These checks are unverified locally.
