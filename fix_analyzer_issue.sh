#!/bin/bash

echo "========================================="
echo "Flutter Analyzer Fix Script"
echo "========================================="
echo ""

# Step 1: Clean Flutter cache
echo "Step 1: Cleaning Flutter build cache..."
flutter clean
if [ $? -ne 0 ]; then
    echo "Warning: Flutter clean failed. Make sure Flutter is installed and in PATH."
fi

# Step 2: Clear Dart/Flutter analyzer cache
echo ""
echo "Step 2: Clearing analyzer and pub cache..."
rm -rf .dart_tool/
rm -rf build/
rm -f .packages
rm -f pubspec.lock

# Step 3: Clear Android Studio caches (if on macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo ""
    echo "Step 3: Clearing Android Studio caches (macOS)..."
    rm -rf ~/Library/Caches/Google/AndroidStudio*
    rm -rf ~/Library/Caches/JetBrains/AndroidStudio*
fi

# Step 4: Clear Android Studio caches (if on Linux)
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo ""
    echo "Step 3: Clearing Android Studio caches (Linux)..."
    rm -rf ~/.cache/Google/AndroidStudio*
    rm -rf ~/.cache/JetBrains/AndroidStudio*
fi

# Step 5: Clear Android Studio caches (if on Windows - Git Bash)
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    echo ""
    echo "Step 3: Clearing Android Studio caches (Windows)..."
    rm -rf "$LOCALAPPDATA/Google/AndroidStudio"*
    rm -rf "$LOCALAPPDATA/JetBrains/AndroidStudio"*
fi

# Step 6: Get packages fresh
echo ""
echo "Step 4: Getting Flutter packages..."
flutter pub get
if [ $? -ne 0 ]; then
    echo "Warning: Flutter pub get failed. Check your pubspec.yaml for errors."
fi

# Step 7: Run code generation if needed
echo ""
echo "Step 5: Running code generation (if applicable)..."
flutter pub run build_runner build --delete-conflicting-outputs 2>/dev/null || echo "No code generation needed or build_runner not configured."

# Step 8: Analyze to check for remaining issues
echo ""
echo "Step 6: Running Flutter analyze..."
flutter analyze --no-fatal-warnings --no-fatal-infos

echo ""
echo "========================================="
echo "Fix Complete!"
echo "========================================="
echo ""
echo "Additional steps to do in Android Studio:"
echo "1. File -> Invalidate Caches and Restart"
echo "2. After restart, wait for indexing to complete"
echo "3. If still stuck, try: File -> Sync Project with Gradle Files"
echo "4. Run 'flutter doctor' in terminal to check for any issues"
echo ""
echo "If the analyzer is still stuck:"
echo "- Close Android Studio completely"
echo "- Run this script again"
echo "- Open Android Studio and let it re-index the project"
