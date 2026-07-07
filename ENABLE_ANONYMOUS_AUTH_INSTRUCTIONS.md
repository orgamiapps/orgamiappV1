# ⚠️ CRITICAL: Enable Anonymous Authentication

## 🚨 Current Error
You're seeing this error because Anonymous Authentication is **NOT enabled** in your Firebase project:

```
[firebase_auth/admin-restricted-operation] This operation is restricted to administrators only.
```

This prevents guest users from accessing the app.

## ✅ How to Fix (3 Simple Steps)

### Step 1: Open Firebase Console
1. Go to: https://console.firebase.google.com
2. Select your project: **Attendus/Orgami**

### Step 2: Navigate to Authentication
1. In the left sidebar, click **"Authentication"**
2. Click on the **"Sign-in method"** tab at the top

### Step 3: Enable Anonymous Authentication
1. Scroll down to find **"Anonymous"** in the list of providers
2. Click on **"Anonymous"**
3. Toggle the switch to **"Enable"**
4. Click **"Save"**

## 📸 Visual Guide

```
Firebase Console
└── Your Project (Attendus/Orgami)
    └── Authentication
        └── Sign-in method (tab)
            └── Anonymous (provider)
                └── Enable ✅
                └── Save
```

## 🧪 Verify It's Enabled

After enabling, you should see:
- **Anonymous** listed under "Sign-in providers"
- Status shows **"Enabled"** with a green checkmark ✅

## 🔄 Test Guest Mode Again

1. **Clear app data** or reinstall the app
2. Launch the app
3. Tap **"Continue as Guest"**
4. You should see in the logs:
   ```
   ✅ "Signing in anonymously to Firebase for guest mode..."
   ✅ "Anonymous sign-in successful: [UID]"
   ```
5. Home hub should load **without permission errors**

## ❓ Why Is This Needed?

### The Problem
- Guest users need to access Firestore to view events and organizations
- Firestore security rules require authentication: `request.auth != null`
- Without Firebase Auth, all Firestore queries fail with `PERMISSION_DENIED`

### The Solution
- Anonymous Authentication gives guest users a temporary Firebase Auth session
- This session allows them to pass the `request.auth != null` check
- Firestore security rules allow read access for anonymous users
- Write operations are still restricted to fully authenticated users

### Security
- Anonymous users get a temporary, randomly-generated UID
- No personal data is collected or stored
- Anonymous sessions are device-specific
- When user creates account, anonymous session is replaced
- Firestore rules prevent anonymous users from creating/modifying content

## 🎯 What You'll See After Enabling

### Before (Current State) ❌
```
❌ Error enabling guest mode
❌ [firebase_auth/admin-restricted-operation]
❌ PERMISSION_DENIED errors in Firestore
❌ Guest users cannot view events
```

### After (Fixed) ✅
```
✅ Signing in anonymously to Firebase for guest mode...
✅ Anonymous sign-in successful: [random-uid]
✅ Guest mode enabled with session: guest_123456789
✅ Home hub loads successfully
✅ Events and organizations are displayed
```

## 🚀 Additional Steps

After enabling Anonymous Authentication, also deploy the updated Firestore rules:

```bash
./deploy_guest_mode_fix.sh
```

Or manually:
```bash
firebase deploy --only firestore:rules
```

## 📞 Still Having Issues?

If you've enabled Anonymous Authentication but still see errors:

1. **Check Firebase Console**:
   - Verify "Anonymous" shows as "Enabled"
   - Check if there are any project restrictions

2. **Clear App Data**:
   - Completely uninstall the app
   - Reinstall from scratch
   - Try guest mode again

3. **Check Firestore Rules**:
   - Make sure rules are deployed
   - Verify rules allow read access for `isAuthenticated()`

4. **Check Network**:
   - Ensure device has internet connection
   - Check if Firebase services are reachable

## 📋 Quick Checklist

- [ ] Anonymous Authentication enabled in Firebase Console
- [ ] Firestore rules deployed (`firebase deploy --only firestore:rules`)
- [ ] App data cleared or app reinstalled
- [ ] Tested "Continue as Guest" button
- [ ] Verified no permission errors in logs
- [ ] Confirmed events are loading on home hub

## 🎉 Success Criteria

✅ **Guest Mode is Working When:**
- No `admin-restricted-operation` errors
- No `PERMISSION_DENIED` errors
- Guest users can view events and organizations
- Home hub screen loads successfully
- Anonymous users appear in Firebase Console → Authentication → Users

---

**Priority**: 🔴 **CRITICAL** - Must be completed before guest mode will work

**Estimated Time**: ⏱️ **2 minutes**

**Difficulty**: ⭐ **Very Easy**

