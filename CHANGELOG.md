# Changelog

All notable changes to AttendMate will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
