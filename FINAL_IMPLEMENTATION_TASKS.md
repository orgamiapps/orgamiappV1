# Final Implementation Tasks - Complete Code

This document contains all remaining implementations needed to complete the two-tier subscription system.

## ✅ Task 1: Subscription Management Screen (COMPLETED)

The subscription management screen has been successfully updated with:
- Dynamic tier badge showing current tier (Basic/Premium)
- Usage stats card for Basic tier showing monthly event quota
- Tier-specific benefits display
- Progress bar for monthly event usage
- Warning when limit reached

## 🔧 Task 2: Account Screen Updates

Add the following code to `lib/screens/Home/account_screen.dart`:

### Step 1: Add imports at the top
```dart
import 'package:attendus/Services/subscription_service.dart';
import 'package:attendus/models/subscription_model.dart';
import 'package:attendus/screens/Premium/premium_upgrade_screen_v2.dart';
import 'package:attendus/screens/Premium/subscription_management_screen.dart';
```

### Step 2: Add tier display widget (add after user profile section)
```dart
// Add this method to the account screen state class
Widget _buildTierCard() {
  return Consumer<SubscriptionService>(
    builder: (context, subscriptionService, child) {
      final tier = subscriptionService.currentTier;
      final theme = Theme.of(context);

      // Free tier
      if (tier == SubscriptionTier.free) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.grey),
                    const SizedBox(width: 8),
                    const Text(
                      'Free Plan',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '5 lifetime events remaining',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PremiumUpgradeScreenV2(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Upgrade to Premium'),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // Basic or Premium tier
      final subscription = subscriptionService.currentSubscription;
      if (subscription == null) return const SizedBox.shrink();

      final isBasic = tier == SubscriptionTier.basic;
      final tierColor = isBasic ? Colors.blue : theme.colorScheme.primary;

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                tierColor.withValues(alpha: 0.1),
                tierColor.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isBasic ? Icons.star : Icons.workspace_premium,
                          color: tierColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${tier.displayName} Plan',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: tierColor,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: tierColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'ACTIVE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isBasic) ...[
                  // Usage stats for Basic
                  Text(
                    '${subscription.remainingEventsThisMonth ?? 0} of 5 events remaining this month',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (subscription.eventsCreatedThisMonth / 5).clamp(0.0, 1.0),
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(tierColor),
                  ),
                ] else ...[
                  // Premium unlimited
                  const Row(
                    children: [
                      Icon(Icons.all_inclusive, size: 20, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        'Unlimited events',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const SubscriptionManagementScreen(),
                            ),
                          );
                        },
                        child: const Text('Manage Subscription'),
                      ),
                    ),
                    if (isBasic) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const PremiumUpgradeScreenV2(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Upgrade'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
```

### Step 3: Add the widget to the UI
Find the account screen's build method and add `_buildTierCard()` in an appropriate location (typically near the top after the profile header).

---

## 🔒 Task 3: Firestore Security Rules

Update `firestore.rules` with the following:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper Functions
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function isUser(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }
    
    function getUserSubscription() {
      return get(/databases/$(database)/documents/subscriptions/$(request.auth.uid));
    }
    
    function hasActiveSubscription() {
      let sub = getUserSubscription();
      return sub != null && 
             sub.data.status == 'active' && 
             request.time < sub.data.currentPeriodEnd;
    }
    
    function hasPremiumTier() {
      let sub = getUserSubscription();
      return hasActiveSubscription() && sub.data.tier == 'premium';
    }
    
    function hasBasicTier() {
      let sub = getUserSubscription();
      return hasActiveSubscription() && sub.data.tier == 'basic';
    }
    
    function isEventOwner(eventId) {
      let event = get(/databases/$(database)/documents/Events/$(eventId));
      return event != null && event.data.customerUid == request.auth.uid;
    }
    
    function isOrgAdmin(orgId) {
      let member = get(/databases/$(database)/documents/Organizations/$(orgId)/Members/$(request.auth.uid));
      return member != null && member.data.role == 'Admin';
    }
    
    // Subscriptions Collection
    match /subscriptions/{userId} {
      allow read: if isUser(userId);
      allow write: if isUser(userId);
    }
    
    // Customers Collection
    match /Customers/{userId} {
      allow read: if isAuthenticated();
      allow write: if isUser(userId);
    }
    
    // Events Collection
    match /Events/{eventId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update, delete: if isAuthenticated() && isEventOwner(eventId);
      
      // Nested collections
      match /{document=**} {
        allow read: if isAuthenticated();
        allow write: if isAuthenticated() && isEventOwner(eventId);
      }
    }
    
    // Event Analytics - Premium Only
    match /eventAnalytics/{analyticsId} {
      allow read: if isAuthenticated() && hasPremiumTier();
      allow write: if isAuthenticated() && hasPremiumTier();
    }
    
    // Organizations (Groups) - Premium Only for Creation
    match /Organizations/{orgId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() && hasPremiumTier();
      allow update, delete: if isAuthenticated() && isOrgAdmin(orgId);
      
      // Organization Members
      match /Members/{memberId} {
        allow read: if isAuthenticated();
        allow write: if isAuthenticated() && isOrgAdmin(orgId);
      }
      
      // Nested collections
      match /{document=**} {
        allow read: if isAuthenticated();
        allow write: if isAuthenticated() && isOrgAdmin(orgId);
      }
    }
    
    // Organization Names (for uniqueness check)
    match /OrganizationNames/{name} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() && hasPremiumTier();
    }
    
    // Conversations (Messaging)
    match /Conversations/{conversationId} {
      allow read, write: if isAuthenticated();
      
      match /Messages/{messageId} {
        allow read, write: if isAuthenticated();
      }
    }
    
    // Attendance Records
    match /Attendance/{attendanceId} {
      allow read: if isAuthenticated();
      allow write: if isAuthenticated();
    }
    
    // Default deny all other collections
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

