# Google Wallet API Setup Guide

This guide explains how to set up Google Wallet API integration for the AttendUs badge system.

## Prerequisites

1. Google Cloud Project with Firebase enabled
2. Google Pay Business Console access
3. Service Account with appropriate permissions

## Step 1: Enable Google Wallet API

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your Firebase project (`orgami-66nxok`)
3. Navigate to **APIs & Services** → **Library**
4. Search for "Google Wallet API"
5. Click **Enable**

## Step 2: Set Up Google Pay Business Console

1. Go to [Google Pay Business Console](https://pay.google.com/business/console/)
2. Sign in with your Google account
3. Create a new issuer account or use existing one
4. Note down your **Issuer ID** (e.g., `3388000000022295094`)

## Step 3: Configure Service Account Permissions

1. Go to Google Cloud Console → **IAM & Admin** → **Service Accounts**
2. Find your Firebase Admin SDK service account
3. Click **Edit** (pencil icon)
4. Add the role: **Wallet Objects Issuer**
5. Save changes

## Step 4: Set Environment Variables

In your Firebase Functions environment, set the following variables:

```bash
# Required for Google Wallet API
firebase functions:config:set google_wallet.issuer_id="YOUR_ISSUER_ID"

# Optional - these are usually auto-detected from service account
firebase functions:config:set google_wallet.client_email="your-service-account@project.iam.gserviceaccount.com"
firebase functions:config:set google_wallet.private_key="-----BEGIN PRIVATE KEY-----\nYOUR_PRIVATE_KEY\n-----END PRIVATE KEY-----"
```

## Step 5: Test the Integration

1. Deploy the updated Firebase functions:
   ```bash
   npm run deploy
   ```

2. Test on an Android device with Google Wallet installed

3. Check Firebase Functions logs for any errors:
   ```bash
   firebase functions:log --only generateUserBadgePass
   ```

## Current Implementation Details

The implementation:

- Creates a generic pass class (`attendus_member_badge_class`)
- Generates user-specific pass objects with badge data
- Creates JWT tokens for "Save to Google Pay" URLs
- Handles pass updates for existing users
- Provides comprehensive error handling and logging

## Troubleshooting

### Common Issues:

1. **"Insufficient permissions"** → Check service account has Wallet Objects Issuer role
2. **"Invalid JWT"** → Verify private key format and issuer email
3. **"Class not found"** → Ensure the generic class is created successfully
4. **"Object already exists"** → The system handles this automatically with updates

### Debug Steps:

1. Check Firebase Functions logs
2. Verify service account permissions in Google Cloud Console
3. Test with Google's JWT debugger
4. Ensure issuer ID is correctly formatted

## Security Notes

- Private keys should be stored securely in Firebase Functions environment
- JWT tokens expire after 1 hour for security
- Object IDs are sanitized to prevent injection attacks
- All API calls use proper authentication scopes

## Support

For additional help:
- [Google Wallet API Documentation](https://developers.google.com/wallet)
- [Firebase Functions Documentation](https://firebase.google.com/docs/functions)
- Firebase project logs and monitoring
