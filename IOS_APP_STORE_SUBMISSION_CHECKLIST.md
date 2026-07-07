# iOS App Store Submission Checklist

## ✅ Completed Technical Requirements

### 1. Privacy Manifest ✓
- [x] Created `ios/Runner/PrivacyInfo.xcprivacy`
- [x] Declared Required Reason APIs:
  - UserDefaults (CA92.1)
  - File Timestamp (C617.1, 0A2A.1)
  - System Boot Time (35F9.1)
  - Disk Space (E174.1)
- [x] Declared all data collection types
- [x] Set tracking to false

### 2. Info.plist Improvements ✓
- [x] Enhanced NSCameraUsageDescription
- [x] Enhanced NSLocationWhenInUseUsageDescription
- [x] Enhanced NSPhotoLibraryUsageDescription
- [x] Enhanced NSPhotoLibraryAddUsageDescription
- [x] Enhanced NFCReaderUsageDescription
- [x] Added ITSAppUsesNonExemptEncryption key (set to false)

### 3. Technical Fixes ✓
- [x] Removed broken OnnxNlpPlugin reference from AppDelegate.swift
- [x] iOS deployment target set to 15.0
- [x] Fixed app icon Contents.json configuration
- [x] Removed alpha channels from app icons

### 4. Entitlements Configuration ✓
- [x] Push notifications (aps-environment)
- [x] Sign in with Apple
- [x] NFC Tag Reading (NDEF and TAG formats)

### 5. Authentication UI ✓
- [x] Sign in with Apple button equally prominent as Google
- [x] Both buttons same size and styling
- [x] Proper button ordering (conditionally rendered)

---

## ⚠️ CRITICAL ISSUES TO RESOLVE

### Payment Compliance - ACTION REQUIRED
See `IOS_APP_STORE_CRITICAL_COMPLIANCE_ISSUE.md` for full details.

**Issue:** Premium subscription uses Stripe for app features (VIOLATION)

**Required Action:** Choose one:
1. Switch to Apple In-App Purchase (2-3 days work)
2. Make premium features free temporarily (2 hours work) ← RECOMMENDED FOR FAST APPROVAL
3. Remove premium features entirely

**Status:** Must be resolved before submission

---

## 📋 Pre-Submission Tasks (You Must Complete)

### A. Xcode Configuration (5-10 minutes)
Open your project in Xcode and verify:

1. **Deployment Target**
   - Open `Runner.xcworkspace` (not .xcodeproj)
   - Select Runner target → General
   - Verify "iOS Deployment Target" is set to 15.0
   - Verify same for all pod dependencies

2. **Capabilities**
   - Select Runner target → Signing & Capabilities
   - Verify these capabilities are enabled:
     - ✓ Push Notifications
     - ✓ Sign in with Apple
     - ✓ Near Field Communication Tag Reading
   - For NFC: Click the "+" to add capability if not present

3. **Bundle Identifier**
   - Verify your Bundle Identifier matches App Store Connect
   - Format: com.yourcompany.attendus (or whatever you chose)

4. **Signing**
   - Select your Team
   - Choose "Automatically manage signing" for development
   - For distribution: Create App Store provisioning profile

### B. App Store Connect Setup (30-60 minutes)

1. **Create App Record**
   - Log in to https://appstoreconnect.apple.com
   - Click "My Apps" → "+" → "New App"
   - Platform: iOS
   - Name: AttendUs (or your preferred name)
   - Primary Language: English (or your choice)
   - Bundle ID: Select the one you registered
   - SKU: Create unique identifier (e.g., attendus-app-001)

2. **App Information**
   - Category: Primary = Social Networking (or Lifestyle)
   - Content Rights: Declare if you have necessary rights
   - Age Rating: Complete questionnaire honestly

3. **Pricing and Availability**
   - Price: Free (since you have event tickets as separate purchases)
   - Availability: Choose countries
   - Pre-orders: Not needed for first release

### C. Privacy Policy & Support URL (REQUIRED)

You **MUST** create these before submission:

**Privacy Policy URL** (REQUIRED)
- Must be publicly accessible URL
- Must describe all data collection shown in Privacy Manifest
- Suggested content:
  - What data you collect (name, email, location, photos, etc.)
  - How you use it (event management, recommendations, etc.)
  - How you protect it (Firebase security, encryption)
  - User rights (access, deletion, etc.)
  - Contact information

**Support URL** (REQUIRED)
- Where users can get help
- Can be simple webpage with:
  - Contact email
  - FAQ
  - How to delete account
  - Troubleshooting tips

