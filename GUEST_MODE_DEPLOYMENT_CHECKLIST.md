# Guest Mode Deployment Checklist

## ⚠️ BEFORE TESTING - REQUIRED SETUP

### 1. Enable Anonymous Authentication in Firebase Console ⚠️ **CRITICAL**

**This is the FIRST step and is REQUIRED for guest mode to work!**

1. Go to: https://console.firebase.google.com
2. Select your project
3. Click **Authentication** in the left sidebar
4. Click **Sign-in method** tab
5. Find **Anonymous** in the providers list
6. Click on **Anonymous**
7. Toggle to **Enable**
8. Click **Save**

**Verification**: You should see "Anonymous" with status "Enabled" ✅

**If you skip this step, you will get this error:**
```
[firebase_auth/admin-restricted-operation] This operation is restricted to administrators only.
```

### 2. Deploy Updated Firestore Security Rules

Run the deployment script:
```bash
./deploy_guest_mode_fix.sh
```

Or manually:
```bash
firebase deploy --only firestore:rules
```

**Verification**: Check Firebase Console → Firestore → Rules to see updated rules

## 📱 TESTING CHECKLIST

### Before Testing
- [ ] Anonymous Authentication enabled in Firebase Console (REQUIRED!)
- [ ] Firestore rules deployed successfully
- [ ] App data cleared OR app reinstalled

### Test 1: Guest Mode Activation
- [ ] Launch the app
- [ ] Tap "Continue as Guest" on splash screen
- [ ] Check logs for: `✅ Anonymous sign-in successful`
- [ ] NO errors about `admin-restricted-operation`
- [ ] User navigates to Home Hub screen

### Test 2: Home Hub - Guest View
- [ ] Guest banner visible at top
- [ ] Public tab shows organizations/events
- [ ] NO `PERMISSION_DENIED` errors in logs
- [ ] Events are displayed (not empty state due to errors)
- [ ] Can tap on events to view details

### Test 3: Firebase Console Verification
- [ ] Go to Firebase Console → Authentication → Users
- [ ] You should see an anonymous user created
- [ ] User ID is a random string
- [ ] Sign-in provider shows "Anonymous"

### Test 4: Navigation & Features
- [ ] Map button works (global events map loads)
- [ ] Calendar button works (calendar loads)
- [ ] Search button works
- [ ] Event details screen loads
- [ ] Guest banner persists across screens

### Test 5: Event Sign-In
- [ ] Can scan QR code or enter manual code
- [ ] Name field appears for guest users
- [ ] Can submit attendance
- [ ] Attendance record created in Firestore
- [ ] NO permission errors during sign-in

### Test 6: Restrictions Work
- [ ] Tap FAB (create event) → Shows restriction dialog
- [ ] Dialog has "Create Account" button
- [ ] Private tab is hidden for guests
- [ ] Cannot access restricted features

### Test 7: Account Creation
- [ ] Tap "Sign Up" from guest banner
- [ ] Can create account successfully
- [ ] Guest mode is disabled after account creation
- [ ] Guest banner disappears
- [ ] Private tab becomes visible
- [ ] Full app access granted

### Test 8: App Restart Persistence
- [ ] Close app completely
- [ ] Reopen app
- [ ] If still in guest mode, should stay in guest mode
- [ ] If created account, should stay logged in

## 🔍 EXPECTED LOG OUTPUT

### ✅ Correct Output (Working)
```
ℹ️ INFO: Signing in anonymously to Firebase for guest mode...
ℹ️ INFO: Anonymous sign-in successful: AbCdEf123456
ℹ️ INFO: Guest mode enabled with session: guest_1234567890
🏠 HomeHubScreen: Creating Firestore query...
🏠 HomeHubScreen: Query completed, got X organizations
```

### ❌ Incorrect Output (Not Working)
```
❌ ERROR: Error enabling guest mode
Error details: [firebase_auth/admin-restricted-operation]
PERMISSION_DENIED errors in Firestore queries
```

**If you see the error above**: Go back to Step 1 and enable Anonymous Authentication!

## 🐛 TROUBLESHOOTING

### Issue: "admin-restricted-operation" error
**Cause**: Anonymous Authentication not enabled in Firebase Console

**Fix**:
1. Go to Firebase Console → Authentication → Sign-in method
2. Enable "Anonymous" provider
3. Clear app data and retry

### Issue: "PERMISSION_DENIED" from Firestore
**Cause**: Either:
- Anonymous auth not enabled, OR
- Firestore rules not deployed

**Fix**:
1. Verify anonymous auth is enabled
2. Deploy Firestore rules: `firebase deploy --only firestore:rules`
3. Clear app data and retry

### Issue: Anonymous user not appearing in Firebase Console
**Cause**: Anonymous sign-in is failing

**Fix**:
1. Check Firebase Console that Anonymous is enabled
2. Check app logs for specific error message
3. Verify Firebase configuration files are up to date

### Issue: Guest can see events but gets errors on sign-in
**Cause**: Firestore rules might not allow write to Attendees collection

**Fix**:
1. Check Firestore rules allow write for `isAuthenticated()`
2. Verify Attendees collection rules specifically
3. Deploy rules and test again

## ✅ SUCCESS CRITERIA

Guest mode is working correctly when:

- [x] No `admin-restricted-operation` errors
- [x] No `PERMISSION_DENIED` errors in Firestore
- [x] Anonymous users appear in Firebase Console
- [x] Guest banner shows on home hub
- [x] Events and organizations load successfully
- [x] Guest can view event details
- [x] Guest can sign in to events
- [x] Restrictions work (can't create events)
- [x] Account creation flow works
- [x] Guest to user transition is seamless

## 📊 MONITORING

### Firebase Console - Things to Check

**Authentication → Users**:
- Anonymous users are being created
- Each guest gets a unique random UID

**Firestore → Data**:
- Attendance records have anonymous UIDs
- No unauthorized writes by anonymous users

**Firestore → Rules**:
- Updated rules are deployed
- `isAuthenticated()` and `isFullyAuthenticated()` functions exist

### App Logs - Look For

**Good Signs ✅**:
- "Anonymous sign-in successful"
- "Guest mode enabled with session"
- Firestore queries completing successfully
- No permission errors

**Bad Signs ❌**:
- "admin-restricted-operation"
- "PERMISSION_DENIED"
- "Error enabling guest mode"
- Firestore queries failing

## 🚀 DEPLOYMENT ORDER

**Follow this exact order:**

1. ✅ **Enable Anonymous Authentication** (Firebase Console)
2. ✅ **Deploy Firestore Rules** (`firebase deploy --only firestore:rules`)
3. ✅ **Clear app data or reinstall app**
4. ✅ **Test guest mode**
5. ✅ **Verify in Firebase Console**
6. ✅ **Monitor logs**

**DO NOT skip step 1!** Everything else will fail without it.

## 📞 SUPPORT

If issues persist after following all steps:

1. Screenshot the error logs
2. Check Firebase Console for any service outages
3. Verify Firebase project settings
4. Ensure you're deploying to the correct Firebase project

---

**Last Updated**: October 28, 2025  
**Status**: Ready for Deployment  
**Priority**: 🔴 CRITICAL

