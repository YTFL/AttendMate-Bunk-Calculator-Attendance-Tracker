# AttendMate 2.3.0 — Release Notes

**Release Date:** In Development
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

---



## 📥 Installation & Upgrade

1. Download **AttendMate-v2.3.0.apk**
2. Install directly over your existing app (all subjects, logs, and settings are preserved)
3. Requires Android 7.0 (API 24) or higher

> **Note on Architectures:** The official release APK provided on the GitHub Releases page is built for `arm64-v8a` (64-bit ARM). If your device or emulator requires a different architecture (`armeabi-v7a` or `x86_64`), all build restrictions have been removed—you can simply run the build command on your own to generate your target split APK.

---

*Thank you for using AttendMate! Stay on top of your attendance without the guesswork.*