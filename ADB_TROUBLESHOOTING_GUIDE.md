# Flutter ADB Installation Issue - Troubleshooting Guide

## Problem
You're getting the following error when running your Flutter app on the Android emulator:
```
Error: ADB exited with exit code 1
adb: failed to install app-debug.apk: cmd: Failure calling service package: Broken pipe (32)
```

## Quick Fixes (Try These First)

### 1. Restart ADB Server
```bash
adb kill-server
adb start-server
adb devices
flutter run
```

### 2. Clean and Rebuild
```bash
flutter clean
flutter pub get
flutter run
```

### 3. Restart Emulator
- Close the Android emulator completely
- Restart it from Android Studio or command line
- Wait for it to fully boot up
- Try running the app again

## Detailed Troubleshooting Steps

### Step 1: Check Emulator Status
```bash
# Check connected devices
adb devices

# Should show something like:
# List of devices attached
# emulator-5554    device
```

### Step 2: Clear App Data on Emulator
```bash
# Clear your app's data on the emulator
adb shell pm clear com.stormdeve.orgami
```

### Step 3: Manual Installation Test
```bash
# Try installing the APK manually
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

### Step 4: Emulator Storage Check
The "Broken pipe" error often occurs when the emulator is out of storage space.

**Solution A: Increase Emulator Storage**
1. Open Android Studio
2. Go to Tools → AVD Manager
3. Click the pencil icon next to your emulator
4. Click "Advanced Settings"
5. Increase "Internal Storage" (try 8GB+)
6. Increase "SD Card" size if needed

**Solution B: Wipe Emulator Data**
1. In AVD Manager, click the down arrow next to your emulator
2. Select "Wipe Data"
3. Restart the emulator

### Step 5: Alternative Emulator
If the issue persists, try creating a new emulator:
1. Android Studio → Tools → AVD Manager
2. Create Virtual Device
3. Choose a different API level (API 30 or 31 work well)
4. Ensure adequate storage (6GB+ internal)

### Step 6: Physical Device Testing
Test on a physical Android device to isolate if it's an emulator-specific issue:
1. Enable Developer Options on your phone
2. Enable USB Debugging
3. Connect via USB
4. Run `adb devices` to confirm connection
5. Run `flutter run`

## Advanced Solutions

### Update Android SDK Tools
```bash
# Update platform-tools
sdkmanager --update
sdkmanager "platform-tools"
```

### Check ADB Version
```bash
adb version
# Should show recent version (30+)
```

### Force Flutter to Use Specific Device
```bash
# List devices
flutter devices

# Run on specific device
flutter run -d device_id
```

### Gradle Clean (if build issues persist)
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

## Prevention Tips

1. **Regular Emulator Maintenance**
   - Periodically wipe emulator data
   - Keep adequate free space (2GB+)
   - Close unused apps in emulator

2. **Project Maintenance**
   - Run `flutter clean` regularly
   - Keep Flutter/Android SDK updated
   - Clear build cache when switching branches

3. **Emulator Configuration**
   - Use recommended API levels (29-33)
   - Allocate sufficient RAM (4GB+)
   - Enable hardware acceleration

## Still Having Issues?

If none of these solutions work, please provide:
1. Output of `flutter doctor -v`
2. Output of `adb devices`
3. Android Studio version
4. Emulator configuration details
5. Host OS version

## Quick Commands Summary
```bash
# Emergency reset sequence
adb kill-server
adb start-server
flutter clean
flutter pub get
flutter run

# If that fails, restart emulator and try:
adb devices
flutter run -v  # verbose output for debugging
```