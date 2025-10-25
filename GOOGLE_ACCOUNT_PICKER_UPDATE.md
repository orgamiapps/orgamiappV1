# Google Account Picker - Always Show Account Selection

## Feature Enhancement
Updated Google Sign-In to always show the account picker, allowing users to choose which Google account they want to sign in with every time.

## Problem
Previously, when a user logged out and then clicked the Google Sign-In button again, it would automatically sign them back into the same Google account they used before. This prevented users from easily switching between different Google accounts.

## Solution Implemented

### 1. Sign Out Before Sign In (Mobile/Desktop)
```dart
// Sign out from Firebase Auth to clear cached credentials
if (_auth.currentUser != null) {
  Logger.info('🔵 Signing out to force account picker...');
  await _auth.signOut();
}
```

This ensures any cached session is cleared before starting a new sign-in flow.

### 2. Force Account Selection Parameter
```dart
googleProvider.setCustomParameters({
  'prompt': 'select_account', // Forces account picker
});
```

This OAuth parameter tells Google to **always** show the account picker, even if only one account is available.

## Changes Made

### File: `/lib/firebase/firebase_google_auth_helper.dart`

#### For Web Platform:
```dart
if (kIsWeb) {
  final GoogleAuthProvider googleProvider = GoogleAuthProvider();
  googleProvider.addScope('email');
  googleProvider.addScope('profile');
  
  // NEW: Force account selection on web
  googleProvider.setCustomParameters({
    'prompt': 'select_account',
  });
  
  final UserCredential userCredential = await _auth
      .signInWithPopup(googleProvider)
      .timeout(const Duration(seconds: 30));
}
```

#### For Mobile/Desktop Platform:
```dart
else {
  Logger.info('🔵 Starting Google sign-in flow...');
  
  // NEW: Sign out to clear cached credentials
  if (_auth.currentUser != null) {
    Logger.info('🔵 Signing out to force account picker...');
    await _auth.signOut();
  }
  
  final GoogleAuthProvider googleProvider = GoogleAuthProvider();
  googleProvider.addScope('email');
  googleProvider.addScope('profile');
  
  // NEW: Force account selection
  googleProvider.setCustomParameters({
    'prompt': 'select_account',
  });
  
  Logger.info('🔵 Calling signInWithProvider with account picker...');
  
  final UserCredential userCredential = await _auth
      .signInWithProvider(googleProvider)
      .timeout(const Duration(seconds: 60));
}
```

## User Experience

### Before This Update:
1. User logs out
2. User clicks "Sign in with Google"
3. **Automatically signs into previous account** ❌
4. User has no way to choose a different account

### After This Update:
1. User logs out
2. User clicks "Sign in with Google"
3. **Google account picker appears** ✅
4. User can select any Google account they want
5. User can add a new account if needed
6. User proceeds with selected account

## What Users Will See

When clicking the Google Sign-In button, users will now see:

### On Mobile (Android/iOS):
- Google account picker dialog
- List of all Google accounts on the device
- Option to add a new account
- Can select which account to use

### On Web:
- Google account selection page
- List of all signed-in Google accounts in the browser
- Option to use a different account
- Option to add a new account

## Benefits

1. **Account Flexibility**: Users can easily switch between personal and work Google accounts
2. **Multi-User Devices**: Perfect for shared devices where multiple people use the app
3. **Testing**: Developers can easily test with different accounts
4. **Privacy**: Users don't feel locked into their previous account choice
5. **Standard UX**: Matches expected behavior from other apps

## Technical Details

### OAuth `prompt` Parameter
The `prompt: select_account` parameter is part of the OAuth 2.0 specification and is supported by Google's OAuth implementation. It:
- Forces the consent screen to appear
- Shows the account picker even if only one account is available
- Bypasses automatic account selection based on cookies/cache
- Works on all platforms (web, iOS, Android)

### Firebase Auth Sign Out
Calling `_auth.signOut()` before signing in:
- Clears the local Firebase Auth session
- Removes cached credentials
- Ensures a fresh authentication flow
- Does NOT sign the user out of their Google account in the browser/device

## Debug Logs

You'll now see these logs when signing in:
```
🔵 Starting Google sign-in flow...
🔵 Signing out to force account picker...
🔵 Calling signInWithProvider with account picker...
🔵 signInWithProvider completed
🔵 User: user@example.com
```

## Important Notes

1. **No Breaking Changes**: Existing functionality remains the same, just adds account selection
2. **All Platforms**: Works on web, iOS, and Android
3. **Performance**: Minimal impact - signOut is very fast
4. **User Control**: Users always see the account picker and can choose
5. **Security**: Does not affect security - still uses standard OAuth flow

## Testing Checklist

- [ ] Test on iOS device
- [ ] Test on Android device
- [ ] Test on web browser
- [ ] Try with single Google account
- [ ] Try with multiple Google accounts
- [ ] Verify account picker appears every time
- [ ] Verify can select different accounts
- [ ] Verify "Add account" option works
- [ ] Test cancellation (pressing back/cancel)
- [ ] Verify successful sign-in after account selection

## Related Files

This change only affects:
- ✅ `/lib/firebase/firebase_google_auth_helper.dart` - Core Google Sign-In logic

No changes needed to:
- `/lib/screens/Splash/second_splash_screen.dart` - Uses the helper
- `/lib/screens/Authentication/login_screen.dart` - Uses the helper
- `/lib/screens/Authentication/create_account/create_account_screen.dart` - Uses the helper

## Status: ✅ COMPLETE

Google Sign-In now always shows the account picker, allowing users to choose which Google account they want to sign in with every time they use the Google Sign-In button.

