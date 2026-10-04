#!/bin/bash

# Flutter Web App Deployment Script for Firebase Hosting
# This script builds and deploys your Flutter web app to Firebase Hosting

set -e  # Exit on any error

echo "🚀 Starting Flutter Web App Deployment..."
echo "========================================"

# Check if we're in the correct directory
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Error: pubspec.yaml not found. Please run this script from your Flutter project root."
    exit 1
fi

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Error: Firebase CLI not found. Please install it first:"
    echo "   npm install -g firebase-tools"
    exit 1
fi

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Error: Flutter not found. Please install Flutter first."
    exit 1
fi

echo "📦 Cleaning previous build..."
flutter clean

echo "🔨 Building Flutter web app for production..."
: "${GOOGLE_MAPS_WEB_API_KEY:?Set GOOGLE_MAPS_WEB_API_KEY to the restricted Attendus web Maps key}"
dart run tools/check_maps_web_key.dart
flutter build web --release --pwa-strategy=none --no-wasm-dry-run \
  --dart-define=GOOGLE_MAPS_WEB_API_KEY="$GOOGLE_MAPS_WEB_API_KEY"
cp web/flutter_service_worker_retirement.js build/web/flutter_service_worker.js
dart run tools/retain_web_releases.dart https://attendus.app/
dart run tools/package_web_release.dart
dart run tools/check_deferred_web_chunks.dart
dart run tools/check_web_bundle_size.dart

echo "🌐 Deploying to Firebase Hosting..."
firebase deploy --only hosting
dart run tools/check_deferred_web_chunks.dart https://attendus.app/
dart run tools/check_deferred_web_chunks.dart https://orgami-66nxok.web.app/

echo ""
echo "✅ Deployment complete! 🎉"
echo "========================================"
echo "🌍 Your app is live at: https://orgami-66nxok.web.app"
echo "📊 Firebase Console: https://console.firebase.google.com/project/orgami-66nxok/hosting"
echo ""
echo "💡 To add a custom domain:"
echo "   1. Go to Firebase Console → Hosting"
echo "   2. Click 'Add custom domain'"
echo "   3. Follow the DNS setup instructions"
echo ""
