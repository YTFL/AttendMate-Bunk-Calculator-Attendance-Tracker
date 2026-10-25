# AttendMate 2.3.0 — Release Notes

**Release Date:** 2026-10-25  
**Version:** 2.3.0  
**Platform:** Android  
**Minimum Android Version:** 7.0 (API 24)

---

## 🚀 AttendMate 2.3.0 Update

AttendMate 2.3.0 introduces one-off extra / makeup class tracking directly into daily schedules, predictive support for factoring pre-marked future lectures and holidays into the Bunk Calculator, alongside continuous refinements, performance enhancements, and codebase modernizations.

---

## 🚀 New Features & Enhancements

- **Consider Pre-Marked Future Lectures in Bunk Calculator** ([#3](https://github.com/YTFL/AttendMate-Bunk-Calculator-Attendance-Tracker/issues/3), [@purval26](https://github.com/purval26)):
  - Students can now factor future pre-marked classes (attended, absent, or cancelled holidays) into the Bunk Calculator ("What-If Calculator") and Bunk Meter instead of treating them as undecided future classes.
  - **Accurate Remaining & Safe Bunk Metrics**: Pre-marked attendance directly credits attended or missed classes towards target thresholds, while pre-marked holidays and cancellations are deducted from remaining class counts rather than incorrectly inflating them.
  - **Toggle & Preference Control**: Easily enable or disable with a dedicated "Consider Future Marked Lectures" checkbox inside the Bunk Calculator sheet or globally in More Settings (defaults to off to preserve standard historical tracking).
  - **Clear Feedback**: The calculation summary clearly indicates when pre-marked future classes are factored in, detailing exact counts of pre-marked present, absent, and cancelled lectures.

- **One-Day Extra / Makeup Classes (Without Changing Weekly Timetable)** ([#4](https://github.com/YTFL/AttendMate-Bunk-Calculator-Attendance-Tracker/issues/4), [#6](https://github.com/YTFL/AttendMate-Bunk-Calculator-Attendance-Tracker/pull/6), [@pranjalaman](https://github.com/pranjalaman)):
  - Students can now seamlessly log a one-off extra, rescheduled, or makeup class on any specific date without touching or cluttering their recurring weekly timetable.
  - **Quick Add from Daily Views**: Tap **Add Extra Class** directly from **Today's Schedule** or from any **Calendar Day Sheet**. Choose the parent subject, start time, and end time (with intelligent default timings suggested based on the day's existing class schedule).
  - **Seamless Attendance & Bunk Tracking**: Extra classes appear with an **Extra** badge, support standard right/left swipe gestures for Present and Absent, can be marked as Holiday, and directly count towards that subject's overall attendance, bunk calculations, and required class targets.
  - **Conflict & Overlap Prevention**: Rejects time slots that overlap with existing scheduled lectures on that date.
  - **Non-Destructive Deletion**: Tap the delete icon on an extra class card to remove only that specific one-off slot and its attendance log—preserving the parent subject and regular weekly schedule.
  - **Timetable Sync & Edit Protection**: Editing a subject or syncing/merging timetables via Classroom Timetable Sync keeps all existing one-off extra classes intact.

- **Developer Portfolio ("More apps by me") in More Tab**:
  - Added a dedicated "More apps by me" entry under Help & Support on the More tab, allowing users to explore other applications and tools by the developer at [ytfl.github.io](https://ytfl.github.io/).
  - Equipped with standard external URL confirmation dialog protection before launching in the browser.

---

## 🐛 Bug Fixes & Refinements

- **Attendance Notification Synchronization & Overhaul**:
  - **Suppress Completed Reminders When Already Marked**: Fixed an issue where end-of-class attendance reminders ("Mark attendance - Class ended: [Subject]") still popped up after class completion even though the student had already marked attendance earlier in the day or during class.
  - **Pre-Class Room & Location Reminders Preserved**: 5-minute pre-class notifications ("Next Class: [Subject] in [Block], [Room]") continue to be reliably delivered even if attendance is marked in advance, ensuring students never miss their classroom navigation details.
  - **Next-Instance Recurrence Scheduling**: Fixed an issue where marking today's class caused the scheduler to skip future weeks entirely. The scheduler now automatically looks ahead to the next unmarked class occurrence (e.g. next week) and schedules it into Android AlarmManager.
  - **Notification ID Collision Fix for Extra & Special Classes**: Replaced simple weekday-based hash IDs with complete slot-key based stable hashing (`end-[subjectId]-[slotKey]` and `pre-[subjectId]-[slotKey]`), preventing one-day extra classes on specific dates from colliding with or overwriting regular weekly timetable class alarms.
  - **Eliminated Duplicate Action Confirmations**: Resolved an issue where tapping "Mark Present" or "Mark Absent" on the notification action button triggered two confirmation notifications in the foreground.
  - **Background Geofence Task Cleanup**: Manually marking attendance now automatically cancels pending 5-minute delayed background GPS check tasks (`geofenceCheckTask`), conserving battery and background location permissions.
  - **App Resume & Unmarking Synchronization**: Restored automatic notification rescheduling when attendance is unmarked before class ends, and synchronized schedules on app resume.

- **Calendar Synchronization & Deletion Engine Overhaul**:
  - **Eliminated Google Calendar API Quota Exhaustion**: Implemented local state tracking and 64-bit FNV-1a content hash diffing (`google_calendar_events` table in SQLite v9). Unchanged timetable slots are skipped completely (**0 API requests**). Modified slots update directly using their cached Google Event ID (**exactly 1 API request**), eliminating the previous 3-request penalty of blind import collisions.
  - **Calm Auto-Sync Debouncing**: Extended the attendance auto-sync debounce window from 1.5 seconds to 8 seconds, enabling students to log all classes for the day without spamming the cloud API or tripping Google's burst write limits (`Calendar usage limits exceeded`).
  - **Explicit Calendar Sync Opt-In**: Google Calendar synchronization now strictly defaults to off unless explicitly enabled, ensuring that signing into Google for Google Drive backups never triggers background calendar synchronization unintentionally.
  - **Guaranteed Local & System Calendar Deletion**: Fixed an issue where disabling Device Calendar sync or switching calendar targets bypassed event deletion in debug/testing builds due to a missing force flag. Introduced two-tier guaranteed cleanup: deletes tracked SQLite records and directly inspects the device calendar (`plugin.listEvents`) to cleanly purge all events stamped with AttendMate metadata.
  - **Resolved Duplicate Calendar Entries**: Added execution mutexes (`_isSyncInProgress`) across both Google and Device calendar sync routines to eliminate race conditions. Added a mutual exclusivity warning banner in Calendar Sync settings when both Google REST API sync and Device Calendar sync target the same Google account.
  - **Boundary-Free Deletion & Pagination**: Removed restrictive semester date range filters on recurring master events and added complete pagination (`pageToken`) loops across Google Calendar queries, ensuring shifts to semester start/end dates never leave orphaned calendar entries behind.

---

1. Download **AttendMate-v2.3.0.apk**
2. Install directly over your existing app (all subjects, logs, and settings are preserved)
3. Requires Android 7.0 (API 24) or higher

> **Note on Architectures:** The official release APK provided on the GitHub Releases page is built for `arm64-v8a` (64-bit ARM). If your device or emulator requires a different architecture (`armeabi-v7a` or `x86_64`), all build restrictions have been removed—you can simply run the build command on your own to generate your target split APK.

---

*Thank you for using AttendMate! Stay on top of your attendance without the guesswork.*