---

## ☁️ Task 4: Cloud Functions

Create/update `functions/index.js`:

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin (only once)
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/**
 * Reset Monthly Event Limits for Basic Tier Users
 * Runs on the 1st day of each month at midnight UTC
 */
exports.resetMonthlyEventLimits = functions.pubsub
  .schedule('0 0 1 * *')
  .timeZone('UTC')
  .onRun(async (context) => {
    console.log('Starting monthly event limit reset...');
    
    try {
      const now = admin.firestore.Timestamp.now();
      
      // Get all Basic tier subscriptions
      const subscriptionsSnapshot = await db
        .collection('subscriptions')
        .where('tier', '==', 'basic')
        .where('status', '==', 'active')
        .get();
      
      if (subscriptionsSnapshot.empty) {
        console.log('No active Basic tier subscriptions found');
        return null;
      }
      
      const batch = db.batch();
      let resetCount = 0;
      
      subscriptionsSnapshot.forEach(doc => {
        batch.update(doc.ref, {
          eventsCreatedThisMonth: 0,
          currentMonthStart: now,
          updatedAt: now,
        });
        resetCount++;
      });
      
      await batch.commit();
      
      console.log(`✅ Successfully reset monthly event limits for ${resetCount} Basic tier users`);
      return { success: true, count: resetCount };
    } catch (error) {
      console.error('❌ Error resetting monthly limits:', error);
      throw error;
    }
  });

/**
 * Apply Scheduled Plan Changes
 * Runs every 6 hours to check for and apply scheduled tier changes
 */
exports.applyScheduledPlanChanges = functions.pubsub
  .schedule('0 */6 * * *')
  .timeZone('UTC')
  .onRun(async (context) => {
    console.log('Checking for scheduled plan changes...');
    
    try {
      const now = new Date();
      
      // Get all subscriptions with scheduled plan changes
      const subscriptionsSnapshot = await db
        .collection('subscriptions')
        .where('scheduledPlanId', '!=', null)
        .get();
      
      if (subscriptionsSnapshot.empty) {
        console.log('No scheduled plan changes found');
        return null;
      }
      
      let appliedCount = 0;
      const batch = db.batch();
      
      for (const doc of subscriptionsSnapshot.docs) {
        const data = doc.data();
        const scheduledStartDate = data.scheduledPlanStartDate?.toDate();
        
        // Check if scheduled date has passed
        if (scheduledStartDate && now >= scheduledStartDate) {
          const scheduledPlanId = data.scheduledPlanId;
          
          // Determine new tier and pricing
          const isBasic = scheduledPlanId.includes('basic');
          const tier = isBasic ? 'basic' : 'premium';
          
          // Price determination
          const BASIC_PRICES = [500, 2500, 4000];
          const PREMIUM_PRICES = [2000, 10000, 17500];
          const prices = isBasic ? BASIC_PRICES : PREMIUM_PRICES;
          
          let priceAmount, billingDays, interval;
          
          if (scheduledPlanId.includes('6month')) {
            priceAmount = prices[1];
            billingDays = 180;
            interval = '6months';
          } else if (scheduledPlanId.includes('yearly')) {
            priceAmount = prices[2];
            billingDays = 365;
            interval = 'year';
          } else {
            priceAmount = prices[0];
            billingDays = 30;
            interval = 'month';
          }
          
          // Update subscription
          batch.update(doc.ref, {
            planId: scheduledPlanId,
            tier: tier,
            priceAmount: priceAmount,
            interval: interval,
            currentPeriodStart: admin.firestore.Timestamp.fromDate(scheduledStartDate),
            currentPeriodEnd: admin.firestore.Timestamp.fromDate(
              new Date(scheduledStartDate.getTime() + billingDays * 24 * 60 * 60 * 1000)
            ),
            scheduledPlanId: null,
            scheduledPlanStartDate: null,
            updatedAt: admin.firestore.Timestamp.now(),
          });
          
          appliedCount++;
          console.log(`Applied scheduled plan change for user: ${doc.id}`);
        }
      }
      
      if (appliedCount > 0) {
        await batch.commit();
      }
      
      console.log(`✅ Applied ${appliedCount} scheduled plan changes`);
      return { success: true, count: appliedCount };
    } catch (error) {
      console.error('❌ Error applying scheduled plan changes:', error);
      throw error;
    }
  });

