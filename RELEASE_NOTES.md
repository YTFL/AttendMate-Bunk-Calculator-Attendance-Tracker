# AttendMate 2.3.0 — Release Notes

**Release Date:** 2026-11-08  
**Version:** 2.3.0  
**Platform:** Android  
**Minimum Android Version:** 7.0 (API 24)

---

## 🚀 AttendMate 2.3.0 Update

AttendMate 2.3.0 delivers major performance improvements to calendar synchronization, fully replaces the external Google Maps SDK with phone-native map app redirection and intelligent coordinate parsing, guarantees dependable midnight Google Drive cloud backups, and refines smart pre-class notifications alongside extra class tracking and future lecture predictions.

---

## 🚀 New Features & Enhancements

### 1. High-Speed Calendar Synchronization & Interruption Protection
- **Concurrent Worker Pool (Up to 5x Faster Sync)**:
  - Re-architected schedule slot synchronization and differential hash lookups to run across a 5-worker concurrent pool.
  - Eliminated sequential one-by-one network blocking when syncing timetables mid-semester with dozens of lecture slots.
- **Determinate Progress Modal (`SyncProgressDialog`)**:
  - Replaced ambiguous indeterminate loaders with a clear modal progress dialog showing the **exact sync percentage** (`0%` to `100%`) alongside real-time slot progress labels (e.g. `Syncing Data Structures (4/12)...`).
- **Interruption & Back-Dismissal Shield (`PopScope`)**:
  - Enforced `PopScope(canPop: false)` across both `CalendarSyncSelectionScreen` and `GoogleCalendarSyncScreen` during active sync.
  - Users can no longer accidentally exit mid-sync, preventing partially populated calendars, orphaned slots, or desynchronized event states.
- **Background Completion Notification**:
  - Sync automatically completes with an automated system status bar notification confirming how many slots and subjects were synchronized.

---

### 2. Native Maps App Redirection & Smart Coordinate Parser (No Paid API Keys)
- **Zero API Costs & SDK Bloat Removed**:
  - Completely stripped out the proprietary Google Maps SDK (`google_maps_flutter`), native platform interfaces, and manifest API key dependencies.
  - Shrank the application binary by over **1.2 MB** and removed all third-party tracking or billing constraints.
- **Direct Phone-Native Map Redirection**:
  - Added an **"Open Default Maps App"** button that directly launches the user's preferred installed navigation app (Google Maps, OsmAnd, Apple Maps, Petal Maps, etc.) using `geo:0,0?q=`.
- **Intelligent Multi-Format Coordinate Parser**:
  - Seamlessly parses pasted location data directly from the clipboard with a 1-tap **"Paste from Clipboard"** button.
  - Supports all major formats:
    - **Decimal Coordinates**: `12.9716, 77.5946` / `12.9716 77.5946`
    - **DMS Format**: `12°58'17.8"N 77°35'40.6"E`
    - **Google Maps Share Links**: `https://maps.app.goo.gl/...`, `https://google.com/maps?q=lat,lng`, and `/@lat,lng,z`
    - **Dropped Pin Clipboard Strings**: `Dropped pin: near 560001, Bangalore... 12.9716, 77.5946`
  - Real-time preview validates the coordinates and gives instant visual feedback.

---

### 3. Consider Pre-Marked Future Lectures in Bunk Calculator
- **Future Attendance Predictions**:
  - Students can factor future pre-marked classes (attended, absent, or cancelled holidays) into the Bunk Calculator ("What-If Calculator") and Bunk Meter instead of treating them as undecided future classes.
- **Accurate Remaining & Safe Bunk Metrics**:
  - Pre-marked attendance credits attended or missed classes towards target thresholds, while pre-marked holidays and cancellations are deducted from remaining class counts rather than incorrectly inflating them.
- **Toggle Control**:
  - Easily toggle via the dedicated "Consider Future Marked Lectures" option in the Bunk Calculator sheet.

---

### 4. One-Day Extra / Makeup Classes (Without Changing Weekly Timetable)
- **One-Off Extra Class Tracking**:
  - Log a one-off extra, rescheduled, or makeup class on any specific date without touching or cluttering your recurring weekly timetable.
- **Quick Add from Daily Views**:
  - Tap **Add Extra Class** directly from **Today's Schedule** or from any **Calendar Day Sheet**.
- **Attendance & Bunk Tracking**:
  - Extra classes support standard swipe gestures for Present and Absent, can be marked as Holiday, and directly count towards subject attendance and required class targets.
- **Non-Destructive Deletion**:
  - Delete an extra class card to remove only that specific one-off slot and attendance record without altering parent subjects.

---

### 5. Streamlined Interactive Tutorial
- **Distraction-Free Onboarding**:
  - Replaced the intimidating numeric step counter (`"STEP 1 OF 9"`) with a sleek, minimalist `"QUICK GUIDE"` chip.
  - Significantly reduces onboarding drop-off and encourages new users to explore key app interactions naturally.

---

### 6. Developer Portfolio in More Tab
- Added a dedicated "More apps by me" tile under Help & Support on the More tab linking to [ytfl.github.io](https://ytfl.github.io/) with external URL confirmation protection.

---

## 🐛 Bug Fixes & Refinements

- **Guaranteed Google Drive Midnight Backup Reliability**:
  - **Independent Modification Timestamp Tracking**: Added `last_data_modified_timestamp_ms` and `last_google_drive_backup_timestamp_ms`. If local auto-backups clear the dirty flag earlier in the day, the midnight sync compares modification times and forces a Drive backup if local data changed after the last Drive upload.
  - **WorkManager Periodic Policy**: Updated the periodic WorkManager policy from `.update` to `ExistingPeriodicWorkPolicy.keep` with `NetworkType.connected`, ensuring the 24-hour periodic schedule is never cancelled or delayed on subsequent app launches.
  - **App Startup Catch-Up Routine**: Added an automated startup catch-up that verifies whether the midnight backup was missed due to deep Android battery optimization (Doze mode) and executes it on app launch.

- **Smart Pre-Class Notification Filtering**:
  - **Suppress Reminders for Absent & Holiday Classes**: 5-minute pre-class room reminders are now automatically unscheduled and suppressed if a class is marked absent or holiday (cancelled).
  - **Preserved Reminders for Attended & Unmarked Classes**: Pre-class notifications continue to trigger reliably for unmarked classes and classes marked present, ensuring room navigation details are always on hand.

- **Calendar Synchronization Deletion & Differential Engine**:
  - Content-hash diffing (64-bit FNV-1a) ensures unchanged slots require **0 API calls**.
  - Two-tier guaranteed deletion cleanly wipes outdated or deleted slots across local device calendars and Google Calendar.

---

## 📥 Installation

1. Download **AttendMate-v2.3.0.apk**
2. Install directly over your existing app (all subjects, logs, and settings are preserved)
3. Requires Android 7.0 (API 24) or higher

---

*Thank you for using AttendMate! Stay on top of your attendance without the guesswork.*
