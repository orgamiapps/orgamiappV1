# Quick Start Guide - Running the App

## ✅ App is Ready to Run!

The build issue has been resolved with a working workaround.

## 🚀 How to Run the App

### Easy Way (Recommended):
```bash
./run_app.sh
```

This script will:
1. Build the debug APK
2. Install it on your emulator
3. Start the app automatically

### Manual Way:
```bash
# Build
flutter build apk --debug

# Install
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk

# Start
adb -s emulator-5554 shell am start -n com.stormdeve.orgami/.MainActivity
```

## 🔥 Hot Reload

After the app is running, enable hot reload:
```bash
flutter attach -d emulator-5554
```

Then:
- Press `r` to hot reload
- Press `R` to hot restart
- Save files to auto-reload

## 📱 View Logs

```bash
flutter logs -d emulator-5554
```

Or filter for My Profile debugging:
```bash
flutter logs -d emulator-5554 | grep -E "(🏗️|🔍|🔄|MY_PROFILE)"
```

## 🧪 Test My Profile Events

1. Open the app on your emulator
2. Navigate to **My Profile** tab
3. Check the three tabs: **Created**, **Attended**, **Saved**
4. If events don't appear:
   - Click **Refresh** button
   - Check console logs for detailed output

## 🛠️ Troubleshooting

### App won't start?
```bash
# Stop any running instances
adb -s emulator-5554 shell am force-stop com.stormdeve.orgami

# Try again
./run_app.sh
```

### Need to rebuild?
```bash
flutter clean
flutter pub get
./run_app.sh
```

### Emulator issues?
```bash
# List all devices
flutter devices

# Or
adb devices
```

## 📚 Documentation

- `BUILD_ISSUE_RESOLUTION_FINAL.md` - Detailed explanation of the build issue
- `MY_PROFILE_EVENTS_FIX_SUMMARY.md` - Technical details of events fix
- `MY_PROFILE_EVENTS_TESTING_GUIDE.md` - Complete testing guide

## ⚡ Common Commands

| Command | Description |
|---------|-------------|
| `./run_app.sh` | Build, install, and run the app |
| `flutter attach -d emulator-5554` | Enable hot reload |
| `flutter logs -d emulator-5554` | View app logs |
| `adb -s emulator-5554 shell am force-stop com.stormdeve.orgami` | Stop the app |

## 🎉 You're All Set!

The app is ready to run and test. Use `./run_app.sh` to get started!