/**
 * Send Monthly Usage Reminder to Basic Users
 * Runs on the 25th of each month to remind users about upcoming reset
 */
exports.sendMonthlyUsageReminder = functions.pubsub
  .schedule('0 10 25 * *') // 10 AM UTC on the 25th
  .timeZone('UTC')
  .onRun(async (context) => {
    console.log('Sending monthly usage reminders...');
    
    try {
      // Get Basic tier users who have used 4+ events
      const subscriptionsSnapshot = await db
        .collection('subscriptions')
        .where('tier', '==', 'basic')
        .where('status', '==', 'active')
        .where('eventsCreatedThisMonth', '>=', 4)
        .get();
      
      if (subscriptionsSnapshot.empty) {
        console.log('No users need reminder');
        return null;
      }
      
      let reminderCount = 0;
      
      // Create notifications for users
      for (const doc of subscriptionsSnapshot.docs) {
        const userId = doc.data().userId;
        const eventsUsed = doc.data().eventsCreatedThisMonth;
        const remaining = 5 - eventsUsed;
        
        // Create notification in Firestore
        await db.collection('notifications').add({
          userId: userId,
          title: 'Monthly Event Limit Reminder',
          message: `You have ${remaining} event${remaining !== 1 ? 's' : ''} remaining this month. Your limit resets on the 1st.`,
          type: 'usage_reminder',
          read: false,
          createdAt: admin.firestore.Timestamp.now(),
        });
        
        reminderCount++;
      }
      
      console.log(`✅ Sent reminders to ${reminderCount} users`);
      return { success: true, count: reminderCount };
    } catch (error) {
      console.error('❌ Error sending reminders:', error);
      throw error;
    }
  });
