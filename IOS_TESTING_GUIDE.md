# iOS Testing Guide for App Store Submission

This guide helps you test AttendUs thoroughly before submitting to the App Store.

---

## 🎯 Testing Overview

**Why Test?**
- Apple tests your app during review
- Crashes = automatic rejection
- 70% of rejections are preventable with proper testing

**What to Test:**
1. Core functionality (everything should work)
2. All permission requests
3. Edge cases (no internet, background, etc.)
4. Different device sizes
5. Minimum iOS version (15.0)

---

## 📱 Required Test Devices

### Minimum Testing Setup
- **At least one real iOS device** (iPhone or iPad)
- **iOS 15.0 or higher** (your minimum version)
- **Latest iOS** (17 or 18) if possible

### Ideal Testing Setup
- iPhone with iOS 15 (or lowest version you support)
- iPhone with latest iOS
- One small screen (iPhone SE or iPhone 13 mini)
- One large screen (iPhone 15 Pro Max)
- iPad (if supporting iPad)

**Don't have devices?**
- Borrow from friends/family
- Use TestFlight with beta testers
- Apple Developer Lab (remote testing)

---

## ✅ Pre-Testing Setup

### 1. Clean Build
```bash
# Start fresh
cd /Users/paulreisinger/Downloads/orgamiappV1-main-2

# Clean Flutter
flutter clean
flutter pub get

# Clean iOS
cd ios
pod deintegrate
pod install
cd ..

# Build fresh
flutter build ios --debug
```

### 2. Install on Test Device

**Via Xcode:**
1. Connect device via USB
2. Open `ios/Runner.xcworkspace` in Xcode
3. Select your device at top
4. Click Run (▶)

**Via TestFlight (recommended for multiple testers):**
1. Build release: `flutter build ios --release`
2. Archive in Xcode
3. Upload to TestFlight
4. Add internal testers
5. Install TestFlight app on device
6. Install your app

---

## 🧪 Testing Checklist

### Phase 1: Launch & Account (10 minutes)

**First Launch:**
- [ ] App launches successfully
- [ ] No crashes on launch
- [ ] Splash screen displays
- [ ] No error messages
- [ ] Logo/branding displays correctly

**Create Account:**
- [ ] Can tap "Sign Up" / "Create Account"
- [ ] Email signup form works
- [ ] Can enter name, email, password
- [ ] Password validation works
- [ ] Can see password (eye icon works)
- [ ] "Sign Up" button works
- [ ] Account created successfully
- [ ] Redirects to home after signup

**Login:**
- [ ] Can enter email and password
- [ ] "Sign In" button works
- [ ] Successful login redirects to home
- [ ] Wrong password shows error
- [ ] Wrong email shows error
- [ ] Form validation works

**Google Sign In:**
- [ ] "Continue with Google" button appears
- [ ] Tapping opens Google login
- [ ] Can select Google account
- [ ] Successfully signs in
- [ ] Returns to app
- [ ] Profile data populated

**Apple Sign In:**
- [ ] "Continue with Apple" button appears
- [ ] Equal prominence to Google
- [ ] Tapping opens Apple login
- [ ] Face ID / Touch ID works
- [ ] Successfully signs in
- [ ] Returns to app
- [ ] Profile data populated

**Forgot Password:**
- [ ] "Forgot Password?" link works
- [ ] Can enter email
- [ ] Reset email sent
- [ ] Email received
- [ ] Reset link works

---

### Phase 2: Permissions (15 minutes)

**Camera Permission:**
- [ ] Permission request appears when needed
- [ ] Description is clear and specific ✓
- [ ] "Allow" button works
- [ ] "Don't Allow" is handled gracefully
- [ ] Camera works after allowing
- [ ] QR scanner works
- [ ] Can scan QR codes successfully

**Location Permission:**
- [ ] Permission request appears
- [ ] Description is clear ✓
- [ ] "Allow While Using App" works
- [ ] "Allow Once" works
- [ ] Map shows current location
- [ ] Nearby events shown based on location
- [ ] Location icon appears in status bar when active

