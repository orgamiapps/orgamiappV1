# Firestore Security Rules for Follow/Following Feature

## Current Issue
The follow/following feature is getting permission denied errors because the Firestore security rules don't allow access to the `followers` and `following` subcollections.

## Solution
Add the following security rules to your `firestore.rules` file:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow users to read and write their own customer document
    match /Customers/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      
      // Allow users to read other customer documents (for public profiles)
      allow read: if request.auth != null;
      
      // Allow access to followers subcollection
      match /followers/{followerId} {
        allow read, write: if request.auth != null && 
          (request.auth.uid == userId || request.auth.uid == followerId);
      }
      
      // Allow access to following subcollection
      match /following/{followingId} {
        allow read, write: if request.auth != null && 
          (request.auth.uid == userId || request.auth.uid == followingId);
      }
    }
    
    // Existing rules for other collections...
    match /Events/{eventId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && 
        request.auth.uid == resource.data.customerUid;
    }
    
    match /Attendance/{attendanceId} {
      allow read, write: if request.auth != null;
    }
    
    // Add other existing rules here...
  }
}
```

## How to Deploy the Rules

1. **Using Firebase CLI:**
   ```bash
   firebase deploy --only firestore:rules
   ```

2. **Using Firebase Console:**
   - Go to Firebase Console
   - Navigate to Firestore Database
   - Click on "Rules" tab
   - Replace the existing rules with the ones above
   - Click "Publish"

## What These Rules Do

1. **Customer Documents**: Users can read/write their own customer document
2. **Public Profiles**: Users can read other customer documents (for public profiles)
3. **Followers Collection**: Users can read/write their own followers and the followers of users they follow
4. **Following Collection**: Users can read/write their own following list and the following list of users they follow

## Testing the Rules

After deploying the rules, the follow/following feature should work without permission errors. The app will:

- ✅ Load follower/following counts without errors
- ✅ Allow users to follow/unfollow other users
- ✅ Show proper follow status
- ✅ Update counts in real-time

## Alternative: Disable Follow Feature Temporarily

If you want to disable the follow feature until the rules are set up, you can modify the UserProfileScreen to hide the follow button:

```dart
// In _buildActionButtons(), comment out the follow button:
// if (!widget.isOwnProfile) ...[
//   // Follow button code...
// ]
```

## Debugging

If you still see permission errors after deploying the rules:

1. Check that the rules were deployed successfully
2. Verify the user is authenticated
3. Check the Firebase Console logs for more details
4. Ensure the user IDs match the expected format

## Note

The follow/following feature will work with 0 counts until users actually start following each other. This is normal behavior. 