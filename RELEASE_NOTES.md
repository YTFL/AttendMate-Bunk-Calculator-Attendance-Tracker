# AttendMate 2.2.0 — Release Notes

**Release Date:** September 11, 2026  
**Version:** 2.2.0  
**Platform:** Android  
**Minimum Android Version:** 7.0 (API 24)

---

## 🚀 AttendMate 2.2.0 Update

AttendMate 2.2.0 delivers a major feature expansion and performance overhaul. Highlights include a Live Classroom Timetable synchronization system powered by Google Drive, unified Classroom Timetable & Sharing under Features & Integrations, a centralized Google Integrations hub with private Google Drive cloud backups and smart login restoration, multi-day special classes supporting arbitrary date selections, mid-semester historical attendance import (CSV & JSON), an external URL redirection confirmation dialog, 5-minute smart app-close backups, in-app GitHub Discussions with launch announcement popups, Keep Android Open awareness with FreeDroidWarn integration, instantaneous screen loading across integration screens, manufacturer background optimization guidance, demo swipe haptics, and complete elimination of tab-switching UI flickers via `IndexedStack`.

> 🔮 **Looking Ahead:** A comprehensive app UI overhaul featuring a modern translucent design and floating dock navigation is currently in active development and will be arriving in the upcoming minor release!

---

## 🚀 New Features & Enhancements

- **Live Classroom Timetable Sync & Sharing**: Synchronize class timetables live across classmates or share semester structures directly with friends. A Class Representative (CR) hosts the class timetable on Google Drive and shares a unique Class Code or link. Whenever the CR updates the timetable, changes propagate to all subscribed classmates seamlessly.
  - **Zero Login Friction for Classmates**: Classmates do not need a Google account or special permissions—the app fetches updates anonymously via direct HTTP GET.
  - **Safe Non-Destructive Merging**: Strictly protects existing student attendance records. When a schedule changes (timings, rooms, blocks, or newly added subjects), the timetable updates while all individual attendance counts, dates, and bunk meter statistics remain 100% intact.
  - **Customizable Class & CR Names**: Class Reps can name the timetable anything (e.g., *"CSE 3rd Sem - Section A"*, *"Mechanical 2026 Batch"*) and set their display name.
  - **Auto-Check on App Open**: Subscribed apps automatically check for schedule updates on app resume (rate-limited to once every 10 minutes) and prompt users with a 1-tap update banner.
  - **Dedicated `AttendMate` Google Drive Subfolder**: Both private cloud backups and live timetable files are automatically organized inside a dedicated `Google Drive > AttendMate` folder, keeping the user's root Drive completely clean. Legacy backups in the root are automatically migrated.
  - **Unified Management Dashboard**: Centrally accessible under `Settings > Features & Integrations > Classroom Timetable & Sharing` with real-time status badges (`Hosting Live (vX)`, `Subscribed (vX)`), one-tap code copy/native share sheet, manual update checks, auto-check toggle, one-time JSON file export & import options, and disconnect controls. Main Semester screen keeps Semester Parameters collapsed by default for a clean, distraction-free view.
- **Centralized Google Integrations Hub**: Added a dedicated Google Integrations screen (`More > Features & Integrations > Google Integrations`) unifying Google Account authentication, Google Calendar synchronization, and Google Drive cloud backups. Secondary screens feature streamlined toggles with inline sign-in, while user emails are kept strictly to the main integrations screen.
- **Google Drive Cloud Backup & Smart Login Restore**: Protect your entire attendance state in your private Google Drive app storage with a single JSON backup (`attendmate_cloud_backup.json`). Backups run automatically once daily at midnight (strictly avoiding rapid battery-draining cloud syncs). When signing in, AttendMate automatically detects existing Google Drive backups and offers instant one-tap restoration.
- **Special Multi-Day Classes**: Upgraded Special Classes from single-day to multi-day. Select single or multiple dates (contiguous or with arbitrary gaps) using an interactive calendar picker and date chips, and batch-assign timetable slots across all chosen dates at once.
- **Unified Import Hub & Dual-Tab Experience**: Consolidated timetable import/export and past attendance imports into a single, cohesive `UnifiedImportScreen` with dedicated tabs for **Timetable** and **Attendance**.
  - **Context-Aware Navigation**: Navigating via the import action on the Subjects tab opens directly to Timetable Import & Export, while Semester Details and Bunk Meter screens route directly to Attendance Import & Baseline settings.
  - **Redesigned Timetable Import & Export Screen UI**: Streamlined the timetable import interface with a clean, focused layout. Removed verbose inline import instruction blocks and static format references in favor of a modern, uncluttered UI. Balanced the **View Format** and **Parse & Preview** action buttons to take exactly 50% width each in the same row.
  - **Inline Dynamic Paste & Clear Controls**: Replaced bottom standalone clear buttons with a smart, embedded in-box button inside the top-right corner of the text container across both Timetable and Attendance import tabs. Toggles dynamically between a compact **Paste** icon button when empty and a red **Clear** icon button once text is pasted or typed.
  - **Modernized Format Dialog with AI Prompts & CSV Summaries**: Moved timetable format references and attendance guidance into an interactive **View Format** dialog right beside the Parse & Preview button. Features 5 organized tabs including a prominent **AI Prompt (Recommended)** guide for effortlessly converting raw college portal schedules or attendance sheets with LLMs, plus comprehensive JSON and CSV summary schemas.
  - **In-Preview Subject Editing Across Timetable & Attendance**: Added direct subject editing directly from the Parse & Preview cards:
    - In **Timetable Import**, an inline edit button (`Icons.edit_outlined`) lets users modify subject name, acronym, room, block, target attendance percentage, and class schedule slots before applying changes.
    - In **Attendance Import**, users can edit parsed class figures (total classes held and classes attended) for any individual subject right in the comparison preview before confirming.
  - **Inline Attendance Parse & Preview with Baseline Comparison**: Replaced modal popup dialogs with an inline preview section rendered directly at the bottom of the screen (mirroring the Timetable Import experience). Displays side-by-side **Current** vs. **Imported** class metrics with percentage delta badges (`+X.X%`), unmatched subject warnings, and a segmented mode toggle to apply data as a **Manual Attendance Baseline** or as individual **Class Logs**.
