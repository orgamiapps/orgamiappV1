# Project-Specific ADB Installation Fix

Based on your project configuration, here are specific recommendations for your Orgami Flutter app:

## Identified Configuration Details

Your app uses:
- **Package Name**: `com.stormdeve.orgami`
- **Target SDK**: 36 (very recent - might cause compatibility issues)
- **Min SDK**: 23
- **Compile SDK**: 36
- **Gradle**: 8.8
- **Java**: Version 17
- **Kotlin**: 1.9.22

## Most Likely Causes & Solutions

### 1. Target SDK 36 Compatibility Issue ⚠️
Your app targets SDK 36, which is very recent and might not be fully supported by older emulators.

**Solution A - Use Compatible Emulator:**
```bash
# Create emulator with API 34 or 35
# In Android Studio: AVD Manager → Create → API 34/35
```

**Solution B - Temporarily Lower Target SDK (if needed):**
Edit `android/app/build.gradle`:
```gradle
defaultConfig {
    targetSdk = 34  // Change from 36 to 34
}
```

### 2. Clear App Data Specifically
```bash
adb shell pm clear com.stormdeve.orgami
```

### 3. Firebase Setup Check
Since your app uses Firebase, ensure:
```bash
# Check if Firebase is causing conflicts
adb shell pm clear com.google.android.gms
# Then try installing again
flutter run
```

### 4. Permission-Heavy App Fix
Your app uses many permissions (location, camera, storage). Try:
```bash
# Reset all permissions
adb shell pm reset-permissions
flutter run
```

## Recommended Emulator Setup

Create a new emulator with these specs:
- **API Level**: 34 (Android 14)
- **Target**: Google APIs (not just Android)
- **RAM**: 4GB minimum
- **Internal Storage**: 8GB+
- **Architecture**: x86_64 (if available)

## Quick Fix Sequence

Try these commands in order:

```bash
# 1. Kill everything
adb kill-server
pkill -f emulator

# 2. Start fresh
adb start-server
# Start your emulator manually

# 3. Wait for full boot, then:
adb devices
# Should show "device" not "offline"

# 4. Clear your app
adb shell pm clear com.stormdeve.orgami

# 5. Clean build
flutter clean
flutter pub get

# 6. Run with verbose output
flutter run -v
```

## Alternative Installation Method

If the above doesn't work, try manual installation:

```bash
# 1. Build APK
flutter build apk --debug

# 2. Install manually with force
adb install -r -d build/app/outputs/flutter-apk/app-debug.apk

# 3. Launch manually
adb shell monkey -p com.stormdeve.orgami -c android.intent.category.LAUNCHER 1
```

## If Still Failing - Compatibility Check

Your project has very recent dependencies. If issues persist:

1. **Test on Physical Device**: The issue might be emulator-specific
2. **Create Simple Test App**: Test if it's project-specific:
   ```bash
   flutter create test_app
   cd test_app
   flutter run  # If this works, it's your project config
   ```

3. **Check Flutter Doctor**: Ensure your setup is valid:
   ```bash
   flutter doctor -v
   flutter doctor --android-licenses
   ```

## Emergency Downgrade (Last Resort)

If nothing else works, you can temporarily downgrade SDK versions:

In `android/app/build.gradle`:
```gradle
android {
    compileSdk = 34  // instead of 36
    
    defaultConfig {
        targetSdk = 34  // instead of 36
    }
}
```

Then:
```bash
flutter clean
flutter pub get
flutter run
```

> **Note**: SDK 36 is very new (released late 2024). Most emulators and devices might not fully support it yet. Consider using SDK 34 for better compatibility.

## Success Indicators

You'll know it's fixed when you see:
```
✓ Built build/app/outputs/flutter-apk/app-debug.apk
Installing build/app/outputs/flutter-apk/app-debug.apk...
✓ App installed successfully  <-- This line should appear
Launching lib/main.dart on sdk gphone64 arm64 in debug mode...
```