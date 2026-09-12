# Changelog

All notable changes to AttendMate will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [2.2.0] - 2026-09-11

### Added
- **Live Classroom Timetable Sync & Sharing**: Synchronize class timetables live between classmates using Google Drive as a decentralized relay without requiring any centralized server, or share semester structures directly via one-time JSON files. A Class Representative (CR) hosts the class timetable and shares an alphanumeric Class Code or link. Whenever the CR updates the timetable, changes propagate to all subscribed classmates seamlessly.
  - **Zero Login Friction for Classmates**: Classmates do not need a Google account or any special permissions—the app fetches updates anonymously via direct HTTP GET.
  - **Safe Non-Destructive Merging**: Strictly protects existing student attendance records. When a schedule changes (timings, rooms, blocks, or newly added subjects), the timetable updates while all individual attendance counts, dates, and bunk meter statistics remain 100% intact.
  - **Customizable Class & CR Names**: Class Reps can give the timetable any custom name (e.g., *"CSE 3rd Sem - Section A"*, *"Mechanical 2026 Batch"*) and set their display name.
  - **Auto-Check on App Open**: Subscribed apps automatically check for schedule updates on app resume (rate-limited to once every 10 minutes) and prompt users with a 1-tap update banner.
  - **Dedicated `AttendMate` Google Drive Subfolder**: Both private cloud backups and live timetable files are automatically organized inside a dedicated `Google Drive > AttendMate` folder, keeping the user's root Drive completely clean. Legacy backups in the root are automatically migrated upon next backup.
  - **Unified Management Dashboard**: Centrally accessible under `Settings > Features & Integrations > Classroom Timetable & Sharing` with real-time status badges (`Hosting Live (vX)`, `Subscribed (vX)`), one-tap code copy/native share sheet, manual update checks, auto-check toggle, one-time file export & import options, and disconnect controls. Main Semester screen keeps Semester Parameters collapsed by default for a clean, distraction-free view.
- **Centralized Google Integrations Hub**: Added a dedicated Google Integrations screen (`More > Features & Integrations > Google Integrations`) unifying Google Account authentication, Google Calendar sync, and Google Drive cloud backups. Secondary screens use clean toggles with inline sign-in, while user emails are kept strictly to the main integrations screen.
- **Google Drive Cloud Backup & Smart Login Restore**: Protect your entire attendance state in private Google Drive app storage with a single JSON backup (`attendmate_cloud_backup.json`). Backups run automatically once daily at midnight (strictly no rapid battery-draining rolling syncs). Automatically checks for existing cloud backups upon sign-in and prompts for instant restoration.
- **Special Multi-Day Classes**: Upgraded Special Classes to support selecting single or multiple dates (with or without gaps in between) and batch-assigning time slots across all chosen dates anytime.
- **Unified Import Hub & Dual-Tab Experience**: Consolidated timetable import/export and past attendance imports into a single, cohesive `UnifiedImportScreen` with dedicated tabs for **Timetable** and **Attendance**.
  - **Context-Aware Navigation**: Navigating via the import button on the Subjects tab defaults directly to Timetable Import & Export, while Semester Details and Bunk Meter screens route directly to Attendance Import & Baseline settings.
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
- **Historical Attendance Import via File & Direct Paste**: Import past attendance records directly by either uploading a file or pasting JSON/CSV content (with one-tap clipboard paste). The parser automatically strips markdown code blocks, unwraps common root keys, and matches subjects flexibly by name, acronym, or code.
- **External URL Redirection Confirmation Popup**: Added a security confirmation modal across all external link interactions displaying the destination URL in a monospace box with "Back" and "Continue" options before leaving AttendMate. Very long URLs (such as bug report diagnostics) are cleanly truncated to 250 characters with ellipses.
- **5-Minute Smart App-Close Backup**: Automatically backs up attendance data 5 minutes after leaving the app only if changes occurred during that session. Reopening the app without modifications preserves the scheduled timer without unnecessary resets. A confirmation notification is posted once the backup is safely created.
  - Diagnostic logs record timer scheduling, session change resets, and backup completion events.
- **Reliable Google Drive Midnight Cloud Sync**: Fixed automated midnight cloud sync execution in background WorkManager isolates.
  - Silent authentication prevents headless background tasks from freezing or attempting interactive UI popups.
  - Added `WAKE_LOCK` permission and non-restrictive WorkManager constraints so scheduled background tasks wake the device as required.
  - Diagnostic logs record every sync step, file upload confirmation, or skip reason.
- **In-App GitHub Discussions & Launch Announcements**: In-app discussion browser with category filtering, offline caching, and markdown reader. Checks on launch and shows an announcement dialog popup exclusively for new unseen posts categorized as Announcements.
- **Keep Android Open & FreeDroidWarn Awareness**: Added an awareness hub under `Help & Support` addressing the upcoming January 2027 Android sideloading restrictions with links to the Change.org petition, `keepandroidopen.org`, F-Droid, and native FreeDroidWarn integration.
- **Manufacturer Background Restrictions & dontkillmyapp.com Guide**: Added device-specific guidance for OEM background killers (Xiaomi, Samsung, OnePlus, etc.) under Background Access, including a direct link to `dontkillmyapp.com` styled with a clean neutral monochrome palette.
- **Demo Swipe Card Haptic Feedback**: Added tactile vibration feedback to swipe gestures and the holiday toggle button in the Swipe Actions customizer.
- **Universally Clickable Markdown Links**: All links rendered across markdown views—including web URLs, GitHub repositories, and `mailto:` email addresses—are now interactive and open their system handlers via `MarkdownLinkHelper`.
- **Adaptive & Round Launcher Icons with Standout Transparent Drawables**:
  - **Dark-by-Default Aesthetic**: Standard and round launcher icons consistently sport the signature AttendMate dark background (`#121212`) with the crisp white calendar drawing across both light and dark system modes.
  - **Native Round Icon Support (`android:roundIcon`)**: Added `android:roundIcon` support in `AndroidManifest.xml` with adaptive XML definitions (`res/mipmap-anydpi-v26/`) and smooth anti-aliased round icons across all screen densities.
  - **Direct Transparent Drawables for Launchers & Icon Packs**: `@drawable/ic_launcher` and `@drawable/ic_launcher_foreground` now point directly to the isolated, transparent-background emblem with zero background box/card, enabling custom launchers (Nothing Launcher, Nova, Lawnchair, Niagara, Smart Launcher) and icon pack creators (Icon Pack Studio) to cleanly extract and theme the calendar emblem without black/white box artifacts.
  - **Material You Dynamic Theming (Android 13+)**: Added `@drawable/ic_launcher_monochrome` across all densities for native Monet wallpaper dynamic color theming.
  - **Safe-Zone Compliance**: Centered and scaled the emblem within Android's 66dp safe zone (out of 108dp canvas), ensuring zero clipping across circular, squircle, pebble, or teardrop launcher masks.