**Options:**
1. Create pages on your website
2. Use privacy policy generators (e.g., TermsFeed, iubenda)
3. Create simple GitHub pages

### D. App Screenshots (REQUIRED)

Apple requires screenshots for at least one device size:

**Required Sizes (choose one set minimum):**
- 6.7" Display (iPhone 15 Pro Max): 1290 x 2796 pixels
- 6.5" Display (iPhone 11 Pro Max): 1242 x 2688 pixels
- 5.5" Display (iPhone 8 Plus): 1242 x 2208 pixels

**How to capture:**
1. Run app in iOS Simulator
2. Navigate to key screens:
   - Login/Home screen
   - Event list
   - Event details
   - Create event
   - User profile
   - (Optional) Search results
3. Use Simulator → File → New Screen Shot
4. Save 3-6 screenshots showing app functionality

**What to show:**
- Main features
- Beautiful, clean UI
- Actual content (not empty states)
- No personal/test data visible

### E. App Description & Metadata

**App Name** (30 characters max)
- AttendUs - Event Management
- AttendUs: Events & Tickets
- AttendUs

**Subtitle** (30 characters max, optional)
- "Manage Events Effortlessly"
- "Events Made Simple"

**Description** (4000 characters max)
Example:
```
AttendUs is your all-in-one event management and attendance platform. Whether you're hosting events, attending gatherings, or discovering activities near you, AttendUs makes it simple and seamless.

KEY FEATURES:

📅 Event Management
• Create and manage events effortlessly
• Track attendees and RSVPs
• Generate QR codes for easy check-in
• Manage tickets and sales

🎫 Smart Ticketing
• Purchase event tickets securely
• Digital QR code tickets
• NFC-enabled badge activation
• Skip-the-line upgrades available

🔍 Event Discovery
• Find nearby events based on your location
• Personalized event recommendations
• Search by category, date, and interest
• Interactive map view

👥 Group Organization
• Create and join groups
• Group-specific events and announcements
• Manage group members
• Private or public groups

🔔 Smart Notifications
• Real-time event updates
• Reminder notifications
• Attendance confirmations
• Group announcements

📊 Insights & Analytics
• Track event attendance
• View attendance statistics
• Download attendance reports
• Export data to Excel

🔐 Secure & Private
• Sign in with Apple or Google
• Secure payment processing
• Privacy-focused design
• Your data stays safe

Perfect for:
• Event organizers and coordinators
• Community groups and clubs
• Corporate events and meetings
• Social gatherings and parties
• Conferences and workshops

Download AttendUs today and transform how you manage and attend events!
```

**Keywords** (100 characters max)
- event,ticket,rsvp,attendance,management,qr,nfc,social,group,calendar

**Promotional Text** (170 characters, optional)
- "New: NFC badge activation for lightning-fast event check-ins!"

### F. App Review Information

**Contact Information**
- First Name, Last Name
- Phone Number
- Email Address

**Demo Account** (REQUIRED if login required)
- Create a test account
- Provide username/email and password
- Ensure account has sample data:
  - Some events created
  - Some tickets purchased
  - Group membership
  - Complete profile

**Notes for Reviewer**
Example:
```
Thank you for reviewing AttendUs!

DEMO ACCOUNT:
Email: demo@attendus.com
Password: Demo123456!

The demo account has:
- Sample events created
- Test group memberships
- Example tickets

TESTING NOTES:
1. Event tickets use Stripe (allowed for physical event access per 3.1.5(f))
2. NFC features require iPhone with NFC capability
3. Location permission is used for nearby event discovery
4. Camera is used for QR code scanning at events

If you have any questions, please contact us at the provided email.
```

### G. Export Compliance

When submitting, you'll be asked about encryption:

**Question:** "Is your app designed to use cryptography or does it contain or incorporate cryptography?"

**Answer:** NO

**Reason:** You set `ITSAppUsesNonExemptEncryption` to `false`. Your app only uses standard iOS HTTPS which is exempt.

---

## 🧪 Testing Checklist

Before submitting, test thoroughly:

### Basic Functionality
- [ ] App launches without crashes
- [ ] Login with Apple works
- [ ] Login with Google works
- [ ] Login with email/password works
- [ ] Can create an account
- [ ] Can reset password

### Core Features
- [ ] Can view events
- [ ] Can search for events
- [ ] Map shows events correctly
- [ ] Can create an event (if premium issue resolved)
- [ ] Can view event details
- [ ] Can purchase tickets
- [ ] Can view purchased tickets
- [ ] QR codes display correctly

