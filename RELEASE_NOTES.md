# AttendMate 2.4.0 — Release Notes

**Release Date:** 2026-11-08  
**Version:** 2.4.0  
**Build Number:** 33  
**Platform:** Android  
**Minimum Android Version:** 7.0 (API 24)

---

> [!IMPORTANT]
> **Unified Calendar Synchronization & Google Drive Cloud Backup Upgrade**
>
> In AttendMate 2.4.0, calendar synchronization has been unified into a blazing-fast, phone-native calendar engine powered by Android's device calendar provider.
> - **Zero Rate Limits & Instant Sync**: Direct OS calendar synchronization writes schedules instantly with zero network latency, no Google API 403/429 rate limit errors, and full offline support.
> - **Automatic Cloud Mirroring**: When syncing to your Google or Outlook account, Android's native calendar sync adapter automatically mirrors your schedule to Google Calendar and Outlook in the cloud and on the web.
> - **Action Required After Updating**: If you previously used Google Calendar Sync, please navigate to **More > Calendar Sync**, switch **Sync Timetable to Calendar** to **ON**, and select your Google account in the interactive picker.
> - **Dedicated Google Drive Cloud Backup**: Google sign-in and cloud backups are now housed under a dedicated screen: **More > Google Drive Backup**.

---

## 🚀 AttendMate 2.4.0 Update

AttendMate 2.4.0 delivers major enhancements including flexible elective subject support and interactive timetable sharing, mid-semester new subject imports, dedicated one-off special class scheduling, performance-optimized parallel calendar synchronization, phone-native map app redirection, dependable midnight Google Drive backups, and smart pre-class notifications.

---

## 🚀 New Features & Enhancements

### 1. Elective Subject Support & Interactive Timetable Selection
- **Elective Subject Management**:
  - Mark any subject as an elective with a single toggle when adding or editing subjects, and optionally assign an elective group name (e.g. *Professional Elective I*).
  - Clear visual `Elective • <Group>` chip badges on subject cards for immediate recognition.
  - Upgraded SQLite database to version 10 with seamless automated migration for existing user data.
- **Interactive Elective Picker on Import**:
  - When importing a shared timetable or semester package that contains elective slots, AttendMate presents an interactive selection dialog allowing you to pick your specific elective for each slot or skip if not enrolled.
- **Structured Elective JSON Sharing**:
  - Timetable exports and imports now support dedicated `"electives": [{ "name": "...", "subjects": [...] }]` blocks with support for single or multiple choices per elective slot.

---

### 2. Mid-Semester New Subjects Import
- **Non-Destructive Course Additions**:
  - Import new subjects that start mid-semester (modular classes, late-start electives) without clearing or altering existing subjects, recurring timetables, or past attendance records.
- **Effective Date Tracking (`effectiveFrom`)**:
  - Supports top-level or per-subject `"effectiveFrom": "YYYY-MM-DD"`. Attendance calculations and schedule displays before the effective date automatically disregard the new subject.

---

### 3. Special One-Off Classes JSON Import
- **Dedicated Special Class Schema**:
  - Import single-date makeup, rescheduled, or extra classes directly via JSON (`"specialClasses": [{ "subject": "...", "date": "YYYY-MM-DD", ... }]`).
  - Automatically parses single dates, infers the day of the week, and flags slots as extra classes (`isExtra: true`).
- **Intelligent Merging**:
  - Classes for existing courses merge directly into the subject's schedule, while new courses are automatically created with unique colors and acronyms.

---

### 4. Dedicated AI Prompts & In-App JSON Templates
- **4 Precision AI Prompts**:
  - Built-in prompts tailored for LLMs to generate valid JSON: Master Timetable, Electives Only, Mid-Semester Subjects, and Special Classes Only.
- **One-Touch Template Copying**:
  - Enhanced format guide in the Timetable Import screen with chip-selectable categories and instant clipboard copying for prompts, JSON schemas, and CSV templates.

---

### 5. Unified Native Device Calendar Engine & Parallel Deletion
- **Zero Rate Limits & Instant Local Sync**:
  - Unified all calendar synchronization into the native Android Device Calendar provider (`device_calendar_plus`).
  - Completely eliminates Google Cloud API rate limits (`403 Rate Limit Exceeded` / `429 Too Many Requests`), OAuth verification hurdles, and slow sequential network uploads. Android's background sync adapter automatically handles uploading events to Google Calendar and Outlook in the cloud.