- **Expanded Setup Guide**: Expanded the in-app Setup Guide to 22 comprehensive chapters covering Google Integrations, Historical Attendance Import (with one-tap AI prompt copy), Multi-Day Special Classes, Discussions, and Keep Android Open.

### Changed & Improved
- **Instantaneous Screen Loading**: Google Integrations, Semester Backup, and GitHub Discussions now open immediately with in-memory cached state on frame 0, eliminating blocking full-screen loading spinners and running cloud checks in the background with a top progress indicator.
- **Locations & Geofencing Header Polish**: Streamlined the Location Manager screen by replacing the top Active/Inactive legend with clear, informative guidance explaining that geofencing checks attendance within 25m of configured locations.
- **Semester Parameters Layout Polish**: Moved the attendance target percentage slider/display to its own dedicated row for balanced spacing and improved readability.
- **Projected Leave Breakdown Cleanup**: Removed redundant repeated date stamps and labels ("as of [date]", "projected after leave") across breakdown titles and status cards, retaining a single clean date header.
- **Semester Backup Subtext Cleanup**: Removed redundant "Enabled/Disabled" subtext on Automatic Backups and streamlined cloud backup timestamps to show clean dates.
- **Settings Screen Restructuring**: Moved Background Access under the *System* section, positioned *Privacy & Terms* below *System*, and optimized button layout in the Support dialog so "Star My Repo" receives maximum width and full visibility.
- **Multi-ABI Support & Split Build Automation**: Removed the global `arm64-v8a` NDK restriction from Gradle (`build.gradle.kts`), enabling builds across all Android architectures (`armeabi-v7a`, `arm64-v8a`, and `x86_64`). Project build instructions and default build tasks now use `--split-per-abi`. *(Note: The official release APK published on the GitHub Releases page will remain the `arm64-v8a` version; users who need another architecture can build their desired APK directly from source as restrictions are no longer present.)*

### Fixed
- **Background Auto-Backup Failure (`MissingPluginException`)**: Resolved an issue where background WorkManager auto-backups failed with `MissingPluginException` for `writeBackupFile` when the app was closed. Migrated local backup file operations and Storage Access Framework (SAF) tree URI handling into a dedicated Flutter plugin (`attendmate_storage`), ensuring full platform channel registration on headless background isolates without requiring an active UI Activity.
- **Aggressive UI Refresh & Screen Flickering**:
  - Replaced bottom navigation tab rebuilds with `IndexedStack` in `HomeScreen`, preserving screen states, scroll positions, and inputs when switching tabs.
  - Eliminated an infinite post-frame rebuild loop in `CalendarScreen.build()`.
  - Removed duplicate listener cascade in `SubjectProvider` where attendance changes repeatedly triggered double-rebuilds.
  - Replaced disruptive full-screen loading spinners with in-place indicators in `LeavePlannerScreen` and `DiagnosticsLogScreen`.
- **Legal Documentation Update**: Updated Privacy Policy and Terms of Service (both markdown and web HTML) to document Google Drive API scopes (`drive.file`) and updated developer contact phrasing to "Contact me at".

---

## [2.1.0] - 2026-09-01

### Added
- **Card Dropdown Animations for Bunk Meter & Subjects Screens**: Added smooth dropdown expansion/collapse and 180° chevron rotation animations for subject cards across both the Bunk Meter and Subjects screens, matching the dropdown animation behavior of the Semester Parameters card.
- **Scrollable 15-Day Schedule (-7 / +7 Days) with Dynamic Titles & Direct Attendance Marking**: Transformed the main schedule screen into a horizontal swipeable 15-day schedule window (-7 days past, Today, and +7 days upcoming) featuring dynamic title adaptation, direct attendance marking for past days, and dedicated upcoming, leave, and holiday handling for future dates.
- **Interactive Projected Attendance Popup in Semester Details**: Added a projected attendance clickable banner to open a detailed modal dialog displaying:
  - Projected attendance percentage following planned leave.
  - Total classes missed during the leave period.
  - Upcoming classes assumed Present prior to the leave.
  - Continuous classes required after leave: If projected attendance falls below the target percentage, dynamically calculates and displays the exact number of consecutive classes required after the leave to restore attendance to target level.
- **Bunk Calculator (What-If Calculator Sheet) Enhancements**:
  - Added a **Target Date Selector** (defaulting to the end of the semester).
  - Added a **Consider Planned Leaves** toggle option.
  - Dynamically recalculates remaining classes, Must Attend, Can Bunk, and Max simulation stats up to the chosen target date (factoring in planned leave absences when enabled).
- **Unrestricted Background Battery Access Guidance**: Added permission requesting and settings guidance for unrestricted background access. To prevent aggressive Android battery optimization plans from killing background tasks, AttendMate now informs users and provides a direct shortcut to app battery settings to enable unrestricted execution.
- **Manual Baseline Reset & Interactive Tooltip**: Moved manual baseline warning banner on Bunk Meter cards to an interactive, tapable tooltip. Tapping the tooltip displays baseline details and provides a direct option to reset the manual baseline back to auto-calculated values.
- **Future Day Holiday Marking**: Added an option in the calendar view to mark any future date directly as a holiday.
- **Next Immediate Planned Leave Projected Attendance**: Refined projected attendance calculations in Semester details to compute projections specifically for the next immediate upcoming planned leave rather than aggregating all future planned leaves across the semester. Upcoming classes up to the next leave date are assumed Present, while marked classes are dynamically factored in once logged.
- **Class Location Support in Timetable JSON Import**: Updated the timetable JSON import format to include support for importing class-wise locations.

### Fixed
- **Backup Screen UI Refresh Fix**: Fixed an issue where creating, importing, or deleting a backup, or updating the backup folder, caused the entire screen to reload, flash a full-screen loading spinner, and reset the scroll position. The backup list now refreshes seamlessly in place without tearing down the UI.
- **Short of Target Recovery Calculation**: Fixed short-of-target and negative bunkable class calculations to accurately compute and display the exact number of continuous classes that must be attended to recover back to the target attendance percentage.
- **Future Holiday Absence Pre-Marking**: Automatically marks all class sessions as absent in advance for dates designated as holidays, rather than delaying until the holiday date arrives.
- **Removed End-of-Day Automatic Attendance Marking**: Removed automatic end-of-day attendance marking and next app open auto-marking so users retain full manual control over unattended logs.
- **Locked Status Display on Today's Schedule**: Fixed schedule items to properly display locked status when classes fall under a manual baseline or locked state.
- **Aggressive Background Location Fetch Fix**: Resolved aggressive background location polling that caused screen flickering over extended app usage sessions.
- **Calendar Baseline Status & Lock Icon Display**: Fixed calendar view erroneously displaying days prior to a set manual baseline as "Not Marked". Dates prior to baseline now accurately show a locked icon when all classes fall under the baseline, or a mixed status indicator for combination days, displaying "Not Marked" exclusively when a class is genuinely unlogged.
- **Bunk Calculator Manual Baseline Calculation**: Fixed the Bunk Calculator to properly calculate attendance from manual baseline values when set instead of falling back to default values.
- **Bunk Calculator Max Class Increment Guard**: Disabled the `+` increment button in the Bunk Calculator when reaching maximum available classes to prevent calculating beyond total semester class bounds.
- **Pre-Marked Class Notification Suppression**: Prevented sending attendance or class-related notifications if a class session has already been marked as Present, Absent, or Holiday.
- **Mid-Semester Timetable Update**: Fixed mid-semester timetable updating to properly overwrite and clean up old records from the effective date forward.
- **Automatic Backup**: Fixed automatic backup not working in the latest version.
- **Location Registration Logging**: Fixed location registered log showing up for all classes associated with a location whenever location is accessed.
- **Screen Flickering on Location Read**: Fixed screen flickering when trying to read location over extended periods.

