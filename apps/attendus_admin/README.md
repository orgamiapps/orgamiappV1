# Attendus Admin

Secure Flutter Windows console for the Attendus Firebase project. The application authenticates with Firebase Auth and calls the secured `adminApi` over HTTPS. It has no direct privileged Firestore access and contains no server credentials.

## Local development

Use a Firebase API key that is restricted in Google Cloud to only the required Firebase APIs. Do not commit it.

```powershell
$env:ATTENDUS_FIREBASE_API_KEY = "restricted-public-firebase-key"
$env:ATTENDUS_GOOGLE_OAUTH_CLIENT_ID = "desktop-client-id.apps.googleusercontent.com"
flutter run -d windows --dart-define="ATTENDUS_FIREBASE_API_KEY=$env:ATTENDUS_FIREBASE_API_KEY" --dart-define="ATTENDUS_GOOGLE_OAUTH_CLIENT_ID=$env:ATTENDUS_GOOGLE_OAUTH_CLIENT_ID" --dart-define="ATTENDUS_ADMIN_API_URL=http://127.0.0.1:5001/orgami-66nxok/us-central1/adminApi"
```

The API must be deployed or running in the Firebase Emulator Suite. A valid administrator needs both the `admin: true` custom claim and an active `admin_roles/{uid}` document. Never create either from this desktop client.

Email/password and Google sign-in are supported. Before using Google sign-in, enable the Google provider in Firebase Console under **Authentication → Sign-in method** for `orgami-66nxok`. In Google Cloud Console, open **APIs & Services → Credentials**, create an OAuth 2.0 Client ID with application type **Desktop app**, and supply its public client ID as `ATTENDUS_GOOGLE_OAUTH_CLIENT_ID` when building. Do not create or embed a client secret. The Windows client opens the system browser, obtains short-lived Google tokens, and exchanges them for a Firebase credential. The selected Google email must represent a Firebase Auth user with the required administrator claim and role.

## Installer

Install Flutter, Visual Studio 2022 Desktop development with C++, and Inno Setup 6 on the build machine only. The target Windows 11 x64 PC needs none of them. Then run:

```powershell
$env:ATTENDUS_FIREBASE_API_KEY = "restricted-public-firebase-key"
$env:ATTENDUS_GOOGLE_OAUTH_CLIENT_ID = "desktop-client-id.apps.googleusercontent.com"
.\scripts\build_admin_windows.ps1 -Version 1.0.0
```

The installer is emitted under `dist/`. Inno Setup is preferred; when it is unavailable, the build script creates a properly manifested MSIX with the installed Windows SDK. Local installers may be unsigned. Production installers and the application executable should be Authenticode-signed with an organization-validated code-signing certificate (preferably EV or managed signing), timestamped, malware-scanned, and the SHA-256 checksum published. Set `ATTENDUS_SIGNING_PFX` and `ATTENDUS_SIGNING_PFX_PASSWORD` for an approved MSIX signing certificate. Signing is intentionally not automated without an approved certificate/key provider.

## First administrator

Do not run until the owner explicitly confirms the exact email. Authenticate Application Default Credentials to `orgami-66nxok`, then:

```powershell
cd functions
gcloud auth application-default login
npm run bootstrap:super-admin -- --project orgami-66nxok --email confirmed@example.com --confirm "BOOTSTRAP:confirmed@example.com"
```

The CLI verifies that the Auth user exists, merges the claim, writes the role, and creates an audit record. It is not an HTTPS function.
