# My Profile Events - Testing Guide

## What Was Fixed

I've implemented comprehensive fixes and debugging tools to resolve the issue where events weren't appearing in the My Profile screen. Here's what was done:

### 1. Enhanced Debug Logging
- Added detailed logging throughout the event display pipeline
- Tracks data from fetch → state update → widget build → display
- Uses distinctive emoji prefixes for easy filtering:
  - 🔍 = Display/rendering logs
  - 🏗️ = Widget build logs  
  - 🔄 = State update logs
  - ✅/❌ = Success/error indicators

### 2. Visual Debug Tools
- **Debug Info Panel**: Shows in empty state with user ID, email, and event counts
- **Refresh Button**: Manual data reload in tab bar
- **Run Diagnostics Button**: Comprehensive Firebase query testing

### 3. Force Rebuild Mechanism
- Added post-frame callback to ensure UI updates after data loads
- Prevents potential state/rendering synchronization issues

### 4. Improved Empty State
- Now shows debugging information even when empty
- Provides actionable buttons for troubleshooting
- Displays real event counts to verify data is loaded

## How to Test

### Step 1: Clean Build and Run
```bash
cd /Users/paulreisinger/Downloads/orgamiappV1-main-2
flutter clean
flutter pub get
flutter run
```

### Step 2: Navigate to My Profile
1. Launch the app
2. Log in with your account
3. Go to the "My Profile" tab (usually bottom navigation)

### Step 3: Check Each Tab
Test all three event tabs:
- **Created**: Events you've created
- **Attended**: Events you've attended (with tickets or attendance records)
- **Saved**: Events you've favorited

### Step 4: If Events Don't Appear

#### A. Check Debug Info
If you see the empty state, look at the debug info box which shows:
- Your User ID
- Your Email  
- Event counts: Created: X, Attended: Y, Saved: Z

**If counts show 0 for all**: You genuinely have no events yet
**If counts show numbers > 0**: Events are loaded but not displaying

#### B. Try Manual Refresh
1. Click the **Refresh** button in the tab bar (top right area)
2. Wait for loading to complete
3. Check if events now appear

#### C. Run Diagnostics
1. Click **Run Diagnostics** button in the empty state
2. Check the Flutter console/terminal for detailed output
3. Look for the diagnostic section that shows:
   ```
   ========================================
   PROFILE DIAGNOSTICS
   ========================================
   User ID: ...
   User Email: ...
   Testing created events query...
   ✅ Created events: X (Yms)
   ```

### Step 5: Check Console Logs

The console will show detailed information about what's happening. Here's what to look for:

#### Normal Successful Flow:
```
MY_PROFILE_SCREEN: initState called
MY_PROFILE_SCREEN: PostFrameCallback executing
🔵 Starting parallel data fetch...
🔵 User ID: abc123...
🔵 Parallel data fetch completed
✅ Created events count: 5
✅ Attended events count: 3
✅ Saved events count: 2
🔄 About to call setState with:
  - created.length: 5
  - attended.length: 3
  - saved.length: 2
✅ MY_PROFILE_SCREEN: Profile data loaded and state updated
AFTER setState:
State - createdEvents.length: 5
State - attendedEvents.length: 3
State - savedEvents.length: 2
🔄 Forced UI rebuild after data load
🏗️ MY_PROFILE_SCREEN build() called
🏗️ isLoading: false
🏗️ createdEvents: 5
🏗️ attendedEvents: 3
🏗️ savedEvents: 2
🔍 _buildTabContent called
🔍 selectedTab: 1 (1=Created, 2=Attended, 3=Saved)
🔍 Raw events count: 5
🔍 After sorting: 5 events
```

#### Problem Indicators:
```
⚠️ Created events fetch timed out after 15 seconds
❌ Error fetching created events: ...
❌ No created events returned from Firebase query
⚠️⚠️⚠️ WARNING: All event lists are empty after setState!
❌ MY_PROFILE_SCREEN: User not logged in
⚠️⚠️⚠️ WARNING: User ID mismatch!
```

## Common Issues and Solutions

### Issue 1: All Event Counts Are 0
**Diagnosis**: You haven't created, attended, or saved any events yet.

**Solution**: 
- Create an event (use Create Event feature)
- Attend an event (get a ticket)
- Save an event (favorite it)
- Then check My Profile again

### Issue 2: Public Profile Shows Events, My Profile Doesn't
**Diagnosis**: Potential user ID mismatch or state synchronization issue.

