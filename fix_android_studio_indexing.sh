#!/bin/bash

# Android Studio Indexing Fix Script for Flutter Project
# This script fixes Android Studio indexing issues by cleaning caches and optimizing project configuration

echo "🔧 Android Studio Indexing Fix Script"
echo "====================================="
echo ""

# Store the project directory
PROJECT_DIR="$(pwd)"

echo "📂 Working in: $PROJECT_DIR"
echo ""

# Step 1: Clean Flutter build caches
echo "🗑️  Step 1: Cleaning Flutter build caches..."
flutter clean 2>/dev/null || echo "   ⚠️  Flutter clean failed (Flutter might not be in PATH)"
rm -rf build/
rm -rf .dart_tool/flutter_build/
echo "   ✅ Flutter caches cleaned"
echo ""

# Step 2: Clean Android build caches
echo "🗑️  Step 2: Cleaning Android build caches..."
rm -rf android/.gradle/
rm -rf android/build/
rm -rf android/app/build/
rm -rf android/app/.gradle/
echo "   ✅ Android caches cleaned"
echo ""

# Step 3: Clean iOS/macOS build caches (if they exist)
echo "🗑️  Step 3: Cleaning iOS/macOS build caches..."
rm -rf ios/build/
rm -rf macos/build/
echo "   ✅ iOS/macOS caches cleaned"
echo ""

# Step 4: Clean platform build caches
echo "🗑️  Step 4: Cleaning other platform build caches..."
rm -rf windows/build/
rm -rf linux/build/
rm -rf web/build/
echo "   ✅ Platform caches cleaned"
echo ""

# Step 5: Clean Android Studio caches
echo "🗑️  Step 5: Cleaning Android Studio IDE caches..."
rm -rf .idea/caches/
rm -rf .idea/libraries/
echo "   ✅ IDE caches cleaned"
echo ""

# Step 6: Ensure exclusion files are properly configured
echo "📝 Step 6: Verifying exclusion configurations..."

# Check if .idea directory exists
if [ ! -d ".idea" ]; then
    echo "   ⚠️  .idea directory not found. Open the project in Android Studio first."
else
    # Check if misc.xml exists with exclusions
    if [ -f ".idea/misc.xml" ]; then
        echo "   ✅ .idea/misc.xml found with exclusions"
    else
        echo "   ⚠️  .idea/misc.xml not found - exclusions may not be configured"
    fi
    
    # Check if .ignore file exists
    if [ -f ".idea/.ignore" ]; then
        echo "   ✅ .idea/.ignore found"
    else
        echo "   ⚠️  .idea/.ignore not found - additional exclusions may not be configured"
    fi
    
    # Check if project .iml file has exclusions
    if [ -f ".idea/orgamiappV1-main-2.iml" ]; then
        if grep -q "functions/node_modules" ".idea/orgamiappV1-main-2.iml"; then
            echo "   ✅ Project .iml file has node_modules exclusion"
        else
            echo "   ⚠️  Project .iml file missing node_modules exclusion"
        fi
    fi
fi
echo ""

# Step 7: Get Flutter packages
echo "📦 Step 7: Getting Flutter packages..."
flutter pub get 2>/dev/null || echo "   ⚠️  Flutter pub get failed (Flutter might not be in PATH)"
echo ""

# Step 8: Display large directories that might cause issues
echo "📊 Step 8: Checking for large directories..."
echo "   Large directories found (>10MB):"
for dir in build ios/build android/build functions/node_modules ios/Pods macos/Pods .dart_tool; do
    if [ -d "$dir" ]; then
        SIZE=$(du -sh "$dir" 2>/dev/null | cut -f1)
        if [ ! -z "$SIZE" ]; then
            echo "   - $dir: $SIZE"
        fi
    fi
done
echo ""

# Step 9: Provide Android Studio restart instructions
echo "✨ Cleanup Complete!"
echo ""
echo "📋 Next Steps:"
echo "1. Close Android Studio completely"
echo "2. On macOS, also clear Android Studio caches:"
echo "   rm -rf ~/Library/Caches/Google/AndroidStudio*"
echo "   rm -rf ~/Library/Caches/JetBrains/AndroidStudio*"
echo "3. Restart Android Studio"
echo "4. When Android Studio opens:"
echo "   - Click 'Invalidate Caches' from File menu if indexing is still slow"
echo "   - Let the initial indexing complete (should be much faster now)"
echo ""
echo "⚡ Performance Tips:"
echo "- The functions/node_modules directory (196MB) is now excluded from indexing"
echo "- Build directories are excluded and cleaned"
echo "- Consider adding more memory to Android Studio:"
echo "  Help → Edit Custom VM Options → Set -Xmx to 4096m or higher"
echo ""
echo "✅ Script completed successfully!"