---

## [2.0.2] - 2026-08-11

### Added
- **Native Android "Open with AttendMate" File Handler**: Registered AttendMate in Android OS as a handler for `.json` files. Clicking a `.json` file in WhatsApp, File Manager, Downloads, etc., and choosing "Open with AttendMate" will launch the app, automatically detect whether the file is a Full Backup or a Shared Semester, and present the appropriate import/restore prompt.
- **Smart Auto-Restore & Conditional Backup on Folder Selection**: When selecting a backup folder, if existing backups are present in the folder, the app automatically restores the latest backup; if no backups exist, initial backup creation is attempted only if an active semester exists.
- **Auto-Backup Semester Safeguard**: Automatic background backups (`force: false`) check if a semester exists before running and safely skip auto-backup if no semester is created.
- **Direct Data Sharing**: Added direct data sharing with classmates from within the app.

### Fixed
- **Backup Storage Location**: Fixed backup creation so files are saved directly in the user-selected location rather than elsewhere.
- **Location Data Backup**: Fixed backup generation to ensure location data is properly backed up.
- **Planned Holiday Backup**: Fixed backup generation to ensure planned holiday data is saved in backups.
- **Complete Database Clear**: Fixed clear database functionality so location data and saved holiday data are completely deleted.
- **Setup Guide Auto-Scroll**: Fixed guide tutorial navigation to automatically scroll the page until the setup guide section is visible.

---

## [2.0.1] - 2026-08-10

### Added
- **Class-Wise Location Selection**: Added option to select/set classroom location per class slot instead of having only one location per subject.
- **Classroom Details in Notifications**: Pre-class notifications (sent 5 minutes before class) now show the classroom block and room number.
- **Diagnostics Log & GitHub Issue Reporting**: Moved Diagnostics Log under System settings and enabled it for release builds. When an error occurs, users can now directly create a GitHub issue pre-filled with the error log for streamlined bug reporting.

### Fixed
- **Timetable JSON Import Default**: When no subjects are present, importing JSON by default sets up the complete semester timetable instead of updating from a specific date.
- **Text Field Keyboard Focus & Auto-Dismiss**: Removed overly aggressive keyboard auto-dismissal across text fields in the app, properly enabling standard focus and unfocus behaviors.
- **Add/Edit Subject Keyboard Focus**: Fixed aggressive keyboard auto-dismissal on the add/edit subject pages.
- **Location Selector Keyboard Focus**: Fixed aggressive keyboard auto-dismissal when setting locations.
- **Pre-Semester Calendar Access**: Fixed an issue preventing opening or viewing the attendance calendar before the semester start date.

---

## [2.0.0] - 2026-07-22

### Added
- **Geofenced Auto-Attendance & Interactive Google Maps**: Added Location Manager with interactive Google Maps location picker (`google_maps_flutter`), 25m radius geofence visualizer, GPS location capture, clipboard link parsing, and 5-minute post-class low-power background location checking.
- **"What-If" Bunk Calculator**: Added interactive simulator sheet on the Bunk Meter screen to simulate bunking $N$ or attending $M$ future classes with live percentage projections.
- **Leave Planner & External Calendar Sync**: Multi-day/single-day leave planning with automatic deletion of scheduled lectures on Google Calendar & Device System Calendars during leave periods, and automatic restoration on cancellation/present marking.
- **Global Time Picker Preference**: Added global setting under More tab to choose between Material Dialog and Scroll Wheel clock styles across all screens.
- **Rolling Semester Backup System**: Automated 3-backup rolling snapshot redundancy (`backup_latest.json`, `backup_previous.json`, `backup_oldest.json`) and manual JSON export/restore.
- **Interactive Calendar Filtering**: Added status filtering chips to full-semester attendance calendar grid with a quick "Today" return shortcut.
- **Interactive Guided App Tour**: Added game-style spotlight onboarding walkthrough with form interaction pass-through.
- **Setup Guide Expansion**: Added Chapters 11 (Locations), 12 (Bunk Calculator), and 13 (Leave Planner) with direct in-app routing links.
- **Haptic Feedback for Attendance Marking**: Integrated tactile haptic vibration responses when marking or unmarking class attendance states on Today's schedule.
- **Per-Subject Attendance Targets**: Custom attendance target percentage configuration per subject with optional fallback to semester default target.

### Changed & Modernized
- **Attendance Calendar UI Overhaul**: Redesigned calendar UI style and day tile aesthetics for a modernized full-semester overview.
- **Haptic Attendance Target % Slider**: Replaced target percentage text inputs with an interactive slider featuring tactile haptic feedback responses for semester and per-subject targets.
- **Semester Screen Overhaul**: Unified Top Hero Card with date spans, large attendance gauge (`85.4%`), progress bar, collapsible parameters bar, and 2x4 metrics grid.
- **Timetable Import Screen UI Overhaul**: Redesigned import timetable interface for improved visual clarity and easier navigation.
- **Update Class Counts UI Overhaul**: Redesigned class count adjustment screen with modern input fields and clean metric displays.
- **Single-Line Subject Name Truncation**: Restricted subject titles on Today's Schedule and Calendar day cards to 1 line with trailing ellipses (`TextOverflow.ellipsis`) for a uniform, clutter-free UI.
- **Subject Screen Empty State**: Redesigned top-aligned empty state hero card with direct *"Add Your First Subject"* primary button and compact AI suggestion card.
- **Bunkable Calculation Metric**: Switched bunkable count from future projection to a pure current-state formula (`bunkable = floor(totalAttended - targetRatio * totalMarked)`), showing exact current class surplus (+) or short deficit (-).