**Solution**:
1. Check debug info panel for your User ID and Email
2. Navigate to public profile and compare data
3. Click Refresh in My Profile
4. If issue persists, log out and log back in

### Issue 3: Some Tabs Work, Others Don't
**Diagnosis**: Specific Firebase query is failing.

**Solution**:
1. Run Diagnostics to see which query fails
2. Check console for specific error messages
3. Verify Firebase indexes are set up (see below)

### Issue 4: Events Appear After Refresh But Not on Initial Load
**Diagnosis**: Timing/initialization issue.

**Solution**: This might be normal behavior due to deferred loading. The fix ensures manual refresh works. If it's problematic, we can adjust initialization timing.

### Issue 5: Filter/Sort Button is Highlighted
**Diagnosis**: You have active filters that might be hiding events.

**Solution**:
1. Click the Filter/Sort button
2. Click "Reset" at the bottom
3. Click "Done"
4. Check if events now appear

## Firebase Index Requirements

For optimal performance, ensure these Firebase indexes exist:

### Index 1: Events by Creator
- **Collection**: Events
- **Fields**: 
  - customerUid (Ascending)
  - eventGenerateTime (Descending)

### Index 2: Attendance by User
- **Collection**: Attendance
- **Fields**:
  - customerUid (Ascending)
  - timestamp (Descending)

### Index 3: Tickets by User  
- **Collection**: Tickets
- **Fields**:
  - customerUid (Ascending)
  - purchaseDate (Descending)

The app will work without these but may be slower and show timeout warnings.

## Expected Behavior

### With Events:
- Events display in their respective tabs
- Tab badges show correct counts
- Events are sorted by date (most recent first)
- Pull-to-refresh works
- Manual refresh button works

### Without Events:
- Empty state shows with friendly message
- Debug info displays correct user information  
- All event counts show 0
- Action buttons work (Refresh, Run Diagnostics)

## Debugging Commands

### View Real-Time Logs
```bash
flutter run | grep -E "(MY_PROFILE_SCREEN|🔍|🏗️|🔄|Created events|Attended events|Saved events)"
```

### Filter for Errors Only
```bash
flutter run | grep -E "(❌|⚠️|ERROR|PERMISSION)"
```

### Run Diagnostics Manually
The diagnostic utility is built into the UI (Run Diagnostics button), but you can also trigger it programmatically if needed.

## Verification Checklist

- [ ] App compiles without errors (`flutter analyze` shows no issues)
- [ ] My Profile tab loads without crashing
- [ ] Tab bar shows three tabs: Created, Attended, Saved
- [ ] Tab badges show correct event counts
- [ ] Clicking tabs switches between event lists
- [ ] Events display correctly (if you have any)
- [ ] Empty state shows debug info when no events
- [ ] Refresh button triggers data reload
- [ ] Run Diagnostics shows console output
- [ ] Pull-to-refresh works on the screen
- [ ] Events match what's shown in public profile

## Next Steps if Issue Persists

If after following this guide events still don't appear:

1. **Collect Information**:
   - Take screenshot of empty state with debug info
   - Save console output from diagnostic run
   - Note your User ID and Email
   - Note what works in public profile vs My Profile

2. **Verify Firebase Data**:
   - Go to Firebase Console
   - Check Events collection for events with your User ID as customerUid
   - Check Attendance collection for records with your User ID
   - Check Tickets collection for tickets with your User ID
   - Check your user document's "favorites" array

3. **Check Firestore Rules**:
   - Verify you can read Events collection
   - Verify you can read Attendance collection
   - Verify you can read Tickets collection
   - Test queries directly in Firebase Console

4. **Report Issue**:
   - Provide console logs
   - Provide screenshots
   - Share User ID (first few characters only for privacy)
   - Describe exact steps to reproduce

## Files Modified

- `lib/screens/MyProfile/my_profile_screen.dart`: Enhanced with debugging and fixes
- `MY_PROFILE_EVENTS_FIX_SUMMARY.md`: Technical documentation
- `MY_PROFILE_EVENTS_TESTING_GUIDE.md`: This file

## Additional Resources

- Firebase Console: https://console.firebase.google.com
- Flutter Debugging: https://flutter.dev/docs/testing/debugging
- Check previous fix documentation in the project:
  - `MY_PROFILE_ALL_EVENTS_FIX_COMPLETE.md`
  - `PROFILE_EVENTS_ALL_DISPLAY_FIX.md`

