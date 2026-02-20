# AttendMate — Features Overview

> A comprehensive attendance tracking app for students. Here's everything AttendMate can do.

---

## 🗓️ Semester & Subject Setup

### Semester
Set up your semester once and the app handles the rest.

| Feature | Description |
|---|---|
| Semester creation | Set start date, end date, and your target attendance percentage |
| Automatic status detection | App knows if your semester hasn't started, is active, or has ended |
| Semester editing | Update your semester details anytime |
| Status banners | Clear messages shown when semester is inactive |

### Subjects
Add and organize your subjects the way you want.

| Feature | Description |
|---|---|
| Unlimited subjects | Add as many subjects as needed |
| Custom acronyms | Short display names for subjects (auto-generated from initials if left empty) |
| Color coding | 10 colors to choose from, auto-assigned to keep them unique |
| Per-subject attendance target | Set a different target percentage for each subject |
| Full CRUD | Add, edit, and delete subjects with confirmation prompts |

### Schedule
Define when each class happens during the week.

| Feature | Description |
|---|---|
| Weekly schedule builder | Assign specific days and time slots to each subject |
| Multiple slots per subject | A subject can appear multiple times on the same day or across different days |
| Time picker | Tap to select start and end times easily |
| Edit & delete slots | Modify or remove individual time slots at any time |

---

## 📥 Timetable Import

Quickly populate all your subjects in one go using a JSON format.

- Bulk import multiple subjects with their schedules in a single step
- Preview what will be imported before confirming
- Automatic color assignment during import
- Built-in format reference and copy-to-clipboard support
- Clear error messages if the format is incorrect

---

## 📆 Attendance Tracking

### Today's Schedule
Your daily attendance hub — see all today's classes and mark them as you go.

- Classes sorted by time, earliest first
- Mark each class as **Present** or **Absent** with a single tap
- Toggle or **Unmark** any class to revert it to _Awaiting Status_
- Visual status indicators: green (present), red (absent), grey (cancelled), neutral (awaiting)
- **Mark Today as Present** button to mark all pending classes at once
- Duplicate slots (same subject, same day) all shown correctly

### Bulk Day Actions
Take action on an entire day at once.

| Action | Effect |
|---|---|
| **Mark as Holiday** | Cancels all classes — does not affect your attendance percentage |
| **Skip Day** | Marks all classes as absent |
| **Mark as Present** | Marks all unmarked classes as present |

When a day is marked as a holiday, a dedicated screen replaces Today's Schedule and no action buttons are shown.

### Auto End-of-Day
At 10 PM, any class that is still unmarked is automatically marked as present — so you don't lose attendance for classes you forgot to log. Classes you've already marked are never overridden.

---

## 📊 Bunk Meter

A smart prediction tool that tells you how many classes you can afford to miss.

### Per-Subject Predictions

| Scenario | What you see |
|---|---|
| Above target | How many classes you can safely bunk continuously |
| Below target | How many classes you must attend to recover |
| Target unreachable | A clear warning that the target can no longer be met |

> **Note:** The semester-level bunk count keeps your *overall* average above target, but individual subjects can still fall below — check each subject's card for the full picture.

### Statistics per Subject
For each subject you can see: classes held, classes marked, classes attended, and classes bunked — displayed separately so you always know where you stand.

### Search
Quickly find any subject in the Bunk Meter list by typing its name. Results filter in real time, showing a match count and a clear empty state if nothing matches.

---

## 📅 Attendance Calendar

A full-semester calendar that gives you a bird's-eye view of your attendance.

- Month view with color-coded dates for each attendance state
- **Swipe** left/right to move between months
- Tap any past date to see its classes and update attendance via a bottom sheet
- Bulk actions available per day (Mark Present, Skip, Holiday)
- Upcoming dates shown as read-only
- Day detail view with classes sorted by time
- **Swipe** in the day view to jump to the previous/next day that has classes

---

## 🔔 Notifications

AttendMate automatically reminds you to mark attendance after each class ends.

- Notification fires when a class ends with **Mark Present** and **Mark Absent** action buttons
- Mark attendance directly from the notification without opening the app
- Tap the notification to go straight to Today's Schedule
- A brief confirmation notification appears after marking, then auto-dismisses
- Notifications are skipped for classes already marked
- 5-minute grace period for classes that ended very recently
- Exact alarm scheduling with timezone awareness
- Notifications are automatically rescheduled when you edit a subject

---

## 🔄 In-App Updates

- Automatic update check on app launch
- "What's New" dialog showing release highlights for the new version
- Download and install updates directly from within the app

---

## ⋯ More Tab

A dedicated tab (three-dots icon) for app-wide settings and info.

| Option | Description |
|---|---|
| Time format | Switch between 12-hour (AM/PM) and 24-hour display |
| App version | See the current version and build number |
| Setup Guide | In-app walkthrough for getting started |
| Feedback | Direct link to submit a feature request or bug report on GitHub |

The time format preference applies across the entire app — schedule chips, calendar views, and time pickers all follow the same setting.

---

## 🎨 Themes

| Theme | Description |
|---|---|
| Light | Clean white background |
| Dark | True black for AMOLED-friendly viewing |
| System | Follows your device's system-wide theme setting |

Theme preference is saved and restored on every launch.

---

## 🔐 Privacy

AttendMate works entirely offline. All your data lives only on your device — no accounts, no syncing, no analytics, no internet connection required.

---

*AttendMate — built for students who want to stay on top of their attendance without the guesswork.*
