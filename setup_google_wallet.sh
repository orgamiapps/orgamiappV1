#!/bin/bash
# Google Wallet Setup Script for AttendUs

echo "🎯 AttendUs Google Wallet Setup Script"
echo "======================================"
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI is not installed. Please install it first:"
    echo "   npm install -g firebase-tools"
    exit 1
fi

echo "This script will help you configure Google Wallet API for AttendUs badges."
echo ""

# Step 1: Get Issuer ID
read -p "Enter your Google Pay Issuer ID (from Google Pay Business Console): " ISSUER_ID
if [ -z "$ISSUER_ID" ]; then
    echo "❌ Issuer ID is required. Please get it from Google Pay Business Console."
    exit 1
fi

echo ""
echo "🔧 Setting Firebase Functions environment variables..."

# Set the issuer ID
firebase functions:config:set google_wallet.issuer_id="$ISSUER_ID"

if [ $? -eq 0 ]; then
    echo "✅ Google Wallet Issuer ID set successfully"
else
    echo "❌ Failed to set Issuer ID"
    exit 1
fi

echo ""
echo "📋 Next steps:"
echo "1. Ensure Google Wallet API is enabled in Google Cloud Console"
echo "2. Add 'Wallet Objects Issuer' role to your service account"
echo "3. Test the integration on an Android device with Google Wallet"
echo ""
echo "📖 For detailed setup instructions, see: GOOGLE_WALLET_SETUP_GUIDE.md"
echo ""
echo "🚀 Ready to test! The Google Wallet integration is now configured."