**Photo Library Permission:**
- [ ] Request appears when uploading photo
- [ ] Description is clear ✓
- [ ] "Allow" button works
- [ ] Can select photo from library
- [ ] Can select multiple photos
- [ ] Photos upload successfully
- [ ] Thumbnails display correctly

**Photo Library Add Permission:**
- [ ] Request appears when saving
- [ ] Description is clear ✓
- [ ] Can save QR codes to Photos
- [ ] Can save tickets to Photos
- [ ] Saved photos appear in Photos app

**Push Notifications:**
- [ ] Permission request appears (not immediately on launch!)
- [ ] "Allow" works
- [ ] "Don't Allow" is handled gracefully
- [ ] Can enable later in Settings
- [ ] Test notifications received
- [ ] Notification sound works
- [ ] Badge count works
- [ ] Tapping notification opens relevant screen

**NFC (if device supports):**
- [ ] NFC icon appears where used
- [ ] Tapping starts NFC session
- [ ] Can hold phone near NFC tag
- [ ] NFC read works
- [ ] Session ends properly
- [ ] Error messages clear if fails

---

### Phase 3: Core Features (30 minutes)

**Home Screen:**
- [ ] Events load and display
- [ ] Event images load
- [ ] Event titles show
- [ ] Event dates/times correct
- [ ] Can scroll through events
- [ ] Pull to refresh works
- [ ] Empty state displays if no events
- [ ] Search icon visible
- [ ] Profile icon visible

**Event Discovery:**
- [ ] Can search for events
- [ ] Search results appear quickly
- [ ] Results relevant to search
- [ ] Can filter by category
- [ ] Can filter by date
- [ ] Can filter by distance
- [ ] Map view works
- [ ] Event pins on map correct
- [ ] Can tap event to view details

**Event Details:**
- [ ] Event page loads
- [ ] All event info displays:
  - Title
  - Description  
  - Date & time
  - Location (with map)
  - Organizer info
  - Number of attendees
- [ ] Event images/photos load
- [ ] Map shows location correctly
- [ ] "Get Directions" opens Maps
- [ ] "Share" button works
- [ ] RSVP/Register button works

**Create Event (if premium resolved):**
- [ ] Can tap "Create Event"
- [ ] Form appears
- [ ] Can enter event name
- [ ] Can enter description
- [ ] Can select date/time
- [ ] Date picker works
- [ ] Can set location (map or search)
- [ ] Can upload event image
- [ ] Can set event as public/private
- [ ] Can save draft
- [ ] Can publish event
- [ ] Created event appears in feed

**Ticket Purchase:**
- [ ] Can view available tickets
- [ ] Ticket prices displayed
- [ ] Can select ticket quantity
- [ ] "Buy Ticket" button works
- [ ] Stripe payment sheet opens
- [ ] Can enter payment details
- [ ] Payment processes successfully
- [ ] Confirmation shown
- [ ] Ticket appears in "My Tickets"
- [ ] QR code generated
- [ ] Can view QR code

**My Tickets:**
- [ ] "My Tickets" accessible from profile
- [ ] All purchased tickets display
- [ ] Ticket details correct
- [ ] QR codes display
- [ ] QR codes are scannable
- [ ] Can share ticket
- [ ] Can save QR to Photos
- [ ] Past tickets marked as past
- [ ] Upcoming tickets at top

**Groups:**
- [ ] Can view groups
- [ ] Can create a group
- [ ] Can join a group
- [ ] Group feed displays
- [ ] Can post in group
- [ ] Can see group events
- [ ] Can leave group
- [ ] Notifications for group activity

**Profile:**
- [ ] Profile page loads
- [ ] Profile picture displays
- [ ] Can edit profile
- [ ] Can change name
- [ ] Can upload new profile picture
- [ ] Can update bio
- [ ] My events shown
- [ ] My groups shown
- [ ] Settings accessible

**Settings:**
- [ ] Settings page opens
- [ ] Notification toggles work
- [ ] Privacy settings accessible
- [ ] Can log out
- [ ] Log out works properly
- [ ] Returns to login screen

---

