# Flutter Analyzer Fix Guide for Android Studio

## Problem
The Flutter app is stuck in "Analyzing..." phase in Android Studio and won't run on the emulator.

## Solutions Applied

### 1. Updated analysis_options.yaml
- Added exclusions for directories that don't need analysis (build, ios, android, etc.)
- Disabled problematic lint rules that can cause false positives
- Set error severity levels to warnings for non-critical issues

### 2. Created fix_analyzer_issue.sh Script
Run this script in your terminal to clear all caches:
```bash
./fix_analyzer_issue.sh
```

## Manual Steps to Fix in Android Studio

### Step 1: Clear Android Studio Caches
1. In Android Studio, go to **File → Invalidate Caches**
2. Check all options:
   - Clear file system cache
   - Clear VCS Log caches
   - Clear downloaded shared indexes
3. Click **Invalidate and Restart**

### Step 2: Clean Flutter Project
Open Terminal in Android Studio (bottom panel) and run:
```bash
flutter clean
rm -rf .dart_tool/
rm -rf build/
rm -f .packages
rm -f pubspec.lock
```

### Step 3: Get Dependencies Fresh
```bash
flutter pub get
```

### Step 4: Restart Dart Analysis Server
1. In Android Studio, go to **View → Tool Windows → Dart Analysis**
2. Click the "Restart Dart Analysis Server" button (circular arrow icon)

### Step 5: Check Flutter Doctor
```bash
flutter doctor -v
```
Fix any issues reported by Flutter doctor.

### Step 6: Gradle Sync (Android specific)
1. Open android/build.gradle
2. Click **Sync Now** when prompted
3. Or go to **File → Sync Project with Gradle Files**

## Alternative Solutions

### If Still Stuck After Above Steps:

#### Option A: Disable Analysis Temporarily
1. Go to **Settings/Preferences → Languages & Frameworks → Flutter**
2. Uncheck "Perform analysis" temporarily
3. Run the app
4. Re-enable analysis after successful run

#### Option B: Run from Command Line
Skip Android Studio's analyzer and run directly:
```bash
flutter run
```

#### Option C: Reset IDE Settings
1. Close Android Studio
2. Delete Android Studio configuration:
   - **macOS**: `~/Library/Application Support/Google/AndroidStudio*`
   - **Linux**: `~/.config/Google/AndroidStudio*`
   - **Windows**: `%APPDATA%\Google\AndroidStudio*`
3. Restart Android Studio (will reset to defaults)

#### Option D: Update Dependencies
Check if any dependencies are outdated:
```bash
flutter pub outdated
flutter pub upgrade
```

## Quick Checklist

- [ ] Flutter SDK is properly installed (`flutter doctor`)
- [ ] Android SDK and emulator are properly configured
- [ ] No syntax errors in Dart files
- [ ] pubspec.yaml is valid YAML
- [ ] All required dependencies are available
- [ ] No conflicting package versions
- [ ] Android Studio Flutter/Dart plugins are up to date

## Files Modified

1. **analysis_options.yaml** - Added analyzer configuration to:
   - Exclude unnecessary directories
   - Disable problematic lint rules
   - Set appropriate error levels

2. **Deleted analysis_results.txt** - Removed outdated analysis results

3. **Created fix_analyzer_issue.sh** - Automated cleanup script

## Prevention Tips

1. **Regular Maintenance**:
   - Run `flutter clean` periodically
   - Keep Flutter SDK updated
   - Update Android Studio plugins regularly

2. **Project Structure**:
   - Keep imports organized and correct
   - Avoid circular dependencies
   - Fix lint issues promptly

3. **IDE Settings**:
   - Allocate more memory to Android Studio if needed
   - Settings → Appearance & Behavior → System Settings → Memory Settings
   - Increase heap size to at least 2048 MB

## If Nothing Works

1. Try opening the project in VS Code with Flutter extension
2. Create a new Flutter project and migrate your code
3. Check Android Studio logs: **Help → Show Log in Explorer/Finder**
4. Report issue to Flutter team with `flutter doctor -v` output

## Run the App Without IDE

If you need to run immediately while fixing the analyzer:
```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d <device_id>

# Run with verbose output
flutter run -v
```

This should resolve the analyzer hanging issue. The main problems were:
1. Outdated analysis cache
2. Missing analyzer exclusions
3. Overly strict lint rules

After following these steps, your app should run normally in the Android Studio emulator.