- **Interactive Calendar Account Picker on Toggle**:
  - Switching Calendar Sync to ON prompts you with an interactive account selection dialog showing all writable Google, Outlook, and local device calendars. You choose exactly which calendar receives your timetable before any sync starts.
- **Concurrent Worker Pool for Event Deletion**:
  - Calendar event deletion executes across a high-throughput **5-worker concurrent pool**, clearing synced events in seconds instead of half a minute.
- **High-Contrast Dark Mode Progress Bar**:
  - Re-styled the modal progress dialog with a clear, high-contrast progress fill and subtle background track, ensuring visual fill progress is prominently visible in dark mode.
- **Full Interruption Shield (`PopScope`)**:
  - Enforced strict back-navigation protection (`PopScope(canPop: false)`) on both the screen and progress modal during active sync and deletion, preventing incomplete or desynchronized states.
- **Background Completion Notification**:
  - An automated system status bar notification confirms when your timetable synchronization finishes.

---

### 6. Native Maps App Redirection & Smart Coordinate Parser (Zero API Costs)
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

### 7. Streamlined Interactive Tutorial
- **Distraction-Free Onboarding**:
  - Replaced the intimidating numeric step counter (`"STEP 1 OF 9"`) with a sleek, minimalist `"QUICK GUIDE"` chip.
  - Significantly reduces onboarding drop-off and encourages new users to explore key app interactions naturally.

---

### 8. Dedicated Google Drive Cloud Backup Screen
- **Exclusive Google Cloud Hub**:
  - Replaced the generic Google Integrations screen with a focused **Google Drive Backup** screen (**More > Google Drive Backup**).
  - Google Sign-In and Sign-Out are strictly exclusive to Google Drive Cloud Backup, cleanly separating cloud storage from calendar synchronization.

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

### 3. Clean Build Number Display (Architecture Offset Stripping)
- **Automatic ABI Prefix Normalization**:
  - When building split-per-ABI APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`), Android package tooling injects architecture offsets (`+2000`, `+1000`, `+3000`) into the internal `versionCode`.
  - Added automated build number normalization (`AppUpdate.cleanBuildNumber` / `AppUpdate.normalizeBuildNumber`) across the More tab, in-app update comparisons, and diagnostic report logs so users consistently see their true clean build number (e.g., `Build 33` instead of `Build 2033`).

---

### 4. High-Speed Parallel Calendar Deletion & Differential Engine
- **Parallel Deletion Acceleration**:
  - Deleting synced events when toggling off Google Calendar sync or switching device calendars now runs in parallel with 5 concurrent workers, slashing deletion time from 30+ seconds down to a few seconds.
- **Content-Hash Diffing**:
  - 64-bit FNV-1a content hashing ensures unchanged slots make **0 API calls** during regular sync cycles.
- **Two-Tier Guaranteed Deletion**:
  - Cleanly purges both tracked SQLite events and scans for orphaned instances, reporting live progress percentages throughout the process.

---

### 5. Strict Permission Hardening & Third-Party Library Cleanup
- **Elimination of Unrequired Permissions**:
  - Audited and stripped unneeded camera, photo, video, audio, and storage permissions injected by third-party packages.
  - Completely removed the `open_filex` dependency and replaced it with native Android `FileProvider` intent dispatching for previewing exported files (PDF, CSV, JSON) and running in-app APK update installation.
  - Enforced strict `tools:node="remove"` rules in `AndroidManifest.xml` to permanently block `CAMERA`, `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_MEDIA_AUDIO`, `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`, and `RECORD_AUDIO` from being merged into the final build.

---

### 6. Change-Gated Precision Local Backups
- **No Redundant Backups**:
  - Local backups are now strictly gated on genuine database modifications (`last_data_modified_timestamp_ms > last_local_backup_timestamp_ms`). If no attendance or subjects were modified during your session, redundant backups are skipped.
- **Optimized Background WorkManager Tasks**:
  - Removed duplicate midnight local backups since local auto-backups execute 5 minutes after session changes. The midnight background task is now strictly dedicated to Google Drive cloud backups.
---

## 📥 Installation

1. Download **AttendMate-v2.4.0.apk**
2. Install directly over your existing app (all subjects, logs, and settings are preserved)
3. Requires Android 7.0 (API 24) or higher

---

*Thank you for using AttendMate! Stay on top of your attendance without the guesswork.*