### Phase 4: Edge Cases (20 minutes)

**No Internet Connection:**
- [ ] Enable Airplane Mode
- [ ] Open app
- [ ] App doesn't crash
- [ ] Shows appropriate message
- [ ] Cached data still displays
- [ ] Graceful error messages
- [ ] Can navigate cached content
- [ ] Reconnection works when internet returns

**Poor Network:**
- [ ] Throttle network to 3G/Edge
- [ ] App remains usable
- [ ] Loading indicators appear
- [ ] Images load eventually
- [ ] No crashes during slow loads
- [ ] Timeouts handled gracefully

**Background/Foreground:**
- [ ] Switch to another app
- [ ] Switch back to AttendUs
- [ ] App resumes correctly
- [ ] No data loss
- [ ] No crashes
- [ ] State preserved

**Interruptions:**
- [ ] Receive phone call during use
- [ ] App pauses properly
- [ ] Resume works after call
- [ ] Receive notification during use
- [ ] App doesn't crash

**Low Battery Mode:**
- [ ] Enable Low Battery Mode
- [ ] App still functions
- [ ] Features work (may be slower)
- [ ] No crashes

**Memory Warnings:**
- [ ] Open many large images
- [ ] App handles memory pressure
- [ ] Doesn't crash
- [ ] Images may reload

**Orientation Changes (if supported):**
- [ ] Rotate device
- [ ] Layout adjusts properly
- [ ] No UI glitches
- [ ] Data preserved

---

### Phase 5: Device Compatibility (15 minutes)

**Small Screen (iPhone SE, 13 mini):**
- [ ] All text readable
- [ ] Buttons not cut off
- [ ] Images scale properly
- [ ] Forms usable
- [ ] Keyboard doesn't cover inputs
- [ ] Bottom navigation visible

**Large Screen (iPhone Pro Max):**
- [ ] Layout uses space well
- [ ] No stretched images
- [ ] Text size appropriate
- [ ] UI elements properly spaced

**iPad (if supported):**
- [ ] App runs (even in compatibility mode)
- [ ] Layout looks reasonable
- [ ] All features work
- [ ] No crashes specific to iPad

**iOS 15 (Minimum Version):**
- [ ] App installs on iOS 15 device
- [ ] All features work
- [ ] No API compatibility issues
- [ ] No crashes

**Latest iOS (17/18):**
- [ ] App runs on latest iOS
- [ ] Uses latest iOS features appropriately
- [ ] No deprecated API warnings
- [ ] No compatibility issues

---

### Phase 6: Performance (10 minutes)

**Launch Time:**
- [ ] App launches in < 3 seconds (cold start)
- [ ] < 1 second warm start
- [ ] No unnecessary delays

**Navigation:**
- [ ] Screen transitions smooth (60fps)
- [ ] No lag when tapping buttons
- [ ] List scrolling smooth
- [ ] Map panning smooth

**Image Loading:**
- [ ] Images load progressively
- [ ] Thumbnails load first
- [ ] No jank during image load
- [ ] Caching works (images load faster second time)

**Search:**
- [ ] Search results appear quickly
- [ ] Typing is responsive
- [ ] Results update as you type

**Battery Usage:**
- [ ] Check battery usage in Settings → Battery
- [ ] Should not be excessive
- [ ] Background activity reasonable

**Data Usage:**
- [ ] Check in Settings → Cellular
- [ ] Not downloading unnecessarily
- [ ] Images cached
- [ ] Reasonable data consumption

---

### Phase 7: Visual & UX (10 minutes)

**Visual Quality:**
- [ ] No pixelated images
- [ ] Consistent styling
- [ ] Proper spacing
- [ ] Colors match design
- [ ] Fonts consistent
- [ ] Icons clear

**Navigation:**
- [ ] Bottom navigation works
- [ ] Back buttons work correctly
- [ ] Breadcrumb navigation clear
- [ ] Can reach all features
- [ ] No dead ends

**Loading States:**
- [ ] Loading indicators show when loading
- [ ] Skeleton screens where appropriate
- [ ] Progress indicators accurate
- [ ] User knows something is happening