- **Bunk Meter Screen Quick-Action Badges**:
  - **Icon-Only Manual Baseline**: Collapsed the wide manual baseline badge into a clean, compact icon button (`Icons.tune_rounded`), removing unnecessary text labels while preserving full baseline explanation, counting start dates, and reset capabilities on tap.
  - **Projected Leave Impact Quick-Action**: Converted the bulky "Projected (After Leave)" card banner into a lightweight, clickable icon button (`Icons.event_available_outlined`) right beside the manual baseline button, opening a detailed leave impact dialog displaying projected attendance after planned leaves on tap.
- **Historical Attendance Import via File & Direct Paste**: Seamlessly switch to AttendMate mid-semester by importing your past attendance records from other apps, spreadsheets, or college ERP portals. Upload a file or directly paste JSON/CSV text (with one-tap clipboard paste). The parser automatically strips markdown code fences and handles root wrappers, matching subjects flexibly by name, acronym, or code.
- **Smart 5-Minute App-Close Backup**: Backs up your data 5 minutes after app exit **only if changes occurred during that session**. Reopening the app without making modifications preserves the pending timer without delay or unnecessary resets. When the backup finishes, a system notification confirms that your attendance data has been safely saved.
  - **Diagnostic Event Logging**: Detailed logs record every phase—initial 5-minute scheduling on app exit, session modifications that mark the timer for reset, and completion timestamps.
- **Reliable Google Drive Midnight Cloud Sync**: Fixed automatic midnight Google Drive cloud backups to ensure reliable background execution without hanging headless isolates.
  - **Silent Background Authentication**: Silent auth bypasses interactive login dialogs when running in headless background tasks, preventing tasks from crashing or hanging.
  - **Non-Restrictive WorkManager & WakeLock**: Configured non-restrictive constraints and added Android `WAKE_LOCK` permission so scheduled midnight backups execute reliably even under aggressive battery management.
  - **Comprehensive Background Logging**: Logs every execution step, file upload result, or skip reason (e.g. cloud sync disabled, no unbacked changes) directly into the Diagnostics Log.
