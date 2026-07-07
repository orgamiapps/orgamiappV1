#!/bin/bash

echo "Deploying Firestore rules..."

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "Firebase CLI is not installed. Please install it first:"
    echo "npm install -g firebase-tools"
    exit 1
fi

# Deploy the Firestore rules
echo "Deploying development rules to Firestore..."
firebase deploy --only firestore:rules

if [ $? -eq 0 ]; then
    echo "✅ Firestore rules deployed successfully!"
    echo ""
    echo "The following changes were deployed:"
    echo "- Users can now follow/unfollow each other"
    echo "- Followers and following counts will be properly tracked"
    echo "- Follow button functionality is now enabled"
    echo ""
    echo "Please test the follow functionality in your app!"
else
    echo "❌ Failed to deploy Firestore rules"
    echo "Please check your Firebase configuration and try again"
    exit 1
fi
