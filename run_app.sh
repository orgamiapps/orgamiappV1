#!/bin/bash

# Script to build and run the Flutter app
# This is a workaround for the flutter run Gradle issue

set -e  # Exit on error

echo "🚀 Building and Running Flutter App..."
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if device is specified
DEVICE=${1:-emulator-5554}

echo -e "${BLUE}📱 Target device: $DEVICE${NC}"
echo ""

# Step 1: Build the debug APK
echo -e "${YELLOW}Step 1: Building debug APK...${NC}"
flutter build apk --debug

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Build successful!${NC}"
    echo ""
else
    echo "❌ Build failed!"
    exit 1
fi

# Step 2: Install on device
echo -e "${YELLOW}Step 2: Installing on device...${NC}"
adb -s $DEVICE install -r build/app/outputs/flutter-apk/app-debug.apk

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Installation successful!${NC}"
    echo ""
else
    echo "❌ Installation failed!"
    exit 1
fi

# Step 3: Start the app
echo -e "${YELLOW}Step 3: Starting app...${NC}"
adb -s $DEVICE shell am start -n com.stormdeve.orgami/.MainActivity

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ App started!${NC}"
    echo ""
else
    echo "❌ Failed to start app!"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 App is now running on $DEVICE${NC}"
echo ""
echo "To view logs, run:"
echo "  flutter logs -d $DEVICE"
echo ""
echo "To attach Flutter for hot reload, run:"
echo "  flutter attach -d $DEVICE"
echo ""