### Permissions
- [ ] Camera permission request works
- [ ] Location permission request works
- [ ] Photo library permission request works
- [ ] Notifications permission request works
- [ ] NFC permission (if prompted)

### Groups
- [ ] Can create a group
- [ ] Can join a group
- [ ] Can view group events
- [ ] Group feed loads correctly

### Profile
- [ ] Profile displays correctly
- [ ] Can edit profile
- [ ] Can upload profile picture
- [ ] Can view my events
- [ ] Can view my tickets

### Edge Cases
- [ ] App works in airplane mode (offline features)
- [ ] App handles no internet gracefully
- [ ] App handles failed API calls
- [ ] No crashes when backgrounded
- [ ] No crashes during orientation changes (if supported)

### Device Testing (IMPORTANT)
- [ ] Test on real iOS 15 device (minimum version)
- [ ] Test on iOS 17/18 device (latest)
- [ ] Test on different screen sizes (small & large)
- [ ] Test on iPad (if supporting iPad)

---

## 📦 Building for Release

### 1. Update Version Number
Edit `pubspec.yaml`:
```yaml
version: 1.0.0+1
```
- First number (1.0.0) = Version shown to users
- Second number (+1) = Build number (increment for each upload)

### 2. Build Archive

```bash
# Make sure dependencies are up to date
flutter pub get
cd ios && pod install && cd ..

# Build iOS release
flutter build ios --release

# Then in Xcode:
# 1. Open Runner.xcworkspace
# 2. Select "Any iOS Device" as destination
# 3. Product → Archive
# 4. When complete, click "Distribute App"
# 5. Choose "App Store Connect"
# 6. Follow the wizard
```

### 3. Upload to App Store Connect

After archiving in Xcode:
1. Click "Distribute App"
2. Select "App Store Connect"
3. Select "Upload"
4. Choose your distribution certificate and provisioning profile
5. Review and upload
6. Wait for processing (15-30 minutes)

### 4. Submit for Review

Once upload is processed:
1. Go to App Store Connect
2. Select your app → version
3. Complete all required fields
4. Click "Add for Review" then "Submit for Review"

---

## ⏱️ Review Timeline

- **Processing:** 15-30 minutes after upload
- **In Review:** Usually 1-3 days
- **First Review:** Can take up to 7 days
- **Rejection Response:** Usually reviewed within 24-48 hours

---

## 🚨 Common Rejection Reasons & How to Avoid

### 1. Incomplete Information
- ✓ Provide demo account with data
- ✓ Fill all metadata fields
- ✓ Include clear app description

### 2. App Crashes
- ✓ Test thoroughly on real devices
- ✓ Test all permission flows
- ✓ Handle all error cases

### 3. Privacy Issues
- ✓ Privacy Policy URL working
- ✓ Usage descriptions clear
- ✓ Privacy Manifest included (done ✓)

### 4. Payment Issues
- ✓ Resolve Stripe vs IAP issue (see critical issue doc)
- ✓ Clear pricing information
- ✓ Restore purchases option if applicable

### 5. Design Issues
- ✓ No placeholder content
- ✓ Professional screenshots
- ✓ Consistent branding

---

## 📞 If You Get Rejected

1. **Don't Panic** - Most apps get rejected first time
2. **Read Carefully** - Apple provides specific reasons
3. **Fix Issues** - Address each point mentioned
4. **Respond Quickly** - You can resubmit immediately
5. **Appeal if Needed** - Use Resolution Center to explain

---

## ✅ Summary of What's Been Done

**Files Created/Modified:**
- ✅ `ios/Runner/PrivacyInfo.xcprivacy` (NEW)
- ✅ `ios/Runner/Info.plist` (UPDATED)
- ✅ `ios/Runner/AppDelegate.swift` (FIXED)
- ✅ `ios/Runner/Runner.entitlements` (UPDATED)
- ✅ `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` (FIXED)
- ✅ App icons (FIXED - removed alpha channels)

**What You Still Need to Do:**
1. ⚠️ Resolve premium subscription payment issue (CRITICAL)
2. 📝 Create Privacy Policy URL
3. 📝 Create Support URL
4. 📸 Capture app screenshots
5. ⚙️ Configure in Xcode (5 min)
6. 📱 Test on real devices
7. 🚀 Create App Store Connect record
8. 📋 Fill in app metadata
9. 📦 Build and upload
10. ✅ Submit for review

---

## Need Help?

If you encounter issues:
1. Check Apple's App Store Review Guidelines
2. Review App Store Connect help documentation
3. Test thoroughly before submitting
4. Provide detailed notes for reviewers

**Good luck with your submission! 🚀**

