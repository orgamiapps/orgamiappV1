# My Profile Events Diagnostic Guide

## Issue
Events are not appearing on the "My Profile" screen under the Created, Attended, and Saved tabs, even though the user has events that show up on other user profile screens.

## Changes Made

### 1. Enhanced Debug Logging
Added comprehensive debug logging throughout the `my_profile_screen.dart` to track:
- User authentication status (both CustomerController and Firebase Auth)
- User ID comparison between CustomerController and Firebase Auth
- Event fetch operations and their results
- Timeout and error conditions
- Individual event details when fetched

### 2. Added Tools
- **Refresh Button**: Manually trigger data reload
- **Enhanced Error Messages**: Toast notifications for timeout and error conditions

### 3. Improved Error Handling
- Added stack traces to error logging
- Added toast notifications for all fetch failures
- Added user ID mismatch detection
- Added individual event logging for debugging

## How to Diagnose the Issue

### Step 1: Check Debug Logs
1. Run the app with Flutter in debug mode:
   ```bash
   cd /Users/paulreisinger/Downloads/orgamiappV1-main-2
   flutter run
   ```

2. Navigate to the "My Profile" screen

3. Look for these debug messages in the console:
   ```
   MY_PROFILE_SCREEN: Starting to load profile data
   CustomerController User ID: [USER_ID]
   Firebase Auth User ID: [AUTH_ID]
   UIDs Match: [true/false]
   ```

4. Check for event fetch results:
   ```
   MY_PROFILE_SCREEN: Events fetched results:
   ✅ Created events count: [NUMBER]
   ✅ Attended events count: [NUMBER]
   ✅ Saved events count: [NUMBER]
   ```

 

### Step 3: Check for Errors
Look for any of these error indicators:
- ⚠️ Timeout messages (queries taking too long)
- ❌ Error messages (query failures)
- ⚠️⚠️⚠️ User ID mismatch warnings
- Toast notifications about errors

### Step 4: Verify Firebase Connection
The diagnostic test will help verify:
- The user is properly authenticated
- The user ID is correct
- Events exist in the database for this user
- Firebase queries are working

## Common Issues and Solutions

### Issue 1: User ID Mismatch
**Symptoms:** Debug logs show UIDs don't match  
**Solution:** User needs to log out and log back in

### Issue 2: Firebase Query Timeout
**Symptoms:** Toast messages about timeouts  
**Solution:** Check internet connection, Firebase status, or increase timeout values

### Issue 3: No Events in Database
**Symptoms:** Direct query test shows 0 events  
**Solution:** Verify events are actually created and assigned to the correct user ID

### Issue 4: Permission Issues
**Symptoms:** Permission denied errors in logs  
**Solution:** Check Firestore security rules

### Issue 5: Events Belong to Different User
**Symptoms:** Test query shows 0 events but events visible elsewhere  
**Solution:** The events might be owned by a different user ID than the logged-in user

## Expected Behavior

When working correctly:
1. The "My Profile" screen loads
2. Debug logs show the user ID and Firebase Auth ID match
3. Event queries complete successfully (no timeouts or errors)
4. Event counts appear in the tabs: "Created (X)", "Attended (Y)", "Saved (Z)"
5. Events are displayed when each tab is selected

## Next Steps

1. Run the app and check the debug logs
2. Share the debug output with the development team
4. Based on the logs, we can identify the specific issue:
   - Authentication problem
   - Query timeout
   - No events in database
   - User ID mismatch
   - Permission issues

## Debug Log Examples

### Successful Load:
```
MY_PROFILE_SCREEN: Starting to load profile data
CustomerController User ID: abc123
Firebase Auth User ID: abc123
UIDs Match: true
🔵 Starting parallel data fetch...
🔵 Parallel data fetch completed
MY_PROFILE_SCREEN: Events fetched results:
✅ Created events count: 5
✅ Attended events count: 3
✅ Saved events count: 2
```

### Failed Load (Timeout):
```
MY_PROFILE_SCREEN: Starting to load profile data
🔵 Starting parallel data fetch...
⚠️ Created events fetch timed out after 15 seconds
⚠️ Attended events fetch timed out after 15 seconds
✅ Created events count: 0
✅ Attended events count: 0
```

### User ID Mismatch:
```
CustomerController User ID: abc123
Firebase Auth User ID: xyz789
UIDs Match: false
⚠️⚠️⚠️ WARNING: User ID mismatch!
```

## Files Modified
- `/lib/screens/MyProfile/my_profile_screen.dart`
  - Added Firebase Auth import
  - Added Firestore import
  - Added user ID verification
  - Added enhanced debug logging
  - Added refresh button
  - Improved error handling with toast notifications

