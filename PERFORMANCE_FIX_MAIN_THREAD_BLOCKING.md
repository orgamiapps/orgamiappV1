# Performance Fix: Main Thread Blocking Issue

## Problem
The app was experiencing severe performance issues on startup:
- **"Skipped 418 frames"** - main thread blocked for over 8 seconds
- **"Davey! duration=8581ms"** - single frame took 8.5 seconds to render
- App became completely unresponsive during startup
- Multiple "doing too much work on main thread" warnings

## Root Cause
The `DashboardScreen` was using `IndexedStack` to manage 6 different tabs (HomeHubScreen, GroupsScreen, MessagingScreen, MyProfileScreen, NotificationsScreen, AccountScreen).

**The Problem with IndexedStack:**
- IndexedStack initializes **ALL** child widgets immediately, even if they're not visible
- All 6 screens' `initState()` methods ran simultaneously
- Each screen started loading data from Firestore immediately:
  - HomeHubScreen: Loading organizations and running discovery queries
  - GroupsScreen: Loading user groups and organization streams
  - MessagingScreen: Loading conversations
  - MyProfileScreen: Loading profile data, events, badges
  - NotificationsScreen: Loading notifications
  - AccountScreen: Loading user data and subscription info

**Result:** 6+ concurrent Firestore queries running on app startup, all blocking the main thread.

## Solution Applied

### 1. Implemented Lazy Loading in DashboardScreen
**File:** `lib/screens/Home/dashboard_screen.dart`

**Changes:**
- Replaced eager initialization of all 6 screens
- Added screen visit tracking with `_visitedScreens` Set
- Only build screens that have been visited by the user
- Cache built screens in `_screenCache` to preserve state
- Use `SizedBox.shrink()` placeholder for unvisited screens

**Before:**
```dart
// All 6 screens initialized immediately in initState
_screens = const [
  HomeHubScreen(),
  GroupsScreen(),
  MessagingScreen(),
  MyProfileScreen(showBackButton: false),
  NotificationsScreen(),
  AccountScreen(),
];
```

**After:**
```dart
// Only build screens when visited
children: List.generate(6, (index) {
  if (_visitedScreens.contains(index)) {
    return _screenCache.putIfAbsent(index, () => _buildScreen(index));
  }
  return const SizedBox.shrink();
}),
```

**Impact:**
- ✅ Only 1 screen (HomeHubScreen) initializes on app startup instead of 6
- ✅ Reduces initial Firestore queries from 6+ to 1
- ✅ Subsequent tabs load on-demand when user navigates to them
- ✅ Screen state is preserved after first visit via caching

### 2. Optimized HomeHubScreen Data Loading
**File:** `lib/screens/Home/home_hub_screen.dart`

**Changes:**
- Moved data loading to `addPostFrameCallback` instead of directly in `initState`
- Added 100ms delay before starting discovery query
- Set loading state immediately for better UX
- Allows UI to render before heavy Firestore operations begin

**Before:**
```dart
void initState() {
  super.initState();
  _loadOrgs(); // Blocks UI rendering
}
```

**After:**
```dart
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      _loadOrgs(); // Runs after first frame renders
    }
  });
}
```

**Impact:**
- ✅ UI renders immediately, showing loading indicators
- ✅ Heavy Firestore queries run after initial frame
- ✅ Better perceived performance for users

## Expected Performance Improvements

### Before Fix:
1. DashboardScreen created → All 6 screens initialize
2. 6+ Firestore queries start simultaneously
3. Main thread blocked for 8+ seconds
4. App appears frozen
5. User sees white screen or unresponsive UI

### After Fix:
1. DashboardScreen created → Only HomeHubScreen initializes
2. 1 Firestore query starts (after first frame)
3. Main thread blocked for ~500ms-1s max
4. App renders quickly
5. User sees responsive UI with loading indicators
6. Other tabs load lazily when accessed

## Performance Metrics Expectations

**Startup Time:**
- Before: 8-15 seconds to full responsiveness
- After: 1-3 seconds to first interactive frame

**Skipped Frames:**
- Before: 418+ frames skipped (8+ seconds)
- After: <30 frames skipped (<500ms)

**Initial Firestore Queries:**
- Before: 6+ simultaneous queries
- After: 1 query (deferred)

**Memory Usage:**
- Before: All screen widgets in memory
- After: Only visited screens in memory

## Testing Recommendations

1. **Clean Install Test:**
   - Uninstall app completely
   - Install fresh build
   - Open app and measure time to first interactive screen
   - Should be under 3 seconds

2. **Navigation Test:**
   - Navigate through all 6 tabs
   - Verify each tab loads properly when first accessed
   - Verify tab state is preserved when switching back

3. **Console Monitoring:**
   - Watch for "Skipped frames" messages
   - Should not see "Skipped 418 frames" anymore
   - Should see lazy loading debug messages

## Additional Notes

- The Google Play Services errors in the console are emulator-specific and do not affect app performance
- The verification warnings are Android runtime optimizations and are expected
- The `characters` package override warnings are dependency constraints and are not related to performance

## Files Modified

1. `/lib/screens/Home/dashboard_screen.dart` - Implemented lazy loading
2. `/lib/screens/Home/home_hub_screen.dart` - Deferred heavy operations

## Breaking Changes

None. The changes are backward compatible and maintain the same user experience while improving performance.

