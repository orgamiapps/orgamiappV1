# Logo Management for AttendUs

## Logo System Overview

AttendUs uses **two different logo versions** for different contexts:

1. **`attendus_logo_withText.png`** - Logo with "Attendus" text
   - Used in: Splash screen, Home Hub header, and other in-app UI elements
   
2. **`attendus_logo_only.png`** - Logo icon only (no text)
   - Used in: App icons (Android, iOS, Web), App Store listings, and favicon

### Current Logo Configuration

**In-App Logos** (configured in `lib/Utils/images.dart`):
- `Images.inAppLogo` → `attendus_logo_withText.png` (primary in-app logo)
- `Images.inAppLogoOnly` → `attendus_logo_only.png` (available for special uses)

**App Icons** (Android/iOS/Web):
- Generated from `attendus_logo_only.png` using the `replace_logo.sh` script

---

## Updating App Icons

### Automatic Method (Recommended)

1. **Ensure you have both logo files in the project root:**
   - `attendus_logo_withText.png` (for in-app use)
   - `attendus_logo_only.png` (for app icons)

2. **Run the replacement script:**
   ```bash
   ./replace_logo.sh
   ```

This script will:
- Generate app icons for Android, iOS, and Web from `attendus_logo_only.png`
- Clean and refresh Flutter cache
- Preserve in-app logo configuration

### Manual Replacement

If you prefer to do it manually or don't have ImageMagick installed:

1. **Update in-app logos:**
   - Edit `lib/Utils/images.dart` to change logo paths if needed
   - Both logo files should be in the project root and listed in `pubspec.yaml`

2. **In-app logo is used in these screens:**
   - Splash Screen (`lib/screens/Splash/splash_screen.dart`)
   - Second Splash Screen (`lib/screens/Splash/second_splash_screen.dart`)
   - Home Hub Screen (`lib/screens/Home/home_hub_screen.dart`)
   - Login Screen (`lib/screens/Authentication/login_screen.dart`)
   - Forgot Password Screen (`lib/screens/Authentication/forgot_password_screen.dart`)

3. **Clean Flutter cache after changes:**
   ```bash
   flutter clean
   flutter pub get
   ```

### App Icons (Optional but Recommended)
To update app icons on home screens:

**Android:** Replace icons in `android/app/src/main/res/mipmap-*/`
- mipmap-mdpi: 48x48px
- mipmap-hdpi: 72x72px
- mipmap-xhdpi: 96x96px
- mipmap-xxhdpi: 144x144px
- mipmap-xxxhdpi: 192x192px

**iOS:** Replace icons in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
- Various sizes from 20x20 to 1024x1024

**Web:** Replace icons in `web/icons/`
- Icon-192.png: 192x192px
- Icon-512.png: 512x512px

---

## Switching Between Logo Versions in Code

If you need to use the logo-only version in your Dart code:

```dart
// Logo with text (default for most screens)
Image.asset(Images.inAppLogo)

// Logo without text (available for special contexts)
Image.asset(Images.inAppLogoOnly)
```

---

## Verification

After any logo changes:

1. **Clean and rebuild:**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

2. **Check these locations:**
   - Splash screen shows logo with text
   - Home Hub header shows logo with text
   - App icon on device shows logo without text
   - Login/signup screens show appropriate logo version

3. **If old logos persist:**
   - Uninstall and reinstall the app
   - Clear app data/cache on your device

---

## File Structure

```
orgamiappV1-main-2/
├── attendus_logo_withText.png    # Logo with "Attendus" text
├── attendus_logo_only.png        # Logo icon only (no text)
├── lib/Utils/images.dart          # Logo path configuration
├── replace_logo.sh                # App icon generation script
└── pubspec.yaml                   # Assets declaration
```
