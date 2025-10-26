# Quiz Restart Feature - Quick Start Guide 🔄

## How to Restart a Quiz

### Step-by-Step Instructions

#### 1️⃣ **Complete Your Quiz**
```
Run your quiz normally until it ends
  ↓
All questions answered
  ↓
Final leaderboard shown
  ↓
Quiz status changes to "ENDED"
```

#### 2️⃣ **Find the Restart Button**
```
Host Control Panel
┌────────────────────────────────┐
│  [Start Quiz]  (if draft)      │
│  OR                            │
│  [Restart Quiz]  (if ended) ← │
└────────────────────────────────┘
```

The restart button appears **only when the quiz has ended**.

#### 3️⃣ **Choose Restart Mode**

When you click "Restart Quiz", you'll see this dialog:

```
╔════════════════════════════════════╗
║  🔄  Restart Quiz                  ║
╠════════════════════════════════════╣
║                                    ║
║  How would you like to restart?   ║
║                                    ║
║  ┌──────────────────────────────┐ ║
║  │ ✨ Fresh Start                │ ║
║  │                               │ ║
║  │ Remove all participants and   │ ║
║  │ responses. Start completely   │ ║
║  │ fresh.                     → │ ║
║  └──────────────────────────────┘ ║
║                                    ║
║  ┌──────────────────────────────┐ ║
║  │ 👥 Keep Participants          │ ║
║  │                               │ ║
║  │ Keep current participants in  │ ║
║  │ lobby. Reset their scores and │ ║
║  │ responses.                 → │ ║
║  └──────────────────────────────┘ ║
║                                    ║
║                      [Cancel]      ║
╚════════════════════════════════════╝
```

#### 4️⃣ **Select Your Option**

**Option A: Fresh Start** ✨
- Best for: Running quiz with different groups
- Effect:
  - All participants removed
  - Lobby is empty
  - New people can join
  - Previous data archived
  
**Option B: Keep Participants** 👥
- Best for: Replay with same group
- Effect:
  - Participants stay in lobby
  - Scores reset to 0
  - Ready to play again
  - Previous data archived

#### 5️⃣ **Wait for Processing**
```
┌─────────────────────────┐
│  ⏳ Restarting quiz...  │
└─────────────────────────┘
```
Takes 1-2 seconds

#### 6️⃣ **Quiz Restarted! 🎉**
```
✅ Success Message Shown
  ↓
Quiz returns to DRAFT status
  ↓
Waiting Lobby appears
  ↓
Ready for new session!
```

---

## Visual Flow Diagram

```
                    Quiz Ended
                        │
                        ▼
              ┌─────────────────┐
              │  Restart Quiz   │◄── Click Here
              │     Button      │
              └────────┬────────┘
                       │
                       ▼
        ┌──────────────────────────┐
        │   Restart Dialog         │
        │                          │
        │  Choose Mode:            │
        │  • Fresh Start           │
        │  • Keep Participants     │
        └──────────┬───────────────┘
                   │
           ┌───────┴────────┐
           │                │
           ▼                ▼
    Fresh Start      Keep Participants
           │                │
           │                │
    Remove All       Reset Scores
    Participants     Keep People
           │                │
           └────────┬───────┘
                    │
                    ▼
            ┌───────────────┐
            │   Processing   │
            │   1-2 seconds  │
            └───────┬───────┘
                    │
                    ▼
            ┌───────────────┐
            │    Success!    │
            │   Quiz Reset   │
            └───────┬───────┘
                    │
                    ▼
            ┌───────────────┐
            │ Waiting Lobby  │
            │   Appears!     │
            └───────────────┘
```

---

## When to Use Each Mode

### 🆕 Fresh Start

**Use When:**
- ✅ Running quiz for different groups throughout the day
- ✅ Starting a completely new session
- ✅ Want to clear all previous participants
- ✅ Running competitive tournaments (new bracket)

**Example Scenario:**
```
Morning Session:
- 20 students take quiz
- Session ends at 10:00 AM

Afternoon Session (Fresh Start):
- Previous students removed
- New 15 students join
- Clean slate for afternoon group
```

### 👥 Keep Participants

**Use When:**
- ✅ Same group wants to replay
- ✅ Practice round before real quiz
- ✅ Learning session (try again to improve)
- ✅ Fixed technical issue and want to continue

**Example Scenario:**
```
Practice Round:
- 10 team members take quiz
- Want to try again with same people

Replay (Keep Participants):
- Same 10 people stay in lobby
- Scores reset to zero
- Everyone tries to beat their previous score
```

---

## What Happens to Data?

### Data Archival (Not Deletion!)

#### Previous Participant Data
```dart
// Fresh Start Mode
{
  "isActive": false,          // Marked inactive
  "archivedAt": "2025-10-26", // Timestamp added
  // All other data preserved
}

// Keep Participants Mode
{
  "currentScore": 0,          // Reset
  "questionsAnswered": 0,     // Reset
  "correctAnswers": 0,        // Reset
  "currentRank": null,        // Cleared
  "bestRank": null,           // Cleared
  // Still active in lobby
}
```