### Fixed
- **Dark Mode Popup Barrier Fix (App-Wide)**: Fixed invisible dialog/bottom-sheet backdrops across 19 dialogs and 6 bottom sheets in dark mode by applying a clear semi-transparent barrier tint.
- **Notification Action Buttons & Confirmation**: Registered missing `ActionBroadcastReceiver` in `AndroidManifest.xml` so notification buttons respond reliably, updated notification body to show exact subject names, and removed auto-dismiss.
- **Swipe Action & Card Animation Fixes**: Dynamic arrow icon colors matching active `SwipeAction` status on Option B settings and smooth initial offset calculation to eliminate card jumping when swiping mid-animation.
- **Dynamic Gradle `.env` Injection**: Android Gradle automatically injects `MAPS_API_KEY` from `.env` file at build time.

---

## [1.6.2] - 2026-07-17

### Added
- **Preserved Swipe Card State**: Subject cards now slide back smoothly instead of instantly popping back when you perform a swipe action on Today's page or in Settings.

### Changed
- **Smooth Liquid-like Easing**: Attendance swipe-back transition now uses a refined `Curves.easeOutQuint` easing over `450ms` for a fluid, organic, and premium feel.
- **Dependency Cleanup**: Stripped unused dependencies (`fl_chart`, `pie_chart`, `flutter_colorpicker`, `markdown`) from the configuration.

### Fixed
- **Setup Guide Bug**: Fixed a bug where a duplicate "5. Marking Attendance" page was displayed in the onboarding Setup Guide flow.

---


## [1.6.1] - 2026-07-11

### Fixed
- Fixed the Google Calendar Sign-in issue that occurred because of updated Package Name in v1.6.0

---


## [1.6.0] - 2026-07-08

### Added
- **Customizable Swipe Gestures**: Swipe right/left to mark classes as present or absent on Today's schedule. Preferences are easily configured and swappable on conflict in the new settings screen.
- **Integrated Swipe-to-Unmark**: Swipe in the direction of an already active status (e.g. swiping right on a "Present" class when Swipe Right is configured as "Mark Present") to unmark it, avoiding visual clutter.
- **Premium Bounce-Back Physics**: A custom swipe wrapper clamps swipe distance to 25% of the screen width and bounces back smoothly, displaying clean, minimalist, text-free action icons (Check, Close, Undo).
- **Simplified Card Actions**: Replaced the multi-button row on class cards with a single toggle button (Mark Holiday / Unmark Holiday), keeping the interface clean and letting swipe gestures handle attendance marking.
- **Automated Google Calendar Sync**: Replaced manual calendar synchronization with fully automated background sync. The app now triggers calendar updates automatically in the background (debounced at 1.5 seconds to optimize battery and network usage) whenever you add, edit, rename, or delete a subject, declare a holiday, or cancel/unmark a class.
- **Device Calendar Sync**: Integrated device-level calendar synchronization supporting native calendars on Android (such as Samsung Calendar, Outlook, and local device-only calendars).
- **Unified Sync Control Screen**: Added a unified settings panel that allows toggling and force-synchronizing both Google Calendar (online) and Device Calendar (local system).
- **Smart Lab Color Grouping**: Added color grouping logic that identifies related lab and lecture subjects (e.g., "Algorithms" and "Algorithms Lab") by cleaning name suffixes, assigning them the same color automatically in Google Calendar.
- **Linear Probing Color Mapping**: Implemented a linear probing allocation fallback loop for assigning calendar colors. If a subject's nearest theme color is already occupied, the app probes the next available slots sequentially (1-11) to ensure distinct, unique colors.
- **Graceful Label Normalization**: Implemented clean label formatting that replaces repeated emails with clear app references (e.g., `Google Calendar (email)`) and maps offline phone calendars to `My Calendar (Local Offline)` (case-insensitive) to prevent user confusion.
- **Smart Calendar Filtering**: Automatically filters out read-only national holidays and subscription feeds to keep the calendar selection list clean and personal.

### Changed
- **Flexible Account Sign-In**: Removed restrictions requiring semester dates configuration prior to logging in. Users can now sign in and connect their Google Account at any time (sync operations are safely bypassed until semester dates are set).

---


## [1.5.5] - 2026-07-07

### Added
- **In-App Data Protection Disclosures**: Added explicit data security and protection mechanism statements to the bundled in-app Privacy Policy (covering encryption in transit, secure storage, and sandboxing) to satisfy Google's sensitive OAuth scope verification requirements.

### Changed
- **Updated Web Policy Page**: Updated the online version of the Privacy Policy on the verified web domain with identical data protection disclosures.

---


## [1.5.4] - 2026-06-28

### Added
- **In-App Privacy Policy Links**: Added direct, clickable links to the live Privacy Policy and Terms of Service documents in the calendar synchronization settings screen. This ensures compliance with Google OAuth verification requirements.

### Fixed
- **Dynamic Status Card Theme**: Resolved a visual rendering issue in dark mode where the Calendar Sync status card appeared as a solid white block with invisible text due to theme color token overlap. The card and buttons now dynamically adjust their styling and borders to maintain perfect contrast and readability.

---


## [1.5.3] - 2026-06-27

### Added
- **Google Calendar Sync**: Added Google Calendar synchronization. Users can connect their Google account in settings to sync their weekly class schedules and semester calendars automatically, using matching color schemes.
- **Calendar Sync Screen**: Introduced a dedicated sync settings page where users can manage their connection status, check their linked Google account, and force-trigger full synchronization.

### Changed
- **Background Notification Live Sync**: Configured Isolate communication via `IsolateNameServer` (`attendance_action_port`). This notifies the main app state when attendance is recorded from a background notification action, refreshing the UI instantly.
- **Background Action Confirmation**: When marking attendance from notification action buttons, the original reminder notification is dismissed immediately, and a silent confirmation notification is shown instead of forcing the main app to launch.

### Fixed
- **Notification Scheduling Grace Period**: Removed legacy grace-period overrides that caused edge-case timing errors when scheduling reminders for classes starting immediately.

---


## [1.5.2] - 2026-06-26

### Added
- **Clock Style Selector**: Added a new clock style option in More so users can switch between the available clock styles from inside the app.
- **Saved Clock Preference**: The selected clock style is now treated as a user preference, so the app remembers the user's choice instead of forcing a fixed clock layout.

### Changed
- **Older Device Performance**: Optimized the app to reduce unnecessary work on older devices, especially around the main screen and calendar flow.
- **Add/Edit Subject UI**: Refreshed the Add Subject and Edit Subject screens with clearer spacing, control grouping, and a cleaner overall layout.
- **Settings Presentation**: Moved the clock style option into the existing More/settings area so it is easier to find and manage.

### Fixed
- **Notification Reliability**: Fixed notification-related bugs so reminders and alerts stay in sync after edits, refreshes, and app resume.
- **Data Refresh**: Improved app-resume and reload handling so older attendance or subject state is less likely to linger in the UI.
- **UI Consistency**: Cleaned up small state-handling issues that could leave the clock style or refreshed subject screens looking out of date.

