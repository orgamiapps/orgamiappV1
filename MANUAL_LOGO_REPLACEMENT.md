# Manual Logo Replacement Instructions for AttendUs

## IMMEDIATE ACTION REQUIRED

To complete the logo replacement with your new AttendUs logo:

### Step 1: Save Your Logo
1. Save the AttendUs logo PNG file you provided to your computer
2. Name it: `attendus_logo.png`
3. Place it in the project root directory: `/Users/paulreisinger/Downloads/orgamiappV1-main-2/`

### Step 2: Run the Replacement Script
Open Terminal in the project directory and run:
```bash
./replace_logo.sh
```

This script will:
- Replace the main logo at `images/inAppLogo.png`
- Generate app icons for Android, iOS, and Web (if ImageMagick is installed)
- Clean and refresh Flutter cache

### Alternative: Manual Replacement
If you prefer to do it manually:

1. **Replace the main logo:**
   - Copy your AttendUs logo to: `images/inAppLogo.png`

2. **The logo is currently used in these locations:**
   - Splash Screen (`lib/screens/Splash/splash_screen.dart`)
   - Second Splash Screen (`lib/screens/Splash/second_splash_screen.dart`)
   - Login Screen (`lib/screens/Authentication/login_screen.dart`)
   - Forgot Password Screen (`lib/screens/Authentication/forgot_password_screen.dart`)

3. **Clean Flutter cache:**
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

## Verification
After replacement, run the app:
```bash
flutter run
```

The new AttendUs logo should now appear throughout the app!
