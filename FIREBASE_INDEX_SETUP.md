# Firebase Index Setup for My Profile Events

If you're experiencing issues with events not showing on the My Profile screen, you may need to create a composite index in Firebase Firestore.

## Required Index

Create a composite index for the Events collection with the following configuration:

### Collection ID
`Events`

### Fields to Index
1. `customerUid` - Ascending
2. `eventGenerateTime` - Descending

## How to Create the Index

### Option 1: Via Firebase Console
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Navigate to Firestore Database
4. Click on "Indexes" tab
5. Click "Create Index"
6. Enter the following:
   - Collection ID: `Events`
   - Add field: `customerUid` (Ascending)
   - Add field: `eventGenerateTime` (Descending)
7. Click "Create"

### Option 2: Via Error Link
If you see an error in the console logs like:
```
The query requires an index. You can create it here: https://console.firebase.google.com/...
```
Click the link and it will automatically create the required index for you.

### Option 3: Via Firebase CLI
Add to your `firestore.indexes.json`:
```json
{
  "indexes": [
    {
      "collectionGroup": "Events",
      "queryScope": "COLLECTION",
      "fields": [
        {
          "fieldPath": "customerUid",
          "order": "ASCENDING"
        },
        {
          "fieldPath": "eventGenerateTime",
          "order": "DESCENDING"
        }
      ]
    }
  ]
}
```

Then deploy:
```bash
firebase deploy --only firestore:indexes
```

## Notes
- Index creation can take a few minutes
- The app will work without the index but queries will be slower
- The code has been updated to handle missing indexes gracefully by falling back to a query without ordering and sorting in memory
