#!/bin/bash

echo "🚀 Starting performance optimization..."

# Clean Flutter build cache
echo "🧹 Cleaning Flutter build cache..."
flutter clean

# Clean Gradle cache
echo "🧹 Cleaning Gradle cache..."
cd android && ./gradlew clean && cd ..

# Clean iOS build
echo "🧹 Cleaning iOS build..."
cd ios && rm -rf Pods Podfile.lock && cd ..

# Clean pub cache
echo "🧹 Cleaning pub cache..."
flutter pub cache clean --force

# Reinstall dependencies
echo "📦 Reinstalling dependencies..."
flutter pub get

# Rebuild iOS pods if on Mac
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "📱 Rebuilding iOS pods..."
    cd ios && pod install && cd ..
fi

# Run pub get again to ensure everything is linked
flutter pub get

echo "✅ Performance optimization complete!"
echo ""
echo "📝 Additional recommendations:"
echo "1. Restart your IDE/editor"
echo "2. Restart the emulator/simulator"
echo "3. Consider using 'flutter run --release' for better performance"
echo "4. On emulator, ensure hardware acceleration is enabled"
echo "5. Allocate more RAM to the emulator (at least 2GB recommended)"
