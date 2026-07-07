# Firestore Security Rules Deployment Guide

## Overview
This guide explains how to deploy the Firestore security rules to fix permission issues with announcements and polls in the Groups feature.

## Quick Fix (Development)

For immediate testing, deploy the development rules that are more permissive:

```bash
# Deploy development rules (more permissive)
firebase deploy --only firestore:rules --project your-project-id
```

Make sure to update `firebase.json` first:
```json
{
  "firestore": {
    "rules": "firestore-dev.rules",
    "indexes": "firestore.indexes.json"
  }
}
```

## Production Deployment

For production, use the more secure rules:

1. Update `firebase.json`:
```json
{
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  }
}
```

2. Deploy the rules:
```bash
firebase deploy --only firestore:rules --project your-project-id
```

## Manual Deployment (Firebase Console)

If you prefer to deploy via the Firebase Console:

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Navigate to **Firestore Database** → **Rules**
4. Copy the contents of either:
   - `firestore-dev.rules` (for testing)
   - `firestore.rules` (for production)
5. Paste into the rules editor
6. Click **Publish**

## Rules Overview

### Development Rules (`firestore-dev.rules`)
- **⚠️ WARNING: Only for development/testing**
- Allows all authenticated users to read/write to Feed collections
- Permits creating announcements and polls without role checks
- Quick solution for testing features

### Production Rules (`firestore.rules`)
- Proper security with role-based access
- Members can create announcements and polls
- Admins have full control
- Authors can edit/delete their own content
- Voting on polls is allowed for all authenticated users

## Key Permissions

### Feed Collection (Announcements & Polls)
- **Read**: All authenticated users
- **Create**: 
  - Group members
  - Group admins
  - Group creators
  - Content authors
- **Update**:
  - Content authors
  - Group admins
  - Any user (for voting on polls only)
- **Delete**:
  - Content authors
  - Group admins

## Testing the Fix

After deploying the rules:

1. Open the app
2. Navigate to a group
3. Tap the "+ New" button
4. Select "Post Announcement" or "Create Poll"
5. Fill in the details and submit
6. The content should now post successfully without permission errors

## Troubleshooting

If you still see permission errors:

1. **Check Authentication**: Ensure the user is logged in
```javascript
// The app checks this with:
FirebaseAuth.instance.currentUser != null
```

2. **Verify Deployment**: Check the Firebase Console to confirm rules are published

3. **Clear Cache**: Sometimes the app caches permission states
   - Force stop the app
   - Clear app data/cache
   - Restart the app

4. **Check Member Status**: For production rules, ensure the user is a member:
   - The user should have joined the group
   - Check if a Members document exists for the user

## Creating Test Data

To test as an admin, you can manually add yourself as an admin member:

1. Go to Firebase Console → Firestore
2. Navigate to: `Organizations/{orgId}/Members/{yourUserId}`
3. Add/Update the document with:
```json
{
  "role": "admin",
  "joinedAt": "SERVER_TIMESTAMP",
  "userId": "your-user-id"
}
```

## Security Considerations

The production rules implement:
- Authentication requirements
- Role-based access control
- Author ownership verification
- Member status validation

Never use the development rules in production as they allow any authenticated user to modify any group's feed.

## Next Steps

1. Deploy the development rules for immediate testing
2. Test the announcement and poll features
3. Once confirmed working, switch to production rules
4. Add proper member management UI in the app
