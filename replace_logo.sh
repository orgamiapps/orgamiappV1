#!/bin/bash

# AttendUs Logo Replacement Script
# This script helps you replace all logo and icon files in the app

echo "========================================="
echo "AttendUs Logo Replacement Script"
echo "========================================="
echo ""

# Check if the new logo file exists
if [ ! -f "attendus_logo.png" ]; then
    echo "ERROR: Please place your new AttendUs logo as 'attendus_logo.png' in the project root directory"
    echo "The logo should be a high-resolution PNG (at least 1024x1024 for best results)"
    exit 1
fi

echo "Found attendus_logo.png - proceeding with replacement..."
echo ""

# Replace the main app logo
echo "1. Replacing main app logo..."
cp attendus_logo.png images/inAppLogo.png
echo "   ✓ Main logo replaced"

# Create app icons for different platforms if ImageMagick is installed
if command -v magick &> /dev/null; then
    echo ""
    echo "2. Generating app icons for different platforms..."
    
    # Android icons
    echo "   Generating Android icons..."
    magick attendus_logo.png -resize 48x48 android/app/src/main/res/mipmap-mdpi/ic_launcher.png
    magick attendus_logo.png -resize 72x72 android/app/src/main/res/mipmap-hdpi/ic_launcher.png
    magick attendus_logo.png -resize 96x96 android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
    magick attendus_logo.png -resize 144x144 android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
    magick attendus_logo.png -resize 192x192 android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
    echo "   ✓ Android icons generated"
    
    # iOS icons
    echo "   Generating iOS icons..."
    magick attendus_logo.png -resize 20x20 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png
    magick attendus_logo.png -resize 40x40 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png
    magick attendus_logo.png -resize 60x60 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png
    magick attendus_logo.png -resize 29x29 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png
    magick attendus_logo.png -resize 58x58 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png
    magick attendus_logo.png -resize 87x87 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png
    magick attendus_logo.png -resize 40x40 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png
    magick attendus_logo.png -resize 80x80 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png
    magick attendus_logo.png -resize 120x120 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png
    magick attendus_logo.png -resize 120x120 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png
    magick attendus_logo.png -resize 180x180 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png
    magick attendus_logo.png -resize 76x76 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png
    magick attendus_logo.png -resize 152x152 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png
    magick attendus_logo.png -resize 167x167 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png
    magick attendus_logo.png -resize 1024x1024 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png
    echo "   ✓ iOS icons generated"
    
    # Web icons
    echo "   Generating Web icons..."
    magick attendus_logo.png -resize 16x16 web/favicon.png
    magick attendus_logo.png -resize 192x192 web/icons/Icon-192.png
    magick attendus_logo.png -resize 512x512 web/icons/Icon-512.png
    magick attendus_logo.png -resize 192x192 web/icons/Icon-maskable-192.png
    magick attendus_logo.png -resize 512x512 web/icons/Icon-maskable-512.png
    echo "   ✓ Web icons and favicon generated"
    
else
    echo ""
    echo "WARNING: ImageMagick is not installed. Cannot auto-generate app icons."
    echo "To install ImageMagick on macOS, run: brew install imagemagick"
    echo ""
    echo "You'll need to manually replace the app icons in:"
    echo "  - android/app/src/main/res/mipmap-*/"
    echo "  - ios/Runner/Assets.xcassets/AppIcon.appiconset/"
    echo "  - web/icons/"
fi

echo ""
echo "3. Cleaning Flutter cache..."
flutter clean

echo ""
echo "4. Getting Flutter packages..."
flutter pub get

echo ""
echo "========================================="
echo "Logo replacement complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Run 'flutter run' to test the app with the new logo"
echo "2. Commit the changes to your repository"
echo ""
echo "Note: If you see the old logo cached, try:"
echo "  - Uninstalling and reinstalling the app"
echo "  - Clearing app data/cache on your device"
