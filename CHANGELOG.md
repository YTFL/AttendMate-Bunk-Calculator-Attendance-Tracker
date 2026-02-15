# Changelog

All notable changes to AttendMate will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
