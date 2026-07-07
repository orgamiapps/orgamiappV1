#!/bin/bash

# Deploy Join Approval Notifications Feature
# This script deploys the updated Cloud Function that sends notifications when join requests are approved

set -e

echo "======================================"
echo "Deploying Join Approval Notifications"
echo "======================================"
echo ""

# Check if we're in the right directory
if [ ! -d "functions" ]; then
  echo "Error: functions directory not found. Please run this script from the project root."
  exit 1
fi

# Navigate to functions directory
cd functions

echo "📦 Installing dependencies..."
npm install

echo ""
echo "🚀 Deploying Cloud Function..."
firebase deploy --only functions:notifyOrgMembershipChanges

echo ""
echo "✅ Deployment complete!"
echo ""
echo "======================================"
echo "Testing Instructions"
echo "======================================"
echo ""
echo "1. Create a test user account (or use an existing one)"
echo "2. Request to join a group"
echo "3. Use an admin account to approve the request"
echo "4. Check the user's notifications tab"
echo "5. Verify the notification appears with: 'Join Request Approved! 🎉'"
echo ""
echo "======================================"
echo "Monitor Function Logs"
echo "======================================"
echo ""
echo "To view function logs, run:"
echo "  firebase functions:log --only notifyOrgMembershipChanges"
echo ""
echo "To view real-time logs:"
echo "  firebase functions:log --only notifyOrgMembershipChanges --follow"
echo ""

