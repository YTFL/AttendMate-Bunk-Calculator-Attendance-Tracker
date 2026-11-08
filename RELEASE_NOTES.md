# AttendMate 2.4.0 — Release Notes

**Release Date:** 2026-11-08  
**Version:** 2.4.0  
**Platform:** Android  
**Minimum Android Version:** 7.0 (API 24)

---

## 🚀 AttendMate 2.4.0 Update

AttendMate 2.4.0 brings major performance enhancements to calendar synchronization, fully replaces the external Google Maps SDK with phone-default map app integration and smart coordinate parsing, guarantees reliable midnight Google Drive backups, and refines pre-class notification rules for absent and holiday classes.

---

## 🚀 New Features & Enhancements

- **Native Maps App Redirection & Smart Coordinate Parser**:
  - Completely replaced the Google Maps SDK and paid Maps API with native maps app integration, eliminating proprietary API requirements and reducing app bloat.
  - Added an "Open Default Maps App" button that launches the user's preferred native maps application (`geo:0,0?q=`).
  - Added an intelligent coordinate parser supporting standard decimal coordinates (`lat, lng`), DMS format (Degrees Minutes Seconds), Google Maps share URLs (`goo.gl`, `?q=`, `/@lat,lng`), and dropped pin clipboard text with one-tap clipboard paste and live coordinate preview.

- **High-Speed Calendar Synchronization & Progress Protection**:
  - Re-architected schedule slot syncing to execute in a 5-worker concurrent pool, speeding up calendar synchronization up to 5x mid-semester.
  - Added a non-dismissible `SyncProgressDialog` displaying exact sync percentage (`%`) and real-time subject slot progress.
  - Protected synchronization with `PopScope(canPop: false)`, preventing accidental cancellation or partial synchronization when the user taps back.
  - Added an automated system status bar notification upon calendar sync completion.

- **Streamlined Interactive Tutorial**:
  - Replaced the numerical step count ("STEP X OF Y") with a discreet "QUICK GUIDE" chip to ensure a frictionless, distraction-free onboarding experience.

---

## 🐛 Bug Fixes & Refinements

- **Google Drive Midnight Backup Reliability**:
  - Fixed an issue where local auto-backups clearing the dirty flag earlier in the day could cause the midnight Google Drive sync to skip. Added independent modification timestamp tracking (`last_data_modified_timestamp_ms` vs `last_google_drive_backup_timestamp_ms`).
  - Updated WorkManager periodic backup policy to `ExistingPeriodicWorkPolicy.keep` with `NetworkType.connected` constraints so the 24-hour cycle is never reset upon app launch.
  - Added an app startup catch-up routine that automatically executes any missed backups if the device was asleep or in battery doze at midnight.

- **Smart Pre-Class Notification Filtering**:
  - Automatically suppress 5-minute pre-class room reminders if a class is marked absent or holiday (cancelled), eliminating unnecessary alarms for missed or cancelled classes.
  - Pre-class reminders remain active for classes marked present (attended) or unmarked.

---
