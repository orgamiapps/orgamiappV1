#!/bin/bash

echo "🚀 Launching Orgami App..."
echo ""

# Check Flutter installation
echo "Checking Flutter installation..."
flutter --version
echo ""

# Check connected devices
echo "Available devices:"
flutter devices
echo ""

# Prompt for device selection
echo "Press Enter to run on default device, or type a device ID from above:"
read -r DEVICE_ID

if [ -z "$DEVICE_ID" ]; then
    echo "Running on default device..."
    flutter run
else
    echo "Running on device: $DEVICE_ID"
    flutter run -d "$DEVICE_ID"
fi