- **GitHub Discussions & Launch Announcements**: Browse community discussions, questions, and ideas directly inside AttendMate with category filtering and offline caching. When an official update or announcement is posted on GitHub, AttendMate notifies you on app launch with an interactive popup dialog.
- **Keep Android Open & FreeDroidWarn Awareness**: Added a dedicated awareness hub under `Help & Support` addressing the upcoming January 2027 Android sideloading restrictions. Features direct links to sign the Change.org petition, visit `keepandroidopen.org`, explore F-Droid, and includes `FreeDroidWarn` native integration to alert users when OS upgrades threaten sideloading freedoms.
- **Instantaneous Screen Loading**: Google Integrations, Semester Backup, and GitHub Discussions open immediately without full-screen loading spinners. Local preferences and cached items render instantly on frame 0, while cloud operations run non-blockingly in the background with a top progress indicator.
- **Manufacturer Restrictions & Battery Optimization**: Added OEM background restrictions guidance under Background Access with manufacturer-specific tips (Xiaomi, Samsung, OnePlus, Huawei, etc.) and a direct shortcut to `dontkillmyapp.com` styled with a clean neutral monochrome palette.
- **Locations & Geofencing Header Polish**: Replaced verbose legend chips on the Location Manager screen with clear, informative guidance explaining that geofencing checks attendance within 25m of configured locations.
- **Semester Parameters Layout Polish & Collapsed View**: Moved the attendance target percentage slider and value to its own dedicated row, and set Semester Parameters to start collapsed by default for streamlined viewing.
- **Projected Leave Breakdown Cleanup**: Removed redundant repeated date stamps and labels ("as of [date]", "projected after leave") across breakdown titles and status cards, retaining a single clean date header.
- **Demo Swipe Card Haptic Feedback**: Added tactile vibration feedback to swipe gestures and holiday toggle controls in the Swipe Actions customizer.
- **Settings Screen Restructuring & Subtext Cleanup**: Moved Background Access into the *System* section, positioned *Privacy & Terms* below *System*, removed redundant "Enabled/Disabled" subtext on Automatic Backups, and optimized the Support dialog so "Star My Repo" receives maximum width and visibility.
- **Universally Clickable Markdown Links**: All links rendered across markdown views—including web URLs, GitHub repositories, and `mailto:` email addresses—are now interactive and open their system handlers via `MarkdownLinkHelper`.
- **Expanded Setup Guide**: Expanded the in-app Setup Guide to 22 comprehensive chapters covering Google Integrations, Historical Attendance Import (with one-tap AI prompt copy), Multi-Day Special Classes, Discussions, and Keep Android Open.
- **Adaptive & Round Launcher Icons with Standout Transparent Drawables**:
  - **Dark-by-Default Aesthetic**: Standard and round launcher icons consistently sport the signature AttendMate dark background (`#121212`) with the crisp white calendar drawing across both light and dark system modes.
  - **Native Round Icon Support (`android:roundIcon`)**: Configured full round icon support in `AndroidManifest.xml` alongside modern adaptive icon XMLs (`res/mipmap-anydpi-v26/`) and smooth anti-aliased round icons across all screen densities.
  - **Direct Transparent Drawables for Launchers & Icon Packs**: `@drawable/ic_launcher` and `@drawable/ic_launcher_foreground` now point directly to the isolated, transparent-background emblem with zero background box/card, enabling custom launchers (Nothing Launcher, Nova, Lawnchair, Niagara, Smart Launcher) and icon pack creators (Icon Pack Studio) to cleanly extract and theme the calendar emblem without black/white box artifacts.
  - **Material You Dynamic Theming (Android 13+)**: Added `@drawable/ic_launcher_monochrome` across all densities for native Monet wallpaper-based dynamic color theming.
  - **Safe-Zone Compliance**: Centered and scaled the emblem within Android's 66dp safe zone (out of 108dp), guaranteeing zero clipping across circular, squircle, pebble, or teardrop launcher masks.
- **Multi-ABI Support & Split Build Automation**: Removed all `arm64-v8a` build restrictions from Gradle. AttendMate now compiles cleanly across all Android architectures (`armeabi-v7a`, `arm64-v8a`, and `x86_64`) with split-per-ABI builds supported by default.
  - *Note on Releases:* The official pre-built APK on the GitHub Releases page will continue to be the **64-bit ARM (`arm64-v8a`)** version. If you require a different architecture (such as 32-bit ARM or x86_64), you can now build it directly from source using `flutter build apk --split-per-abi --release --obfuscate --split-debug-info=build/app/outputs/symbols` as all ABI restrictions have been removed.

---

## 🐛 Bug Fixes & Refinements

- **Background Auto-Backup Failure (`MissingPluginException`)**: Fixed an issue where background WorkManager auto-backups failed with `MissingPluginException` for `writeBackupFile` when the app was closed. Migrated local backup file operations and Storage Access Framework (SAF) tree URI handling into a dedicated Flutter plugin (`attendmate_storage`), guaranteeing native platform channel registration on headless background isolates without requiring an active UI Activity.
- **Aggressive UI Refresh & Flicker Elimination**:
  - Replaced bottom navigation tab rebuilds with `IndexedStack` in `HomeScreen`, preserving screen states, scroll positions, and form inputs when switching tabs.
  - Eliminated an infinite post-frame rebuild loop in `CalendarScreen.build()`.
  - Removed duplicate listener cascade in `SubjectProvider` where attendance changes repeatedly triggered double-rebuilds across all listening widgets.
  - Replaced disruptive full-screen loading spinners with in-place indicators in `LeavePlannerScreen` and `DiagnosticsLogScreen`.
- **Legal Documentation Update**: Updated Privacy Policy and Terms of Service (both markdown and web HTML) to document Google Drive API scopes (`drive.file`) and updated developer contact phrasing to "Contact me at".

---

## 📥 Installation & Upgrade

1. Download **AttendMate-v2.2.0.apk**
2. Install directly over your existing app (all subjects, logs, and settings are preserved)
3. Requires Android 7.0 (API 24) or higher

> **Note on Architectures:** The official release APK provided on the GitHub Releases page is built for `arm64-v8a` (64-bit ARM). If your device or emulator requires a different architecture (`armeabi-v7a` or `x86_64`), all build restrictions have been removed—you can simply run the build command on your own to generate your target split APK.

---

*Thank you for using AttendMate! Stay on top of your attendance without the guesswork.*