```

### Deploy Cloud Functions

```bash
cd functions
npm install firebase-functions firebase-admin
cd ..
firebase deploy --only functions
```

---

## 🧪 Task 5: Testing & Quality Assurance

### Testing Checklist

#### Subscription Tier Tests
- [ ] **Free Tier**
  - [ ] Can browse and RSVP to events
  - [ ] Can create up to 5 lifetime events
  - [ ] Blocked after 5 events with upgrade prompt
  - [ ] Cannot access analytics
  - [ ] Cannot create groups

- [ ] **Basic Tier ($5/month)**
  - [ ] Can create 5 events per month
  - [ ] Event counter resets on 1st of month
  - [ ] Blocked after 5 events with "Monthly limit reached" message
  - [ ] Shows correct usage stats in account/management screens
  - [ ] Cannot access analytics (shows Premium upgrade prompt)
  - [ ] Cannot create groups (shows Premium upgrade prompt)

- [ ] **Premium Tier ($20/month)**
  - [ ] Can create unlimited events
  - [ ] Can access all analytics screens
  - [ ] Can create unlimited groups
  - [ ] Shows "Unlimited" badge in UI

#### UI/UX Tests
- [ ] **PremiumUpgradeScreenV2**
  - [ ] Side-by-side tier comparison displays correctly
  - [ ] Pricing toggle works (Monthly/6-month/Annual)
  - [ ] Prices update correctly on toggle
  - [ ] "Most Popular" badge shows on Premium
  - [ ] Plan selection creates correct subscription

- [ ] **Subscription Management Screen**
  - [ ] Tier badge shows correct tier and color
  - [ ] Usage stats display for Basic tier
  - [ ] Benefits list matches current tier
  - [ ] Progress bar updates correctly

- [ ] **Account Screen**
  - [ ] Tier card displays correct information
  - [ ] Usage stats accurate for each tier
  - [ ] Upgrade/Manage buttons work correctly

#### Feature Gating Tests
- [ ] **Analytics**
  - [ ] EventAnalyticsScreen blocks non-Premium users
  - [ ] Analytics buttons disabled/hidden for non-Premium
  - [ ] Upgrade prompts appear when clicked
  
- [ ] **Group Creation**
  - [ ] CreateGroupScreen blocks non-Premium users
  - [ ] Shows Premium upgrade dialog
  
- [ ] **Event Creation**
  - [ ] Free tier: 5 lifetime limit enforced
  - [ ] Basic tier: 5 monthly limit enforced
  - [ ] Premium tier: no limits

#### Subscription Flow Tests
- [ ] **Upgrades**
  - [ ] Free → Basic: Creates Basic subscription
  - [ ] Free → Premium: Creates Premium subscription
  - [ ] Basic → Premium: Upgrades immediately
  
- [ ] **Downgrades**
  - [ ] Premium → Basic: Schedules for period end
  - [ ] Shows "Scheduled plan" in management screen
  
- [ ] **Migration**
  - [ ] Migration dialog shows for existing subscribers
  - [ ] Tier selection works correctly
  - [ ] Migration completes and doesn't show again

#### Data & Security Tests
- [ ] **Firestore Rules**
  - [ ] Non-Premium users blocked from analytics collections
  - [ ] Non-Premium users blocked from creating groups
  - [ ] Users can only access their own subscriptions
  
- [ ] **Cloud Functions**
  - [ ] Monthly reset function works (test manually or wait for 1st)
  - [ ] Scheduled plan changes apply correctly

### Performance Tests
- [ ] App launch time acceptable
- [ ] Subscription checks don't cause lag
- [ ] UI animations smooth (60fps)
- [ ] No memory leaks in subscription service

### Edge Cases
- [ ] User cancels subscription mid-period
- [ ] User reactivates cancelled subscription
- [ ] Trial subscription expires
- [ ] Network errors handled gracefully
- [ ] Concurrent event creation near limit

---

## 📊 Monitoring & Analytics

### Metrics to Track
1. **Conversion Rates**
   - Free → Basic conversion
   - Free → Premium conversion
   - Basic → Premium upgrades

2. **Usage Patterns**
   - Average events created per tier
   - Feature adoption by tier
   - Monthly churn rate

3. **Technical Metrics**
   - Subscription API response time
   - Feature gate check performance
   - Error rates by tier

### Logging
Ensure proper logging for:
- Subscription creation/updates
- Tier changes
- Feature access attempts
- Limit enforcement

---

## 🚀 Deployment Checklist

### Pre-Deployment
- [ ] All lint errors resolved
- [ ] All tests passing
- [ ] Code review completed
- [ ] Documentation updated

### Deployment Steps
1. [ ] Deploy Firestore security rules
   ```bash
   firebase deploy --only firestore:rules
   ```

2. [ ] Deploy Cloud Functions
   ```bash
   firebase deploy --only functions
   ```

3. [ ] Build and test app
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --release  # Android
   flutter build ios --release  # iOS
   ```

4. [ ] Deploy app to stores

### Post-Deployment
- [ ] Monitor error logs
- [ ] Track conversion metrics
- [ ] Collect user feedback
- [ ] Plan next iteration

---

## 📝 Support Documentation

### User FAQs

**Q: What happens to my events when I downgrade?**
A: Your existing events remain active. You'll be limited to 5 events per month on Basic tier.

**Q: When does my monthly limit reset?**
A: Basic tier limits reset on the 1st of each month.

**Q: Can I upgrade mid-period?**
A: Yes! Upgrades take effect immediately. You'll be charged the difference.

**Q: What happens if I cancel?**
A: You'll keep access until the end of your billing period, then revert to Free tier.

---

## 🎯 Success Metrics

### Week 1 Post-Launch
- [ ] Zero critical bugs
- [ ] < 1% error rate
- [ ] Positive user feedback
- [ ] Successful payments processing

### Month 1 Post-Launch
- [ ] 10%+ Free → Paid conversion
- [ ] 5%+ Basic → Premium upgrades
- [ ] < 2% churn rate
- [ ] Feature adoption tracking

---

**Implementation Complete!** 🎉

All 5 remaining tasks are now documented with complete code implementations. The system is production-ready pending final testing and deployment.

