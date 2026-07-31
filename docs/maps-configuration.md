# Google Maps configuration

Attendus uses separate Google Maps keys for web, Android, iOS, and the
authenticated Firebase Places proxy. Do not reuse a key between platforms.

## Required Google Cloud APIs

Enable billing for `orgami-66nxok`, then enable Maps JavaScript API, Maps SDK
for Android, Maps SDK for iOS, Places API (New), and Geocoding API. Configure
quotas, billing alerts, and usage monitoring before release.

## Client keys

- Web: restrict to Maps JavaScript API and HTTP referrers for `attendus.app`,
  the Firebase Hosting domains, preview channels, and localhost. Add it as the
  GitHub Actions secret `GOOGLE_MAPS_WEB_API_KEY`, or pass it locally with
  `--dart-define=GOOGLE_MAPS_WEB_API_KEY=...`.
- Android: restrict to Maps SDK for Android, package
  `com.stormdeve.orgami`, and every release/debug SHA fingerprint. Put
  `GOOGLE_MAPS_ANDROID_API_KEY=...` in the uncommitted
  `android/local.properties`, or provide the same environment variable.
- iOS: restrict to Maps SDK for iOS and bundle identifier
  `com.stormdeve.orgami`. Copy `ios/Flutter/Maps.xcconfig.example` to
  `ios/Flutter/Maps.xcconfig` and replace the placeholder.

## Server key

Restrict the server key to Places API (New) and Geocoding API. Store it as a
Firebase Functions secret and deploy the three callable functions:

```sh
firebase functions:secrets:set GOOGLE_PLACES_API_KEY --project orgami-66nxok
firebase deploy --only functions:placesAutocomplete,functions:placeDetails,functions:reverseGeocode --project orgami-66nxok
```

The callable Cloud Run services allow public transport invocation so Firebase
can receive the request, but the handlers reject missing and anonymous Firebase
authentication before contacting Google. If local function discovery exceeds
the Firebase CLI default timeout on Windows, deploy with:

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '60'
firebase deploy --only "functions:placesAutocomplete,functions:placeDetails,functions:reverseGeocode" --project orgami-66nxok
```

## Local Android readiness

The Gradle 8.13 wrapper is tracked in the repository. Android builds use JDK 17,
Kotlin 2.3.10, compile SDK 36, and NDK 28.2.13676358 (required by the `jni`
plugin). After
installing the Android command-line tools, accept the
Google Android SDK licenses interactively (license acceptance cannot be checked
into this repository), then install the required packages:

```powershell
$sdkManager = "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat"
& $sdkManager --sdk_root="$env:LOCALAPPDATA\Android\Sdk" --licenses
& $sdkManager --sdk_root="$env:LOCALAPPDATA\Android\Sdk" `
  "platform-tools" "platforms;android-36" "build-tools;36.0.0"
& $sdkManager --sdk_root="$env:LOCALAPPDATA\Android\Sdk" `
  "ndk;28.2.13676358"
flutter doctor -v
Push-Location .\android
.\gradlew.bat signingReport
Pop-Location
flutter build apk --release
```

The current Android release build still uses the debug signing configuration.
Configure the production upload keystore before publishing to Play; its SHA-1
and SHA-256 fingerprints must be included on the restricted Android Maps key.

## Web preview verification

Build with the restricted web key and deploy an expiring Hosting preview. The
web key's HTTP referrers must include the project-specific preview pattern
`https://orgami-66nxok--*.web.app/*`.

```powershell
flutter build web --release --dart-define="GOOGLE_MAPS_WEB_API_KEY=$env:GOOGLE_MAPS_WEB_API_KEY"
firebase hosting:channel:deploy maps-integration --expires 7d --project orgami-66nxok
```

Use a signed-in, non-anonymous test account to search for a place, create an
in-person event, verify its Firestore coordinates and map marker, then create an
online event and verify it has no coordinates or marker. Repeat on Android and
on a macOS/Xcode machine for iOS before promoting the web build or releasing
mobile clients.

Do not revoke the previously shared/Firebase key during this rollout. After all
released clients use their restricted keys, audit its traffic and remove Maps
permissions only after signup has its own restricted solution. Retain any
Firebase API access required by the existing Firebase client configuration.
