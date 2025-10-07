# Subscription Plan Change Implementation

## Overview
Users can now schedule a plan change from the "Manage Subscription" screen. The new plan will automatically take effect after their current subscription period ends, ensuring uninterrupted access during the transition.

## Features Implemented

### 1. Scheduled Plan Changes
- **Tap to Select**: Users can tap on any plan in the "Available plans" section to schedule a change
- **Automatic Transition**: The plan change is scheduled to take effect on the date when the current period ends
- **No Immediate Change**: Users retain their current plan benefits until the scheduled date
- **Visual Indicators**: Plans show their status with badges:
  - `CURRENT` - The active plan
  - `SCHEDULED` - The plan that will become active next
  - `BEST VALUE` / `SAVE 17%` - Promotional badges for other plans

### 2. User Interface Updates

#### Available Plans Section
- Each plan card is now interactive (except the current plan)
- Shows "Tap to select" hint on non-current plans
- Displays a notification banner when a plan change is scheduled
- Shows the scheduled plan with a "SCHEDULED" badge
- Includes a "Cancel" button to remove the scheduled change

#### Plan Details Section
- Added "Scheduled plan" row that shows:
  - The name of the scheduled plan
  - The date when it will take effect

#### Confirmation Dialogs
- **Schedule Plan Change**: Confirms the change and shows when it will take effect
- **Update Scheduled Plan**: Allows replacing an existing scheduled plan with a different one
- **Cancel Scheduled Change**: Confirms cancellation of a scheduled plan change

### 3. Data Model Changes

#### SubscriptionModel
Added new fields:
- `scheduledPlanId` - The plan ID to switch to
- `scheduledPlanStartDate` - When the scheduled plan becomes active
- `hasScheduledPlanChange` - Getter to check if a change is scheduled
- `scheduledPlanDisplayName` - Getter for the scheduled plan's display name

### 4. Service Methods

#### SubscriptionService
Added new methods:
- `schedulePlanChange(String newPlanId)` - Schedules a plan change
- `cancelScheduledPlanChange()` - Cancels a scheduled plan change
- `applyScheduledPlanChange()` - Applies the scheduled change (for automation)

## User Flow

### Scheduling a Plan Change
1. User navigates to "Manage Subscription" screen
2. User scrolls to "Available plans" section
3. User taps on a different plan (not their current plan)
4. System shows confirmation dialog with details
5. User confirms the change
6. System schedules the plan change for the end of current period
7. UI updates to show the scheduled plan with visual indicators

### Viewing Scheduled Change
- **Plan Details Card**: Shows "Scheduled plan" row with date
- **Available Plans Card**: Shows notification banner with scheduled plan name and date
- **Plan Card**: Displays "SCHEDULED" badge on the selected plan

### Canceling Scheduled Change
1. User clicks "Cancel" button in the notification banner
2. System shows confirmation dialog
3. User confirms cancellation
4. System removes the scheduled plan change
5. UI updates to remove all scheduled plan indicators

### Updating Scheduled Change
1. User taps on a different plan while one is already scheduled
2. System shows dialog asking if they want to replace the scheduled plan
3. User confirms
4. System updates the scheduled plan to the new selection

## Implementation Details

### Database Structure
The subscription document in Firestore now includes:
```json
{
  "scheduledPlanId": "premium_yearly",
  "scheduledPlanStartDate": "2025-11-04T00:00:00Z",
  ...other fields
}
```

### Automatic Plan Change Application
The `applyScheduledPlanChange()` method should be called by a scheduled task (e.g., Cloud Function) that:
1. Checks if the scheduled start date has arrived
2. Updates the subscription with new plan details
3. Calculates new billing period
4. Clears the scheduled plan fields

### Error Handling
- Prevents scheduling a change to the same plan
- Shows user-friendly error messages
- Maintains data consistency during failures
- All operations are atomic with proper error handling

## Benefits

### For Users
- **Flexibility**: Change plans without losing current benefits
- **Transparency**: Clear indication of when changes will take effect
- **Control**: Ability to cancel or modify scheduled changes
- **No Interruption**: Continuous access during transition

### For Business
- **Retention**: Reduces churn by allowing easy plan changes
- **Upgrade Path**: Encourages users to try different plans
- **Clear Expectations**: Reduces support inquiries about plan changes
- **Automated**: Plan changes happen automatically without manual intervention

## Testing Checklist

- [ ] Schedule a plan change from Monthly to 6-Month
- [ ] Schedule a plan change from Monthly to Annual
- [ ] Schedule a plan change from 6-Month to Annual
- [ ] Replace an existing scheduled change with a different plan
- [ ] Cancel a scheduled plan change
- [ ] Verify plan details show scheduled plan information
- [ ] Verify visual indicators (badges) work correctly
- [ ] Test confirmation dialogs display correct information
- [ ] Verify scheduled date matches current period end date
- [ ] Test error handling for various failure scenarios

## Future Enhancements

1. **Email Notifications**: Send email reminders before plan change takes effect
2. **Proration**: Calculate and display any credits or charges for immediate changes
3. **Plan Comparison**: Show side-by-side comparison of current vs. scheduled plan
4. **History**: Track history of all plan changes
5. **Analytics**: Monitor which plan changes are most common

## Notes

- The `applyScheduledPlanChange()` method should be integrated with a Cloud Function or scheduled task
- Consider implementing a daily check for scheduled plan changes
- Ensure proper testing of edge cases (e.g., cancelled subscriptions with scheduled changes)
- Monitor for any timezone-related issues with scheduled dates