**Empty States:**
- [ ] Proper message when no events
- [ ] Proper message when no tickets
- [ ] Empty states have helpful text
- [ ] Call to action provided

**Error Messages:**
- [ ] Error messages are clear
- [ ] Actionable instructions provided
- [ ] Not technical jargon
- [ ] Friendly tone

---

### Phase 8: Security & Privacy (5 minutes)

**Data Protection:**
- [ ] Login required for sensitive actions
- [ ] Session persists appropriately
- [ ] Session expires eventually
- [ ] Can't access other users' private data

**Payment Security:**
- [ ] Payment info not visible in app
- [ ] Stripe handles payment securely
- [ ] No credit card numbers stored

**Account Security:**
- [ ] Password requirements enforced
- [ ] Can change password
- [ ] Can't guess other users' passwords
- [ ] Account lockout after failed attempts (if implemented)

---

## 📊 Test Results Template

Create a document with your test results:

```markdown
# AttendUs iOS Testing Results

**Date:** [Date]
**Tester:** [Your Name]
**Device:** [iPhone Model]
**iOS Version:** [Version]
**App Version:** 1.0.0 (1)

## Test Summary
- Total Tests: [Number]
- Passed: [Number]
- Failed: [Number]
- Blocked: [Number]

## Critical Issues Found
1. [Issue description]
2. [Issue description]

## Non-Critical Issues Found
1. [Issue description]
2. [Issue description]

## Device-Specific Issues
- iPhone SE: [Issues]
- iPhone 15 Pro Max: [Issues]
- iOS 15: [Issues]

## Overall Assessment
[Ready for submission / Needs fixes]

## Detailed Results
[Copy checklist with results]
```

---

## 🐛 Found Issues?

### Prioritize Fixes:

**Critical (Must fix before submission):**
- App crashes
- Core features don't work
- Payment processing fails
- Can't create account/login
- Data loss issues

**High (Should fix before submission):**
- Permission requests unclear
- Poor error messages
- Performance issues
- UI glitches on certain devices

**Medium (Can fix in update):**
- Minor UI inconsistencies
- Feature enhancements
- Optimization opportunities

**Low (Nice to have):**
- Polish items
- Advanced features
- Edge case improvements

---

## 🎥 Record Your Testing

**Screenshots:**
- Take screenshots of all major screens
- Save screenshots of any issues found
- Use for App Store submission

**Video:**
- Consider screen recording your testing session
- Helpful for bug reports
- Can share with developers
- Useful reference

**Notes:**
- Document any unusual behavior
- Note device-specific issues
- Track steps to reproduce bugs

---

## ✅ Sign-Off Checklist

Before submitting to App Store:

- [ ] All critical tests passed
- [ ] No crashes encountered
- [ ] All permissions tested
- [ ] Core features working
- [ ] Tested on at least 2 devices
- [ ] Tested on minimum iOS version
- [ ] Tested on latest iOS version
- [ ] Performance acceptable
- [ ] Visual quality good
- [ ] Ready for Apple review

---

## 📱 TestFlight Beta Testing (Recommended)

**Why use TestFlight?**
- Test with real users before public release
- Catch issues you missed
- Get feedback
- Build confidence

**How to set up:**
1. Archive build in Xcode
2. Upload to App Store Connect
3. Add internal testers (up to 100)
4. Add external testers (up to 10,000) - requires Apple review
5. Testers install via TestFlight app
6. Collect feedback
7. Fix issues
8. Upload new build

**Timeline:**
- Internal testing: Immediate
- External testing: 1-2 day review by Apple
- Beta testing period: Recommend 1-2 weeks

---

## 🚀 Final Recommendation

**Minimum before submission:**
- Test on 2+ real devices
- Complete all critical tests
- Document results
- Fix all critical issues

**Ideal before submission:**
- TestFlight beta testing
- Multiple device types tested
- Multiple iOS versions tested
- External testers provided feedback
- All issues documented and triaged

**Remember:** Apple will test your app too. The more thorough your testing, the higher your chance of first-time approval.

Good luck with testing! 🎯

