# AttendMate

**AttendMate** is an attendance tracking app for students — track classes, calculate bunking capacity, and stay on top of your attendance target throughout the semester.

![App Version](https://img.shields.io/badge/version-1.4-blue)
![Platform](https://img.shields.io/badge/platform-Android-green)
![License](https://img.shields.io/badge/license-MIT-orange)

---

## 📱 Overview

AttendMate gives you a clear picture of where you stand in every subject — how many classes you can still bunk, how many you need to attend to recover, and when a subject is beyond saving. All data stays on your device with no accounts or internet required.

![App Home Screen showing Today's Schedule with bottom navigation](./screenshots/todays_schedule.png)

---

## ✨ Key Features

### 📅 Semester Management
- Create a semester with start date, end date, and target attendance percentage
- Automatic status detection — tracks whether your semester is upcoming, active, or ended
- Edit semester details anytime

![Semester Setup Screen with dates and target percentage configuration](./screenshots/semester_setup.png)

### 📚 Subject Management
- Add unlimited subjects with custom names, acronyms, colors, and per-subject attendance targets
- Acronyms auto-generated from subject initials if left empty (filler words like "and", "of", "the" are skipped)
- 10 colors available, auto-assigned to keep subjects visually distinct
- **Collapsible subject cards** — collapse to just the name and acronym, expand for full schedule details
- Edit or delete subjects anytime

![Subject List showing color-coded subjects](./screenshots/subject_list.png)

### 📥 Timetable Import
- Bulk import all your subjects and schedules at once using a simple JSON format
- Preview what will be imported before confirming
- Automatic color assignment during import
- Built-in format reference with copy-to-clipboard support

![Import Timetable Screen with JSON input interface](./screenshots/import_timetable.png)

### 📆 Today's Schedule
- View all classes for today, sorted by time
- Mark each class as **Present** or **Absent** with one tap; unmark to revert to _Awaiting_
- **Mark Today as Present** — marks all pending classes at once
- Mark entire day as **Holiday** (cancels all classes, excluded from attendance calculations)
- **Skip Day** — marks all classes absent
- When a day is a holiday, classes are still visible with individual **Holiday** actions per class
- Auto end-of-day: at 10 PM, any still-unmarked class is automatically marked Present

![Today's Schedule with Present/Absent action buttons](./screenshots/todays_schedule.png)

### 📊 Bunk Meter
- Per-subject predictions: how many classes you can safely bunk, or how many you must attend
- Clear warning when a subject's target is no longer achievable
- Statistics per subject: classes held, attended, bunked, and current percentage
- **Collapsible bunk meter cards** — collapse for a quick status summary, expand for full detail
- **Search** — filter subjects by name in real time

![Bunk Meter showing predictions and statistics for all subjects](./screenshots/bunk_meter.png)

### 📅 Attendance Calendar
- Full-semester month view with colour-coded dates for each attendance state
- Swipe left/right to navigate between months
- Tap any past date to review its classes and update attendance from a bottom sheet
- Bulk day actions: Mark Present, Skip, Holiday
- Day detail view with classes sorted by time; swipe to jump to the next/previous day with classes
- Upcoming dates shown as read-only

### 🔔 Notifications
- Notification fires when each class ends with **Mark Present** and **Mark Absent** action buttons
- Mark attendance directly from the notification — no need to open the app
- Tap notification to navigate straight to Today's Schedule
- Brief confirmation notification after marking, auto-dismisses after 2 seconds
- Skips notifications for already-marked classes; 5-minute grace period for very recent classes
- Exact alarm scheduling with full timezone awareness

### 🔄 In-App Updates
- Automatic update check on launch; manual check available in the More tab
- In-app update dialog with "What's New" highlights
- Download and install the update directly from within the app

### ⋯ More Tab
- Switch between 12-hour (AM/PM) and 24-hour time format — applied across the whole app
- View current app version and build number
- In-app **Setup Guide** — swipeable section-by-section walkthrough with a table of contents
- **What's New** — bundled release notes viewable in-app
- Submit a feature request or bug report directly on GitHub

### 🎨 Theme Support
- Light mode (white), dark mode (true black, AMOLED-friendly), and System (follows device setting)
- Theme preference saved across restarts

### 💾 Privacy & Data
- All data stored locally using SQLite — no accounts, no cloud, no tracking
- Works fully offline

---

## 🎯 How It Works

### Setting Up
1. **Create a Semester:** Set start date, end date, and your target percentage
2. **Add Subjects:** Name, colour, acronym, and weekly schedule for each subject
3. **Import (Optional):** Paste a JSON timetable to add all subjects at once

### Daily Usage
1. Open **Today's Schedule** and mark each class as Present or Absent
2. Or mark attendance directly from the notification that fires after class ends
3. Use **Skip Day** or **Mark as Holiday** for special days

### Monitoring Progress
1. Check the **Bunk Meter** tab to see how many classes you can bunk per subject
2. Review the **Calendar** for a full-semester overview
3. Get warnings when recovering a subject's attendance becomes impossible

---

## 📖 JSON Import Format

```json
{
  "subjects": [
    {
      "name": "Mathematics",
      "acronym": "MTH",
      "schedule": [
        { "day": "monday",    "startTime": "09:00", "endTime": "10:30" },
        { "day": "wednesday", "startTime": "14:00", "endTime": "15:30" }
      ]
    }
  ]
}
```

**Valid days:** `monday` `tuesday` `wednesday` `thursday` `friday` `saturday` `sunday`  
**Time format:** `HH:MM` (24-hour)  
**Acronym:** optional — auto-generated from initials if omitted

---

## 🚀 Getting Started

### Download
Download the latest APK from the [Releases](../../releases) section.

### Installation
1. Download **AttendMate-v1.4.7.apk**
2. Enable **Install from Unknown Sources** in Android settings if prompted
3. Open the APK and install
4. Grant notification and exact alarm permissions for the best experience

### First Launch
1. Open AttendMate — a Setup Guide prompt appears on first launch
2. Go to the **Semester** tab and create your semester
3. Add subjects or use the JSON import
4. Start marking attendance from the **Today** tab

---

## 🔧 Technical Details

| | |
|---|---|
| **Platform** | Android (Flutter) |
| **Min Android** | 7.0 (API 24) |
| **Database** | SQLite (local, offline) |
| **State Management** | Provider |
| **UI Framework** | Material Design 3 |
| **Fonts** | Google Fonts (Oswald, Roboto, Open Sans) |
| **Notifications** | Flutter Local Notifications |
| **Background tasks** | WorkManager |

---

## 📝 Version Information

See [CHANGELOG.md](CHANGELOG.md) for full version history.  
See [RELEASE_NOTES.md](RELEASE_NOTES.md) for latest release notes.  
See [FEATURES.md](FEATURES.md) for a complete feature reference.

---

## 🤝 Contributing

AttendMate is open source — contributions, bug reports, and feature suggestions are welcome.  
See [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

For questions or support, please [open an issue](../../issues/new).

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

---

**Made with ❤️ for students who want to stay organized**