---


## [1.5.1] - 2026-04-03

### Added
- **"Copy Timetable To This Day"** in the calendar day-details modal. Users can pick a source date and copy its classes onto a chosen target date.
- Outlined copy button (`Copy Timetable To This Day`) in the day details modal for quick access.

### Changed
- Copied slots are converted into one-day special slots on the target date, and existing schedules are trimmed/merged as needed.
- SubjectProvider now includes `copyDayTimetable()` and `DayTimetableCopyResult` for safe copy/merge of day-specific classes.
- When replacing classes on the target date, attendance records for that date are deleted to keep attendance consistent.
- Subject schedules are saved and notifications/reminders are refreshed after changes.
- Improved adaptive layout for action buttons (Present / Skip / Holiday) on narrow screens.
- Added clear snackbar feedback for success, replacement info, and no-source warnings.

### Fixed
- Defensive checks prevent copying from the same date and notify the user when the source date has no classes.
- UX polish for special one-day classes and locked/manual baseline displays.
- Small bug fixes and defensive improvements around date normalization and modal state handling.

---


## [1.5.0] - 2026-03-29

### Added
- Timetable import now supports **JSON and CSV** formats.
- Import by pasting data or selecting a `.json` or `.csv` file.
- Quick helper buttons: **Copy JSON Reference**, **Copy CSV Reference**.
- Built-in timetable export as **JSON**, **CSV**, or **PDF** (saved to Downloads, PDF supports direct open).
- Special One-Day Class mode in Add/Edit Subject for one-off classes.
- Manual baseline controls in Bunk Meter with **Update Counts Manually**.
- Startup fallback: marks previously unmarked past classes as present when appropriate.
- Updated in-app Setup Guide with new instructions for import/export and special classes.

### Changed
- Import flow includes parse + preview for validation before importing.
- Mid-semester timetable updates: choose an effective from date, preview changes (added/updated/retired slots), preserves older attendance history.
- Color uniqueness now handled separately for weekly vs special classes.
- Cards indicate when manual baseline logic is active; calculations respect manual baseline windows and lock rules.
- Day actions (Present / Skip / Holiday) are more adaptive on smaller screens.
- Added visible **Locked** state for dates restricted by manual baseline rules.
- Calendar better reflects date-based slot logic (including special classes).
- Improved spacing, typography, and control sizing for better compact-device usability.
- Update flow: **App updates** action in More now opens the new full-screen update page; removed old popup dialog.

### Fixed
- PDF/CSV/JSON export structured for easy re-import after editing.
- Fixed missed attendance marking after offline/interrupted sessions.
- Responsiveness and readability improvements across all main screens.

---


## [1.4.7] - 2026-03-01

### Open Source
- **AttendMate is now open source** — the full source code is available in the same GitHub repository where the APK is distributed. Contributions, bug reports, and feature suggestions are welcome!

### Fixed
- **AppBar Scroll Tint**: Fixed the page header slightly changing colour when scrolling — it now stays pure white in light mode and pure black in dark mode regardless of scroll position

---


## [1.4.6] - 2026-02-28

### Changed
- **Collapsible Subject Cards**: Cards now default to collapsed state instead of expanded

### Fixed
- **Acronym Generation Ignores Filler Words**: Subject acronyms in Add/Edit now skip common words ("and", "the", "of", "for", "with", "to", etc.) and use only main subject words for a more meaningful abbreviation
- **Subject Time Selection Flash**: Reduced screen flashing in Add Subject/Edit Subject during Start Time → End Time → Day picker transitions by smoothing dialog handoff and navigator routing
- **Holiday Day Class Visibility**: Classes are now shown even when an entire day is marked as holiday (class cards are no longer hidden); each class card includes a **Holiday** action to mark that individual class as holiday for the day

---


## [1.4.5] - 2026-02-26

### Added
- **Collapsible Subject Cards**: Each subject card can now be collapsed to show only the avatar/acronym, subject name, and edit/delete actions
- **Expanded Subject Schedule View**: Expanding a subject card continues to show the same schedule chip details as before
- **Unified Subject Card Header**: Avatar, name, edit/delete actions, and expand/collapse indicator now stay aligned in a single top row in both states
- **Collapsible Bunk Meter Cards**: Subject cards in Bunk Meter now support collapsed and expanded states to reduce list height
- **Compact Quick Status (Collapsed)**: Collapsed bunk meter cards now show a short status summary such as bunkable count, must-attend count, or can't bunk/target status
- **Expanded Full Details (Redesigned)**: Expanded bunk meter cards keep all previous bunk meter details with a cleaner layout and a 4-column quick-glance stats row (Classes Held, Attended, Bunked, Current %)
- **Header Style Match**: Bunk Meter card headers now match Subjects card style with avatar/acronym, subject name, and chevron indicator

### Changed
- **Home Update Flow**: Launch-time update prompt now opens as a full-screen update page instead of a small dialog
- **More Page Update Check**: Update checks now run only when tapped and continue showing update availability after selecting **Remind Later**
- **More → What's New Content**: In-app bundled release notes now hide the top version metadata block and the **Installation** section for cleaner reading

### Fixed
- **Subject Time Selection Flash**: Reduced screen flashing in Add Subject/Edit Subject during Start Time → End Time → Day picker transitions by smoothing dialog handoff and navigator routing

---


## [1.4.4] - 2026-02-22

### Added
- **Search**: Acronym-aware subject search in both the Subjects and Bunk Meter screens (e.g., searching `DBMS` now matches `Database Management Systems`)

### Changed
- **What's New Page**: Simplified to display only the bundled `RELEASE_NOTES.md` content, removing additional generated sections and extra UI blocks
- **Dialog UI**: Improved dark mode dialog background separation by slightly lightening the popup backdrop, making dialogs stand out more clearly
- **Toast & Snackbar**: Updated in-app toast/snackbar handling so the latest notification immediately replaces the currently visible one; prevented notification stacking/queue buildup during rapid actions

---


## [1.4.3] - 2026-02-22

### Added
- **More Page**: New **What's New** screen in More showing bundled release notes
- **More Page**: New **App updates** item that checks for update availability; displays an **Update available** badge when a newer version exists; tapping it opens the in-app update dialog
- **Setup Guide**: Rebuilt fully in-app with a swipeable, section-by-section book-style experience
- **Setup Guide**: Clickable Table of Contents for jumping directly to any section
- **Setup Guide**: On first launch, users are prompted to open the Setup Guide or start using the app directly
- **Setup Guide**: One-tap **Copy AI Prompt** button in the JSON import section
- **Setup Guide**: **Open in App** deep-link actions per section (Add Subject, Import Timetable, Attendance Calendar)

