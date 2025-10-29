#!/bin/bash

# Deploy Guest Mode Firebase Connection Fix
# This script deploys the updated Firestore security rules to support guest mode

echo "========================================="
echo "Deploying Guest Mode Firebase Fix"
echo "========================================="
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null
then
    echo "❌ Firebase CLI is not installed."
    echo "   Please install it with: npm install -g firebase-tools"
    exit 1
fi

echo "✅ Firebase CLI found"
echo ""

# Check if logged in to Firebase
echo "Checking Firebase authentication..."
firebase login:ci --no-localhost 2>/dev/null
if [ $? -ne 0 ]; then
    echo "⚠️  Not logged in to Firebase. Logging in..."
    firebase login
fi

echo "✅ Logged in to Firebase"
echo ""

# Deploy Firestore rules
echo "Deploying Firestore security rules..."
firebase deploy --only firestore:rules

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================="
    echo "✅ Firestore rules deployed successfully!"
    echo "========================================="
    echo ""
    echo "Next steps:"
    echo "1. Enable Anonymous Authentication in Firebase Console:"
    echo "   - Go to: https://console.firebase.google.com"
    echo "   - Select your project"
    echo "   - Go to: Authentication → Sign-in method"
    echo "   - Enable 'Anonymous' sign-in provider"
    echo ""
    echo "2. Test guest mode:"
    echo "   - Launch the app"
    echo "   - Tap 'Continue as Guest'"
    echo "   - Verify home hub loads without errors"
    echo "   - Browse events and organizations"
    echo ""
    echo "3. Monitor logs for:"
    echo "   - 'Signing in anonymously to Firebase for guest mode...'"
    echo "   - 'Anonymous sign-in successful'"
    echo "   - No Firestore permission errors"
    echo ""
else
    echo ""
    echo "========================================="
    echo "❌ Failed to deploy Firestore rules"
    echo "========================================="
    echo ""
    echo "Please check:"
    echo "1. You're logged in to Firebase: firebase login"
    echo "2. You have permission to deploy to the project"
    echo "3. The firestore.rules file is valid"
    echo ""
    exit 1
fi