#### Previous Responses
```dart
{
  "archived": true,           // Marked as archived
  "archivedAt": "2025-10-26", // Timestamp added
  // All response data preserved
}
```

**Important:** Nothing is permanently deleted! All data is archived for historical analysis.

---

## User Experience

### What Participants See

#### Fresh Start Mode
```
Previous Participant:
  ↓
Quiz ended
  ↓
Host restarts (Fresh Start)
  ↓
Participant's session ends
  ↓
Must join again as new participant
```

#### Keep Participants Mode
```
Participant:
  ↓
Quiz ended (see results)
  ↓
Host restarts (Keep Participants)
  ↓
Automatically return to waiting lobby
  ↓
Score shows 0
  ↓
Ready to play again!
```

---

## Testing Guide

### Test Scenario 1: Fresh Start
```
1. Complete a quiz with 5 participants
2. Click "Restart Quiz"
3. Select "Fresh Start"
4. ✅ Verify: Lobby is empty
5. ✅ Verify: Participant count shows 0
6. ✅ Verify: Previous participants can join as new
7. ✅ Verify: Old responses archived in database
```

### Test Scenario 2: Keep Participants
```
1. Complete a quiz with 5 participants
2. Click "Restart Quiz"  
3. Select "Keep Participants"
4. ✅ Verify: 5 participants still in lobby
5. ✅ Verify: All scores show 0
6. ✅ Verify: Participants see waiting lobby
7. ✅ Verify: Can start quiz immediately
8. ✅ Verify: Old responses archived in database
```

### Test Scenario 3: Multiple Restarts
```
1. Complete quiz
2. Restart (Fresh Start)
3. Run quiz again
4. Restart (Keep Participants)
5. Run quiz again
6. ✅ Verify: Each session data properly archived
7. ✅ Verify: No data conflicts
8. ✅ Verify: Performance remains good
```

---

## Troubleshooting

### Issue: Restart button not showing
**Solution:**
- Ensure quiz status is "ended"
- Check you're logged in as host
- Refresh the page
- Check console for errors

### Issue: "Restarting quiz..." stuck
**Solution:**
- Check internet connection
- Wait 30 seconds
- If still stuck, refresh page
- Try restart again

### Issue: Participants not reset correctly
**Solution:**
- Verify you selected correct mode
- Check Firestore console for data
- Look for archived responses
- Contact support if data integrity issue

### Issue: Error message on restart
**Solution:**
- Check host permissions
- Verify quiz ID is valid
- Check Firestore rules
- Review error logs

---

## Best Practices

### 📋 Before Restart
- ✅ Announce to participants you're restarting
- ✅ Decide which mode you need
- ✅ Save/export results if needed
- ✅ Ensure stable internet connection

### 🎯 During Restart
- ✅ Wait for success message
- ✅ Don't close the app
- ✅ Don't click multiple times
- ✅ Verify participant count after

### ✨ After Restart
- ✅ Confirm quiz is in draft state
- ✅ Check waiting lobby appears
- ✅ Inform participants they can join/rejoin
- ✅ Start when ready

---

## FAQ

**Q: Can I undo a restart?**
A: No, but all previous data is archived, not deleted. You can view historical data.

**Q: How many times can I restart?**
A: Unlimited! Restart as many times as needed.

**Q: Do participants lose their history?**
A: Their previous scores are archived. They start fresh each restart.

**Q: Can I restart during a live quiz?**
A: No, end the quiz first, then restart.

**Q: What happens to leaderboard?**
A: Leaderboard resets. Previous leaderboards are archived.

**Q: Can participants see their archived data?**
A: Not currently in the UI, but data exists in database for host analysis.

**Q: Does restart affect questions?**
A: No, all questions remain the same.

**Q: Can I change questions after restart?**
A: Yes! Quiz returns to draft, so you can edit questions.

---

## Success Indicators

After a successful restart, you should see:

✅ **Success toast message**
✅ **Quiz status badge shows "DRAFT"**
✅ **Waiting lobby appears**
✅ **Participant counter shows correct number**
✅ **"Start Quiz" button available**
✅ **Questions intact and ready**

---

## Summary

The restart feature allows hosts to:
- 🔄 Run the same quiz multiple times
- 👥 Choose whether to keep participants
- 📊 Preserve all historical data
- ⚡ Quick and easy process (2 seconds)
- 🎯 Perfect for repeated sessions

**Two Modes:**
1. **Fresh Start**: New participants, clean slate
2. **Keep Participants**: Same group, reset scores

**Key Points:**
- Nothing is permanently deleted
- Choose mode based on use case
- Takes only 1-2 seconds
- Unlimited restarts allowed
- Data safely archived

---

**Ready to restart your first quiz? Follow the steps above and enjoy the flexibility of running multiple quiz sessions!** 🚀✨

---

**Need Help?**
- Check console logs for errors
- Verify host permissions
- Review Firestore data
- Contact support team
