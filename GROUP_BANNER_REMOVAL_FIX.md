# Group Banner Image Removal Fix

## Problem

When an admin edited a group from the admin settings and removed the banner image (or logo), the changes were not being saved properly. After clicking "Save Changes", the banner would still appear on the group profile because the Firestore database was never updated to remove the image URL.

## Root Cause

The issue was in `/lib/screens/Groups/edit_group_details_screen.dart` in the `_saveChanges()` method:

1. When the user clicked the "Remove" button on the banner, the code set:
   - `_bannerFile = null`
   - `_currentBannerUrl = null`

2. In the `_saveChanges()` method, the code only added image URLs to the update data **if they were not null**:
   ```dart
   // Old code (buggy)
   if (bannerUrl != null) {
     updateData['bannerUrl'] = bannerUrl;
   }
   ```

3. This meant when the banner was removed (set to null), the `bannerUrl` field was never added to `updateData`, so Firestore was never told to remove the old banner URL.

## Solution

Modified the `_saveChanges()` method to explicitly handle image removal using `FieldValue.delete()`:

```dart
// New code (fixed)
if (bannerUrl != null) {
  updateData['bannerUrl'] = bannerUrl;
} else if (_currentBannerUrl == null && _bannerFile == null) {
  // Banner was explicitly removed
  updateData['bannerUrl'] = FieldValue.delete();
}
```

The same fix was applied to the logo handling as well.

## How It Works

Now when an admin removes a banner or logo:

1. The user clicks the "Remove" button (X icon)
2. Both `_bannerFile` and `_currentBannerUrl` are set to null
3. When saving, the code detects that both are null
4. It adds `FieldValue.delete()` to the update data for that field
5. Firestore removes the field from the document
6. The group profile correctly shows no banner

## Testing

To test this fix:

1. **Open a group** where you're an admin
2. **Navigate to** Admin Settings → Edit Group Details
3. **Remove the banner image** by clicking the X button
4. **Click "Save Changes"**
5. **Go back to the group profile** - the banner should now be gone
6. **Repeat for the logo** to verify it works for both images

## Files Changed

- `/lib/screens/Groups/edit_group_details_screen.dart` - Fixed the `_saveChanges()` method to properly handle image removal

## Impact

This fix ensures that when admins remove group images (banner or logo), the changes are properly persisted to Firestore and reflected immediately in the app.

