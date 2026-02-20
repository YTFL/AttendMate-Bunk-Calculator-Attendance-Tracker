# AttendMate — Setup & User Guide

A complete walkthrough of everything you need to get started and make the most of AttendMate.

---

## 📋 Table of Contents

1. [Setting Up Your Semester](#1-setting-up-your-semester)
2. [Adding Subjects Manually](#2-adding-subjects-manually)
3. [Importing Subjects via JSON](#3-importing-subjects-via-json)
4. [Marking Attendance](#4-marking-attendance)
5. [Calendar View](#5-calendar-view)
6. [Bunk Meter](#6-bunk-meter)
7. [Notifications](#7-notifications)
8. [More](#8-more)
9. [Tips & Tricks](#9-tips--tricks)

---

## 1. Setting Up Your Semester

Before you can add subjects or track attendance, you must set up a semester. The app is intentionally semester-aware — features stay locked until a valid semester is configured.

### Steps

1. Open AttendMate and tap the **Semester** tab in the bottom navigation bar.
2. Tap **Set Up Semester** (or the edit icon if one already exists).
3. Fill in the following fields:

   | Field | Description |
   |---|---|
   | **Start Date** | First day of your semester |
   | **End Date** | Last day of your semester (must be after start date) |
   | **Target Attendance %** | Your college's minimum requirement (e.g. `75`) |

4. Tap **Save**.

### Semester Status Indicators

Once set up, the Semester screen shows a status banner:

| Status | Meaning |
|---|---|
| 🟡 **Not Started** | Today is before the start date |
| 🟢 **Active** | Semester is currently running |
| 🔴 **Ended** | Today is after the end date |

> **Note:** Attendance tracking, subject management, and the Today tab are all disabled when the semester is not active.

---

## 2. Adding Subjects Manually

1. Tap the **Subjects** tab.
2. Tap the **＋** floating action button at the bottom-right.
3. Fill in the subject details:

   | Field | Description |
   |---|---|
   | **Name** | Full subject name (e.g. `Mathematics`) |
   | **Acronym** *(optional)* | Short display name shown on cards (e.g. `MTH`) |
   | **Color** | Pick one of 10 colors for easy identification |

4. Tap **Add Time Slot** to set the weekly schedule:
   - Select the **day of the week**
   - Set the **start time** and **end time** using the time picker
   - Tap **Add** to save the slot
   - Repeat for every day/time this subject meets

5. Tap **Save Subject**.

### Editing or Deleting a Subject

- Tap any subject card to open its **detail/edit** screen.
- Modify any field or time slot, then tap **Save**.
- To delete, scroll to the bottom and tap **Delete Subject** → confirm the dialog.

---

## 3. Importing Subjects via JSON

If you have your full timetable ready, you can import all subjects at once instead of adding them one by one.

### How to Import

1. On the **Subjects** tab, tap the **Import** icon (top-right area of the app bar).
2. Paste your JSON into the text field.
3. Tap **Parse** to validate and preview the subjects.
4. Review the preview cards — each subject shows its name, acronym, and schedule.
5. Tap **Import** to confirm and add all subjects.

### JSON Format

```json
{
  "subjects": [
    {
      "name": "Mathematics",
      "acronym": "MTH",
      "schedule": [
        {
          "day": "monday",
          "startTime": "09:00",
          "endTime": "10:30"
        },
        {
          "day": "wednesday",
          "startTime": "14:00",
          "endTime": "15:30"
        }
      ]
    },
    {
      "name": "Physics",
      "acronym": "PHY",
      "schedule": [
        {
          "day": "tuesday",
          "startTime": "11:00",
          "endTime": "12:00"
        },
        {
          "day": "friday",
          "startTime": "10:00",
          "endTime": "11:00"
        }
      ]
    }
  ]
}
```

### JSON Rules

| Field | Rules |
|---|---|
| `name` | Required. Any text. |
| `acronym` | Optional. Short code shown on subject cards. |
| `day` | Lowercase: `monday`, `tuesday`, `wednesday`, `thursday`, `friday`, `saturday`, `sunday` |
| `startTime` / `endTime` | 24-hour format: `HH:MM` (e.g. `09:00`, `14:30`) |

> **Tip:** Tap **Copy Format** inside the import screen to copy the JSON template to your clipboard.

---

> ### 🤖 Skip the Typing — Use AI to Generate Your JSON!
>
> Don't want to type out the JSON manually? Just send your timetable to an AI and let it do the work in seconds.
>
> **Steps:**
> 1. Take a **screenshot** of your timetable, or have your **timetable PDF / image** ready.
> 2. In AttendMate, tap **Copy Format** to copy the JSON reference to your clipboard.
> 3. Open any AI chatbot — **Gemini**, **ChatGPT**, **Claude**, or any other.
> 4. Upload your timetable image and send this prompt (paste your copied JSON format at the end):

**📋 Ready-to-use prompt — copy and send this to any AI:**

```
I have attached an image/screenshot of my college timetable. Convert it into the following JSON format exactly:

{
  "subjects": [
    {
      "name": "Subject Name",
      "acronym": "ACR",
      "schedule": [
        {
          "day": "monday",
          "startTime": "09:00",
          "endTime": "10:00"
        }
      ]
    }
  ]
}

Rules to follow:
- "name" is the full subject name as shown in the timetable.
- "acronym" is a short 2–4 letter code for the subject (create one if not shown).
- "day" must be fully lowercase: monday, tuesday, wednesday, thursday, friday, saturday, or sunday.
- "startTime" and "endTime" must be in 24-hour HH:MM format (e.g. 09:00, 14:30).
- Include every subject and every time slot shown in the timetable.
- Return only the raw JSON with no extra explanation.
```

> 5. Copy the JSON the AI returns, paste it into AttendMate's import screen, and tap **Import**. Done! ✅

---

Colors are automatically assigned from the available palette during import.


---

## 4. Marking Attendance

### Today's Schedule

The **Today** tab (home screen) shows all classes scheduled for the current day, sorted by time.

Each class card shows:
- Subject name and acronym avatar (color-coded)
- Class start and end time
- Current attendance status

### Marking Individual Classes

Each class card has action buttons:

| Button | Action |
|---|---|
| ✅ **Mark Present** | Records you as attended |
| ❌ **Mark Absent** | Records you as absent |
| 🔄 **Unmark** | Reverts to "Awaiting Status" |

Tapping **Mark Present** on an already-present class shows an **Unmark** and **Mark Absent** option, and vice versa. You can toggle freely.

### Status Colours at a Glance

| Colour | Status |
|---|---|
| 🟢 Green | Attended |
| 🔴 Red | Absent |
| ⚪ Grey | Cancelled (holiday/skipped) |
| Neutral | Awaiting Status |

### Bulk Day Actions

At the top of the Today tab, three action buttons let you manage the entire day at once:

| Action | Effect |
|---|---|
| **Mark Holiday** | Cancels all classes for the day — they don't count toward attendance |
| **Skip Day** | Marks all classes as Absent |
| **Mark Today as Present** | Marks all unmarked classes as Present |

A confirmation dialog appears before any bulk action.

> **Auto-Marking:** Any class still unmarked at 10 PM is automatically marked as Present (smart holiday skip — skipped if the day is a holiday).

### Using Notifications to Mark Attendance

When a class ends, a notification fires with two action buttons:
- **Mark Present** — marks directly from the notification
- **Mark Absent** — marks directly from the notification

Tapping the notification body opens the **Today** tab. Already-marked classes are silently skipped.

---

## 5. Calendar View

The Calendar gives you a full semester-wide view of your attendance history.

### Opening the Calendar

Tap the **Calendar** icon in the app bar on the **Today** tab (or navigate via the subjects screen).

### Reading the Calendar

Each day on the calendar is colour-coded:

| Colour | Meaning |
|---|---|
| 🟢 Green | All classes attended |
| 🔴 Red | All classes absent / skipped |
| 🟠 Orange/Mixed | Mix of attended and absent |
| ⚫ Grey | Holiday or cancelled |
| 🔵 Blue/Outlined | Upcoming date (read-only) |

A **legend** at the bottom of the screen explains each state.

### Reviewing & Editing Past Attendance

1. Tap any **past date** on the calendar.
2. A **bottom sheet** slides up showing all classes for that day with their status.
3. In the bottom sheet you can:
   - Toggle individual class statuses (Present / Absent / Unmark)
   - Use bulk actions: **Mark All Present**, **Skip Day**, **Mark Holiday**
4. The calendar updates immediately after any change.

> **Upcoming dates** are shown as read-only — you cannot pre-mark future attendance.

---

## 6. Bunk Meter

The **Bunk Meter** tab gives you intelligent predictions about your attendance standing for every subject.

### What It Shows

For each subject:

| Info | Description |
|---|---|
| Current % | Your attendance percentage so far |
| Classes Held | Total classes that have taken place |
| Attended | Classes you were present for |
| Bunked | Classes you were absent for |
| Remaining | Classes left before semester end |

### Predictions

The Bunk Meter calculates three scenarios automatically:

| Scenario | Message Colour | Meaning |
|---|---|---|
| **Above Target** | 🟢 Green | Shows how many classes you can safely bunk |
| **Below Target** | 🟠 Orange | Shows how many classes you must attend |
| **Target Unreachable** | 🔴 Red | Even attending everything won't meet the target |

Subjects needing attention (below or near target) are sorted to the **top** automatically.

### Search

Use the **search bar** at the top of the Bunk Meter to filter subjects by name. Results update in real time.

---

## 7. Notifications

AttendMate automatically schedules notifications for every class and rescheduled when you edit a subject.

### Permissions Required

- **Post Notifications** — required for all notifications
- **Schedule Exact Alarms** — required on Android 12+ for precise timing (prompted automatically)

If you dismissed the permission prompt, go to **Android Settings → Apps → AttendMate → Permissions** to enable them.

### How Notifications Work

- A notification fires **when each class ends**
- You can mark attendance directly from the notification via action buttons
- A brief confirmation notification appears after marking, then auto-dismisses in 2 seconds
- If you already marked a class, its notification is silently skipped

---

## 8. More

### Time Format

On the **Subjects** tab, tap the **clock icon** in the app bar to toggle between:
- **12-hour (AM/PM)** format
- **24-hour** format

This preference applies everywhere in the app — subject cards, calendar view, add/edit screens, and the Today tab.

---

## 9. Tips & Tricks

| Tip | Details |
|---|---|
| 🎨 **Color-code wisely** | Assign distinct colors to subjects for instant visual recognition on the Today tab and Calendar |
| 📋 **Bulk import saves time** | Prepare your full timetable JSON before term starts and import everything at once |
| 🔔 **Keep notifications on** | The end-of-class notification is the easiest way to never forget to mark attendance |
| 📆 **Fix past attendance** | Made a mistake? Tap any past date on the Calendar to correct it |
| 🎯 **One target for all** | The attendance target you set in the Semester screen applies to all subjects equally |
| 🏖️ **Use Holiday, not Skip** | Marking a day as Holiday cancels classes without hurting your attendance. Skip marks all as Absent — only use it if you actually skipped |
| 🔍 **Search the Bunk Meter** | If you have many subjects, use the search bar to quickly jump to a specific one |


---

> **All data is stored locally on your device. No internet connection is required and no data ever leaves your phone.**

---

*For version history, see [CHANGELOG.md](CHANGELOG.md). For a complete feature list, see [FEATURES.md](FEATURES.md).*