### Changed
- **Attendance Calendar**: Updated calendar swipe transitions to a push animation — swiping forward pushes content left while new content enters from the right; swiping back does the reverse
- **More Page**: Replaced GitHub-dependent **Latest update release date** with offline **Current version release date** sourced from bundled `RELEASE_NOTES.md`
- **Setup Guide**: Updated quote styling to use dark/grey theme-aware highlights instead of blue callouts; fixed JSON examples to render in proper code blocks; removed changelog/features footer content

### Fixed
- **More Page**: In **Support me** and **Request feature / Report bug** dialogs, tapping the action button now closes the dialog before opening the external link

---


## [1.4.2] - 2026-02-22

### Changed
- **Attendance Calendar**: Updated calendar swipe transitions to a PowerPoint-style push slide animation; swiping to next month/day pushes current content left while new content enters from the right, and vice versa for previous
- **More Page**: Improved theme switching with a 3-option selector in the app bar: **Light**, **Dark**, and **System** (phone icon); Light and Dark now stay fixed and no longer change with device theme; System mode follows the phone's light/dark setting automatically

### Fixed
- Removed the visible repository URL from the **Support me** dialog, keeping only the action button for a cleaner UI
- Fixed same-subject multiple-class attendance conflicts by rebuilding the attendance table with slot-based keys during upgrade (performs a one-time reset of attendance records to avoid legacy duplicate/misaligned status issues)
- Fixed lingering screen flash on Add Subject/Edit Subject during time-slot interactions by tightening text-field focus behavior (focus only on direct tap, then keyboard auto-dismisses after typing stops)

---


## [1.4.1] - 2026-02-21

### Added
- **Attendance Calendar**: Smooth swipe animations for month-to-month navigation in calendar view
- **Attendance Calendar**: Smooth swipe animations for day-to-day transitions in day details view; transitions use directional slide + fade animations for a more fluid experience
- **More Page**: Split app metadata into separate rows for **App version** and **Build number**
- **More Page**: New **Latest update release date** row sourced from GitHub releases
- **More Page**: New **Support me** entry that opens a dialog asking users to star the GitHub repository, with a direct repository link

### Changed
- **Subject Management**: Improved auto-generated acronyms (when acronym is left empty while adding/editing) to ignore filler words like "and", "the", "of", "with", "for", and "to"
- **Subject Management**: Removed redundant runtime acronym fallbacks across the app; acronym display/usage now relies on the stored subject acronym generated during Add/Edit save
- **Subject Management**: Centered acronym text inside subject avatar circles on both Subjects and Today's Schedule so wrapped acronyms remain visually centered
- **Subject Management**: Increased subject avatar circle size by 3% on Subjects and Today's Schedule for better acronym readability
- **More Page**: Updated the time format control to match the standard list-item UI used by the rest of the More page

### Fixed
- Fixed residual screen flash/jitter while adding or editing time slots in Add Subject and Edit Subject by removing focus churn during picker interactions
- Improved dark-mode dialog presentation by slightly lightening the background behind More page dialogs while keeping the dialog itself dark
- Updated request/bug dialog copy from "our" to "my" and removed inline link text from the dialog body
- Improved external link opening reliability for the More page action buttons with a stronger launch fallback flow

---


## [1.4.0] - 2026-02-20

### Added
- **More Tab**: New **More** tab (three-dots icon) in bottom navigation
  - Moved the global 12-hour / 24-hour time format toggle from the Subjects screen to the More tab
  - App version display in More showing **Version + Build Number**
  - In-app **Setup Guide** page
  - **Request feature / Report bug** action with guidance to create a new issue on GitHub
  - Direct link launch support for the GitHub Issues page
- **Attendance Calendar Improvements**:
  - Swipe navigation in calendar month view to move to previous/next month
  - Swipe navigation in day details view to move to previous/next day
  - Day view swipe skips days with no classes and jumps directly to the next/previous day that has classes

### Changed
- Updated bunk recommendation wording to: "You can bunk next X classes continuously"
- Added explicit zero-bunk state text: "You currently cannot bunk anymore classes" instead of showing "Can bunk 0 more classes"
- Added a warning in Overall Semester Summary that semester-level bunkable count may keep overall attendance above target while individual subjects can still fall below target
- Removed the duplicate top-right checkmark save action from Add Subject and Edit Subject screens, keeping only the bottom Save button
- When acronym is cleared and subject is saved, app now auto-generates an acronym from subject name initials (e.g., "Data Structures" → "DS") instead of retaining the previous acronym

### Fixed
- Fixed an issue where if the same subject appeared multiple times on the same day, only the first entry was shown — all same-day entries now appear correctly in both Today's Schedule and Calendar Day View
- Fixed a screen flash/jitter issue while adding or editing time slots in Add Subject and Edit Subject screens

---


## [1.3.4] - 2026-02-18

### Fixed
- Fixed a bug where the name of the app appeared as "Flutter Material AI App" in the recent apps screen on android

---


## [1.3.3] - 2026-02-15

### Fixed
- Fixed a bug where the update apk stayed in the app files after updating the app to the latest version
- Reduced app size significantly by optimizing for modern 64-bit devices
- Removed unnecessary debug statements for better performance
- Various bug fixes and stability improvements

---


## [1.3.2] - 2026-02-15

### Fixed
- Reduced app size by optimizing for modern 64-bit devices
- Removed unnecessary debug statements for better performance
- Various bug fixes and stability improvements

---


## [1.3.1] - 2026-02-14

### Fixed
- Various minor bug fixes and stability improvements.
---


## [1.3.0] - 2026-02-14

### Added
- **Global Time Format Preference**: Choose between 12-hour (AM/PM) and 24-hour time formats
  - Toggle available on Subject screen
  - Applied consistently across entire app (subject lists, calendar views, add/edit pages)
  - Times displayed in chosen format throughout schedule and calendar
- **Attendance Calendar**: Full-semester calendar view with comprehensive attendance tracking
  - Legend showing all attendance states
  - Tap past dates to review classes and update attendance via bottom sheet
  - Bulk actions per date (Present, Skip Day, Holiday)
  - Upcoming dates shown as read-only with distinct calendar state
  - Calendar day details display class time slots sorted chronologically

### Changed
- **UI Improvements**:
  - Schedule chips, calendar day dialogs, and time pickers now use selected time format for consistency
  - Subject cards now display acronyms (or first letters of each word) across Today, Calendar, and Subjects screens
  - Calendar upcoming-day color updated for better visual distinction from mixed attendance

### Fixed
- Editing subject time slot now defaults end time to slot's current end time instead of always adding one hour
- Calendar bulk actions now update day state immediately after selection
- Various minor bug fixes and stability improvements

---


## [1.2.0] - 2026-02-14

**Minimum Android Version:** 7.0 (API 24) — required for in-app update system and secure APK installation.

