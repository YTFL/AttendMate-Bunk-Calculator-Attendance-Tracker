# Changelog

All notable changes to AttendMate will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
