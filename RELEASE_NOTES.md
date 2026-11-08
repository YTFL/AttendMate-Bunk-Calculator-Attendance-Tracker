# AttendMate 2.4.0 — Release Notes

**Release Date:** 2026-11-08  
**Version:** 2.4.0  
**Build Number:** 33  
**Platform:** Android  
**Minimum Android Version:** 7.0 (API 24)

---

## 🚀 AttendMate 2.4.0 Update

AttendMate 2.4.0 delivers major performance improvements to calendar synchronization, fully replaces the external Google Maps SDK with phone-native map app redirection and intelligent coordinate parsing, guarantees dependable midnight Google Drive cloud backups, and refines smart pre-class notifications alongside extra class tracking and future lecture predictions.

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

### 2. Native Maps App Redirection & Smart Coordinate Parser (Zero API Costs)
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

### 3. Streamlined Interactive Tutorial
- **Distraction-Free Onboarding**:
  - Replaced the intimidating numeric step counter (`"STEP 1 OF 9"`) with a sleek, minimalist `"QUICK GUIDE"` chip.
  - Significantly reduces onboarding drop-off and encourages new users to explore key app interactions naturally.

---

## 🐛 Bug Fixes & Refinements

### 1. Guaranteed Google Drive Midnight Backup Reliability
- **Independent Modification Timestamp Tracking**:
  - Added `last_data_modified_timestamp_ms` and `last_google_drive_backup_timestamp_ms`. If local auto-backups clear the dirty flag earlier in the day, the midnight sync compares modification times and forces a Drive backup if local data changed after the last Drive upload.
- **WorkManager Periodic Policy**:
  - Updated the periodic WorkManager policy from `.update` to `ExistingPeriodicWorkPolicy.keep` with `NetworkType.connected`, ensuring the 24-hour periodic schedule is never cancelled or delayed on subsequent app launches.
- **App Startup Catch-Up Routine**:
  - Added an automated startup catch-up that verifies whether the midnight backup was missed due to deep Android battery optimization (Doze mode) and executes it on app launch.

---

### 2. Smart Pre-Class Notification Filtering
- **Suppress Reminders for Absent & Holiday Classes**:
  - 5-minute pre-class room reminders are now automatically unscheduled and suppressed if a class is marked absent or holiday (cancelled), eliminating annoying notifications for classes you aren't attending.
- **Preserved Reminders for Attended & Unmarked Classes**:
  - Pre-class notifications continue to trigger reliably for unmarked classes and classes marked present, ensuring room navigation details are always on hand.

---

### 3. Calendar Synchronization Deletion & Differential Engine
- Content-hash diffing (64-bit FNV-1a) ensures unchanged slots require **0 API calls**.
- Two-tier guaranteed deletion cleanly wipes outdated or deleted slots across local device calendars and Google Calendar.

---

## 📥 Installation

1. Download **AttendMate-v2.4.0.apk**
2. Install directly over your existing app (all subjects, logs, and settings are preserved)
3. Requires Android 7.0 (API 24) or higher

---

*Thank you for using AttendMate! Stay on top of your attendance without the guesswork.*