### Added
- **Holiday Management**: Mark/unmark entire days as holidays with automatic class cancellation
  - Dedicated "Today is a Holiday" screen when day is marked as holiday
  - Complete holiday isolation - classes hidden from display until unmarked
  - Automatic exclusion of holiday classes from attendance calculations
- **Enhanced Attendance Control**:
  - "Mark Today as Present" button to quickly mark all unmarked classes as present
  - Ability to unmark individual classes (both present and absent) to revert to "Awaiting Status"
  - Dual action buttons for marked classes (Mark Absent/Unmark for present classes, Mark Present/Unmark for absent classes)
- **Bunk Meter Search**: Search functionality to quickly find specific classes by name
  - Real-time filtering with case-insensitive matching
  - Search results counter showing number of matching classes
  - Quick clear button and empty state feedback
  - Preserved sorting (classes needing attendance appear first)
- **Automatic End-of-Day Attendance**: Unmarked classes automatically marked as present at 10 PM+
  - Smart holiday skip - auto-marking skipped if day marked as holiday
  - Respects user intent - pre-marked classes not overridden
  - Background task integration with WorkManager

### Changed
- **Attendance Calculation Improvements**:
  - Unmarked classes now excluded from attendance percentage calculations
  - Only explicitly marked classes (Present or Absent) counted toward bunk meter and semester summary
  - Clearer statistics display showing Classes Held, Marked, Attended, and Bunked separately
  - Simplified attendance messages with "Must attend X remaining classes" format
- **Improved UI Layout**: Better organized action buttons
  - Top row: "Mark Holiday", "Skip Day"
  - Second row: "Mark Present" for normal days
  - No action buttons shown when day marked as holiday

### Fixed
- Subject acronym not persisting across app restarts
  - Added database migration (schema v3) with `acronym` column to `subjects` table
  - Updated save/load logic to properly store and restore subject acronyms
- **Dark mode styling** for "What's New" box in update dialog
  - Background now properly changes to dark gray/black in dark mode instead of remaining white
- **APK installation issue** on Android
  - Replaced file opening approach with native Android method channel
  - Now properly uses Android's system package installer (ACTION_INSTALL_PACKAGE)
  - Resolved "problem parsing the package" errors when app was open during installation
  - Properly implements FileProvider for Android 7.0+ compatibility

### Performance
- Reduced APK size dramatically from ~178 MB to ~54 MB
  - Removed emulator-only native libraries
  - Enabled aggressive code and resource shrinking
  - Enabled R8 minification
  - Added ProGuard/R8 rules for Flutter and Play Core classes

---

## [1.1.0] - 2026-02-12

### Added
- Automatic update detection feature to check for new app versions

### Fixed
- Fixed Android app name appearing as "flutter material ai app" in recent apps - now correctly shows "AttendMate"

---

## [1.0.1] - 2026-02-08

### Fixed
- Fixed JSON import not importing acronyms from timetable data (operator precedence bug)
- Fixed all analyzer warnings and issues (empty catch blocks, unnecessary null checks, unused variables)

### Changed
- Simplified bunk meter text messages to be more concise and fit in one line
- Simplified semester summary card text to show essential information only
- Messages now directly state "Can bunk X classes" or "Must attend X of Y classes"
- Removed target attendance percentage pill from JSON import preview cards

---

## [1.0.0] - 2026-02-07

### Initial Release

This is the first public release of AttendMate, a comprehensive attendance tracking app for students.

### Added

#### Semester Management
- Semester creation with start date, end date, and target percentage
- Automatic semester status detection (not started, active, ended)
- Semester editing and configuration
- Persistent semester data storage
- Visual status indicators and informational banners

#### Subject Management
- Add unlimited subjects with custom names and optional acronyms
- Color-coded subjects with 10 predefined colors
- Individual target attendance percentage per subject
- Edit and delete subjects with confirmation dialogs
- Automatic color assignment from unused colors
- Persistent subject data storage

#### Schedule Management
- Flexible weekly schedules with multiple time slots per subject
- Support for all 7 days of the week
- Custom start and end times for each class
- Time picker UI for easy time selection
- Schedule validation (end time after start time)
- Edit and delete individual time slots
- Automatic calculation of total scheduled classes

#### Timetable Import
- Bulk import subjects via JSON format
- Import single or multiple subjects at once
- JSON validation with detailed error messages
- Preview imported subjects before confirming
- Automatic color assignment during import
- Copy JSON format reference to clipboard
- Built-in JSON format documentation

#### Attendance Tracking
- Today's Schedule view with all classes for current day
- Time-sorted class list (earliest to latest)
- Quick attendance marking with Present/Absent buttons
- Toggle attendance status (Present ↔ Absent)
- Visual status indicators with icons and colors
- Subject color-coded avatars
- Display class timings
- "No classes today" message for empty schedules
- Semester-aware attendance tracking

#### Bulk Attendance Actions
- Mark entire day as Holiday (cancels all classes)
- Skip entire day (marks all classes as absent)
- Confirmation dialogs before bulk actions
- Success notifications after actions

#### Bunk Meter (Predictions)
- Real-time attendance percentage calculation
- Bunking predictions based on target percentage
- Three prediction scenarios:
  - Above Target: Shows safe bunking capacity
  - Below Target: Shows required attendance
  - Target Unreachable: Warns when impossible to achieve
- Detailed statistics per subject (held, attended, bunked, current %)
- Future class predictions and remaining classes count
- Maximum attainable percentage calculation
- Intelligent subject sorting (subjects needing attention first)
- Color-coded messages (green, orange, red)
- Semester end date awareness
- Correct handling of cancelled classes

#### Notifications
- Automatic notification scheduling for all subjects
- Notifications trigger when class ends
- Action buttons in notifications (Mark Present/Absent)
- Mark attendance directly from notification
- Tap notification to navigate to Today's Schedule
- Confirmation notification after marking attendance
- Auto-dismiss confirmation after 2 seconds
- Skip notifications for already-marked attendance
- Timezone-aware scheduling
- Exact alarm support for precise timing
- 5-minute grace period for recently ended classes
- Notification and exact alarm permission requests
- Custom notification icon with vibration and sound

#### Theme Support
- Light theme with white background
- Dark theme with true black background
- System theme following (automatic switching)
- Theme toggle button in app bar
- Persistent theme preference
- Material Design 3 components
- Consistent color scheme across themes

#### User Interface
- Bottom navigation bar with 4 tabs (Today, Subjects, Semester, Bunk Meter)
- Fixed bottom navigation (always visible)
- Active tab highlighting
- Google Fonts integration (Oswald, Roboto, Open Sans)
- Custom typography scale
- Rounded corners on cards and buttons
- Elevation and shadows
- Color-coded subjects
- Icon-based status indicators
- Responsive layouts
- Consistent spacing and padding

#### User Experience
- Floating Action Button for adding subjects
- Contextual action buttons
- Confirmation dialogs for destructive actions
- Success/error snackbar notifications
- Empty states with helpful messages
- Informational banners
- Tooltips on icon buttons
- Keyboard dismissal on tap outside
- Form validation with error messages

#### Data Management
- SQLite local database for data persistence
- Automatic database initialization
- CRUD operations for all entities
- Data persistence across app restarts
- Efficient data loading
- Offline-first architecture (no internet required)

#### State Management
- Provider pattern for state management
- Reactive UI updates
- Efficient widget rebuilding
- Separation of concerns (UI, business logic, data)
- Multiple providers (Theme, Semester, Subject, Attendance)

#### Performance & Reliability
- Optimized database queries
- Efficient list rendering
- Minimal unnecessary rebuilds
- Fast app startup
- Smooth animations and transitions
- Error handling for database operations
- Graceful degradation
- Input validation and edge case handling
- Null safety and type safety

#### Privacy & Security
- All data stored locally on device
- No data collection or internet connection required
- No third-party analytics
- No user accounts or authentication
- Complete privacy

### Technical Details
- **Platform:** Android (Flutter-based)
- **Database:** SQLite
- **State Management:** Provider
- **UI Framework:** Material Design 3
- **Notifications:** Flutter Local Notifications
- **Fonts:** Google Fonts
- **Version:** 1.0.0+1
- **Minimum Android:** API 21 (Android 5.0)

---

## Version History

- **2.2.0** (2026-09-10) - Centralized Google Integrations hub, Google Drive cloud backup at midnight with smart restore on login, multi-day special class support with arbitrary date ranges, historical attendance import (CSV & JSON) with preview verification, IndexedStack tab flicker elimination, infinite rebuild loop fixes in calendar, deduplicated provider listeners, 5-minute smart app-close backup on session mutations, GitHub Discussions in-app browser & launch announcement checker, Keep Android Open awareness & FreeDroidWarn integration, clean geofencing status badge, universally clickable markdown links, expanded 22-chapter setup guide, privacy & terms updates.
- **2.1.0** (2026-09-01) - Scrollable 15-day schedule window (-7/+7 days) with dynamic titles & direct attendance marking, short of target continuous recovery calculation fix, future holiday absence pre-marking, removal of auto end-of-day attendance marking, locked status display on today's schedule, background location fetch optimization, interactive projected attendance popup, bunk calculator target date selector & planned leave toggle, calendar baseline status & lock icon display fix, bunk calculator manual baseline calculation fix & max class increment guard, unrestricted background battery access prompt, bunk meter manual baseline reset & interactive tooltip, future day holiday marking in calendar, next immediate planned leave projected attendance calculation, class location JSON import support, pre-marked class notification suppression, mid-semester timetable update overwrite fix, automatic backup fix
- **2.0.2** (2026-08-11) - Native Android .json file handler ("Open with AttendMate"), smart auto-restore & conditional backup on folder selection, auto-backup semester safeguard, direct classmate data sharing, backup storage location fix, location & planned holiday backup fixes, database clear fixes, setup guide auto-scroll navigation fix
- **2.0.1** (2026-08-10) - Class-wise location selection, classroom details in notifications, diagnostics log & GitHub issue reporting, timetable JSON import default, text field keyboard focus fixes, pre-semester calendar access fix
- **2.0.0** (2026-07-22) - Major release with Geofenced Auto-Attendance & Interactive Google Maps, "What-If" Bunk Calculator, Leave Planner, Rolling Semester Backup System, Interactive Calendar Filtering, Guided Spotlight Tour, and UI modernizations
- **1.6.2** (2026-07-17) - Preserved swipe card state, smooth liquid-like easing, dependency cleanup, Setup Guide duplicate fix
- **1.6.1** (2026-07-11) - Google Calendar sign-in fix for updated package name
- **1.6.0** (2026-07-08) - Automated background calendar sync, smart lab color grouping, linear probing color mapping, sign-in warning removal
- **1.5.5** (2026-07-07) - In-app data protection disclosures for Google OAuth verification
- **1.5.4** (2026-06-28) - In-app privacy links, dynamic status card dark theme styling fix
- **1.5.3** (2026-06-27) - Google Calendar Sync, background notification live sync, confirm notifications, scheduling grace period removal
- **1.5.2** (2026-06-26) - clock style selector, saved preference, older-device performance improvements, Add/Edit Subject UI refresh, notification fixes
- **1.5.1** (2026-04-03) - Ccopy timetable to day, and updated UI
- **1.5.0** (2026-03-29) - Import time table updates, and mid semester timetable updating
- **1.4.7** (2026-03-01) - AttendMate goes open source, AppBar scroll tint fix
- **1.4.6** (2026-02-28) - Collapsible subject cards default to collapsed, acronym filler word fix, time selection flash fix, holiday day class visibility fix
- **1.4.5** (2026-02-26) - Collapsible subject/bunk meter cards, full-screen home update flow, update check on tap, What's New metadata/install section hidden, subject time selection flash fix
- **1.4.4** (2026-02-22) - Acronym-aware subject search, simplified What's New page, dark mode dialog polish, toast/snackbar stacking fixes
- **1.4.3** (2026-02-22) - What's New screen, App updates item with badge, offline release date, Setup Guide rebuilt in-app (swipeable, ToC, onboarding prompt, deep links), calendar push animation fix, dialog auto-close fix
- **1.4.2** (2026-02-22) - Push-slide calendar swipe animation, 3-option theme selector, support dialog polish, attendance slot conflict fix, screen flash fix
- **1.4.1** (2026-02-21) - Calendar swipe animations, acronym improvements, More page additions (update date, support, split metadata), polish fixes
- **1.4.0** (2026-02-20) - More tab, swipe navigation in calendar, bunk meter wording improvements, duplicate subject fix, various UI fixes
- **1.3.4** (2026-02-18) - recent apps name fix, update apk bug fix, reduced app size, performance improvements
- **1.3.3** (2026-02-15) - fixed update apk retention, reduced app size, performance improvements
- **1.3.2** (2026-02-15) - bug fixes, performance improvements
- **1.3.1** (2026-02-14) - performance improvements
- **1.3.0** (2026-02-14) - Global time format preference, attendance calendar with bulk actions, UI improvements, bug fixes
- **1.2.0** (2026-02-14) - Holiday management, enhanced attendance control, bunk meter search, auto end-of-day attendance, major size optimizations
- **1.1.0** (2026-02-12) - Automatic update detection, app name fix
- **1.0.1** (2026-02-08) - JSON import acronym fix, analyzer warnings resolved
- **1.0.0** (2026-02-07) - Initial public release

---

## Future Considerations

While this is the initial release with a complete feature set, potential future enhancements could include:
- Statistics and analytics dashboard
- Export attendance data
- Backup and restore functionality
- Widget support for home screen
- Additional customization options

---

**Note:** This changelog will be updated with each new release to document all changes, additions, and fixes.
