import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../main.dart';
import '../../utils/snackbar_utils.dart';
import '../calendar/calendar_screen.dart';
import '../home/home_screen.dart';
import '../subject/add_subject_screen.dart';
import 'calendar_sync_selection_screen.dart';
import 'swipe_actions_settings_screen.dart';
import '../import/unified_import_screen.dart';
import '../location/location_manager_screen.dart';
import '../planner/leave_planner_screen.dart';
import 'semester_backup_screen.dart';
import 'google_integrations_screen.dart';
import 'github_discussions_screen.dart';
import 'keep_android_open_screen.dart';
import '../../services/battery_optimization_service.dart';
import '../../utils/attendance_import_utils.dart';
import '../../utils/markdown_link_helper.dart';

class SetupGuideScreen extends StatefulWidget {
  final int initialPage;
  const SetupGuideScreen({super.key, this.initialPage = 0});

  @override
  State<SetupGuideScreen> createState() => _SetupGuideScreenState();
}

class _SetupGuideScreenState extends State<SetupGuideScreen> {
  late final PageController _pageController;
  int _currentPage = 0;

  static const String _attendanceAiPrompt = AttendanceImportUtils.attendanceAiPrompt;

  static const String _aiPrompt = '''I have attached an image/screenshot of my college timetable. Convert it into the following JSON format exactly:

{
  "subjects": [
    {
      "name": "Subject Name",
      "acronym": "ACR",
      "room": "Room 101",
      "block": "Block A",
      "schedule": [
        {
          "day": "monday",
          "startTime": "09:00",
          "endTime": "10:00",
          "room": "Room 101",
          "block": "Block A"
        }
      ]
    }
  ]
}

Rules to follow:
- "name" is the full subject name as shown in the timetable.
- "acronym" is a short 2–4 letter code for the subject (create one if not shown).
- "room" is the room number or name (optional, e.g. "Room 101", "Lab 2").
- "block" is the building or block name (optional, e.g. "Block A", "Science Wing").
- "day" must be fully lowercase: monday, tuesday, wednesday, thursday, friday, saturday, or sunday.
- "startTime" and "endTime" must be in 24-hour HH:MM format (e.g. 09:00, 14:30).
- "room" and "block" can be specified at the subject level or inside individual schedule slots.
- Include every subject and every time slot shown in the timetable.
- Return only the raw JSON with no extra explanation.''';


  final List<_GuideSection> _sections = [
    _GuideSection(
      title: '1. Setting Up Your Semester',
      openInAppLabel: 'Open Semester Page',
      openTarget: _GuideOpenTarget.semesterTab,
      markdown: '''
## Overview
Before you can add subjects or track attendance, you must set up a semester.

---

## Steps
1. Open AttendMate and tap the **Semester** tab.
2. Tap **Set Up Semester**.
3. Fill **Start Date**, **End Date**, and **Target Attendance %**.
4. Tap **Save**.

> Attendance tracking and subject features stay locked until a valid semester is configured.
''',
    ),
    _GuideSection(
      title: '2. Adding Subjects Manually',
      openInAppLabel: 'Open Add Subject',
      openTarget: _GuideOpenTarget.addSubject,
      markdown: '''
## Overview
Add subjects one by one with name, acronym, color, and time slots.

---

## Steps
1. Open the **Subjects** tab.
2. Tap the **+** button.
3. Choose class type:
   - Keep **Special Multi-Day Class** OFF for regular weekly classes.
   - Turn **Special Multi-Day Class** ON for non-repeating classes.
4. Fill subject name, optional acronym, and color.
5. Add schedule:
   - Weekly class: tap **Add Slot** and pick weekdays/time.
   - Special class: pick one or multiple dates (with or without gaps in between them) using the calendar or date chips, then assign time slot(s) across those dates.
6. Tap **Add Subject**.

---

## Special Multi-Day Class Rules
- Special classes are counted in attendance just like regular classes.
- Special classes do **not** repeat weekly.
- You can select single or multiple dates with or without gaps (e.g. weekend bootcamps, guest lectures, makeup labs).
- Duplicate subject colors are not allowed on the same date, but can be reused across different dates.
- Time slots added apply across all selected dates, and can be adjusted anytime.

---

## Manage Existing Subjects
To edit or delete, open any subject card and update details.
''',
    ),
    _GuideSection(
      title: '3. Importing Subjects via JSON/CSV',
      openInAppLabel: 'Open Import Timetable',
      openTarget: _GuideOpenTarget.importTimetable,
      markdown: '''
## Overview
If you have your timetable ready, you can import all subjects at once using either JSON or CSV.

---

## How to Import
1. On **Subjects**, tap the **Import** icon in the top app bar (upper-right corner).
2. Paste JSON/CSV **or** tap **Import File** to load a `.json` or `.csv` file.
3. Review preview cards.
4. Tap the **Import** button at the bottom of the screen (below the preview cards).

---

## Supported Formats
- **JSON**: Same schema as JSON export (`subjects` with `name`, optional `acronym`, and `schedule`).
- **CSV**: Same grid shape as CSV export.

```text
Day,"09:00-10:30","10:00-11:30"
Monday,"MTH","-"
Tuesday,"PHY","CSE"
```

> Use **Copy JSON Reference** or **Copy CSV Reference** inside Import Timetable.

---

## Export Notes
- Export options (**JSON / CSV / PDF**) are for the **weekly timetable**.
- One-off **Special One-Day Classes** are excluded from timetable export.

---

> **Tip:** Want to skip manual JSON writing? Use the ready-to-use AI prompt below with your timetable image.
''',
      aiPromptCopyText: _aiPrompt,
    ),
    _GuideSection(
  title: '4. Exporting Timetable (JSON/CSV/PDF)',
  openInAppLabel: 'Open Import Timetable',
  openTarget: _GuideOpenTarget.importTimetable,
  markdown: '''
## Overview
You can export your weekly timetable in **JSON**, **CSV**, or **PDF** directly from the Import Timetable screen.

---

## How to Export
1. Open **Subjects** and go to **Import Timetable**.
2. Tap the **three-dot menu** in the top-right.
3. Choose one of:
   - **Export as JSON**
   - **Export as CSV**
   - **Export as PDF**

---

## Output Details
- All files are saved to your device **Downloads** folder.
- Export covers the **weekly timetable grid**.
- One-off **Special One-Day Classes** are excluded from export.

---

## Format Notes
- **JSON Export**: Uses the same schema supported by JSON import.
- **CSV Export**: Uses the same grid format supported by CSV import.
- **PDF Export**: Generates a landscape timetable table based on the same grid data.

> This means exported JSON/CSV can be edited and re-imported into AttendMate.
''',
    ),
    _GuideSection(
      title: '5. Marking Attendance',
      openInAppLabel: 'Open Today Page',
      openTarget: _GuideOpenTarget.todayTab,
      markdown: '''
## Overview
The **Today** tab shows all classes for the current day.

---

## Class Actions
Use class actions:
- **Mark Present**
- **Mark Absent**
- **Unmark**

---

## Bulk Day Actions
Bulk actions are available for a full day:
- **Mark Holiday**
- **Skip Day**
- **Mark Today as Present**
''',
    ),
    _GuideSection(
      title: '6. Swipe Gestures & Customization',
      openInAppLabel: 'Open Swipe Settings',
      openTarget: _GuideOpenTarget.swipeActions,
      markdown: '''
## Overview
AttendMate supports swipe gestures to quickly mark and unmark attendance directly from the **Today** schedule list.

---

## Swipe Actions
- **Swipe Right**: By default, swipe right to mark a class as **Present**.
- **Swipe Left**: By default, swipe left to mark a class as **Absent**.

---

## Integrated Swipe-to-Unmark
If you swipe a card in the direction of its already active status, it will toggle and **unmark** the attendance record:
- Swipe **Right** on a class that is already marked **Present** to unmark it.
- Swipe **Left** on a class that is already marked **Absent** to unmark it.

---

## Customization Settings
You can customize which direction does what:
1. Go to the **More** tab and tap **Swipe Actions**.
2. Choose your preferred configuration (Option A: Right = Present / Left = Absent; Option B: Right = Absent / Left = Present).
3. Duplicates are not allowed; changing one side automatically swaps the other to keep configuration consistent.

> Swiping displays clean, text-free action icons (Check/Close/Undo) and animates back smoothly without flickering.
''',
    ),
  _GuideSection(
      title: '7. Calendar View',
      openInAppLabel: 'Open Calendar',
      openTarget: _GuideOpenTarget.calendar,
      markdown: '''
## Overview
Open **Calendar** from the app bar to review attendance across dates.

---

## Date Actions
Tap any past date to:
- View class-wise status
- Edit attendance
- Use bulk actions for that date

> Upcoming dates are read-only.
''',
    ),
  _GuideSection(
      title: '8. Bunk Meter',
      openInAppLabel: 'Open Bunk Meter',
      openTarget: _GuideOpenTarget.bunkMeterTab,
      markdown: '''
## Overview
The **Bunk Meter** predicts where each subject stands against your target.

---

## Subject Metrics
For each subject, it shows:
- Current %
- Held / Attended / Bunked counts
- Remaining classes

---

## Prediction Summary
It also tells whether you can bunk safely, need to attend more, or if the target is unreachable.
''',
    ),
  _GuideSection(
      title: '9. Notifications',
      openInAppLabel: 'Open Today Page',
      openTarget: _GuideOpenTarget.todayTab,
      markdown: '''
## Overview
AttendMate sends notifications before and after your scheduled classes:
1. **Pre-Class Location Reminder (5 Mins Before)**: Sends a notification formatted with your subject and classroom location (e.g. *Next Class: DBMS in Block B, Room 402*) so you can head directly to class.
2. **End of Class Marking Reminder**: Prompts you to record attendance when class ends.

---

## Quick Actions
- **Pre-Class Notification**: Tap to open **Today** and view your schedule.
- **End-of-Class Notification**: Tap **Mark Present** or **Mark Absent** directly from the notification.

> Ensure notification permissions and exact alarm permissions are enabled in Android settings.
''',
    ),
    _GuideSection(
      title: '10. Calendar Synchronization',
      openInAppLabel: 'Open Calendar Sync Settings',
      openTarget: _GuideOpenTarget.googleCalendarSync,
      markdown: '''
## Overview
AttendMate supports two forms of calendar synchronization to keep your weekly timetable, classes, and cancellations perfectly synchronized:
1. **Google Calendar Sync (Cloud)**: Links to your Google Account and syncs your schedules online.
2. **Device Calendar Sync (Local)**: Writes your schedules directly to your phone's native calendar database (supporting Samsung Calendar, Outlook, or local offline calendars).

---

## Setting Up Google Calendar Sync
1. Open the **More** tab and tap **Calendar Sync**.
2. Under **Google Calendar Sync**, tap the arrow to open settings, then tap **Connect Account** and log in.
3. Once connected, AttendMate will automatically sync your timetable. You can also tap **Sync Now** to trigger an immediate full update.

---

## Setting Up Device Calendar Sync
1. Open the **More** tab and tap **Calendar Sync**.
2. Toggle **Device Calendar Sync** to **ON** (allow the calendar permission prompt when requested).
3. Under **Select Destination Calendar**, choose the target calendar from the dropdown. 
   - All Google account calendars, Samsung/Outlook accounts, and local offline phone calendars (labeled as `My Calendar (Local Offline)`) will be listed with their owner accounts.
4. Tap **Sync to Device Calendar Now** to write all your schedules to your local calendar database.

---

## Automated Background Sync
Once calendar synchronization is configured, you don't need to manually sync again! AttendMate automatically runs background sync operations (debounced at 1.5 seconds to protect your battery and network) whenever you:
- Add, edit, or delete a subject or schedule timeslot.
- Change a subject's name (automatically updates event titles).
- Declare/unmark a holiday.
- Mark a class as cancelled (automatically deletes that specific event occurrence).

---

## Key Rules
- **Color Mapping**: Google Calendar color mapping automatically groups related lecture and lab subjects together under the same color, using a linear probing collision loop to resolve overlaps.
- **Smart Filtering**: Read-only holiday calendars, national calendars, and third-party subscription lists are automatically filtered out to keep your dropdown clean.
- **Outlook Calendar Sync**: To sync with Outlook, open the native Outlook app settings and ensure **Sync calendars** is enabled for your Exchange account.
''',
    ),
  _GuideSection(
    title: '11. Setting up Locations & Auto-Attendance',
    openInAppLabel: 'Open Location Manager',
    openTarget: _GuideOpenTarget.locationManager,
    markdown: '''
## Overview
AttendMate supports location-based auto-attendance to automatically mark you as Present when you are in your classroom.

---

## Steps to Configure Locations
1. Go to the **More** tab and tap **Location Manager**.
2. Tap the **+** (Add) button in the bottom-right corner.
3. Enter a **Location Name** (e.g. *Room 402*) and **Block** (e.g. *Block C*).
4. (Optional) Capture GPS coordinates:
   - Tap **Set to Current Location** to grab your device's current coordinates.
   - Or tap **Select from Map** to open maps, copy coordinates, and paste them.
5. Tap **Save Location**.

---

## Link Locations to Subjects
1. Go to the **Subjects** tab and edit or add a subject.
2. Under **Class Location**, select your saved room configuration from the dropdown.
3. Tap **Save** / **Add Subject**.

---

## How Auto-Attendance Works
- **Low-Power Trigger**: Exactly 5 minutes after a scheduled class starts, a background task wakes up and checks your location.
- **Range Check**: If you are within a **25-meter radius** of the classroom coordinates, it automatically marks you as **Present**.
- **Notification**: A confirmation notification is displayed: *"Auto-logged Present for DBMS in Room 402"*.

> **Background Location**: This feature requires setting location permissions to **"Allow all the time"** in device settings.
''',
  ),
  _GuideSection(
    title: '12. The Bunk Calculator',
    openInAppLabel: 'Open Bunk Meter',
    openTarget: _GuideOpenTarget.bunkMeterTab,
    markdown: '''
## Overview
The **What-If Calculator** helps you run hypothetical scenarios to see the impact of future attendance actions on your overall percentages.

---

## How to Simulate Scenarios
1. Go to the **Bunk Meter** tab.
2. Tap the **Calculator** icon in the top app bar (upper-right corner).
3. Select a subject to simulate.
4. Adjust the variables using the sliders or input fields:
   - *"What if I bunk the next N classes?"*
   - *"What if I attend the next M classes?"*
5. The sheet will instantly compute and compare:
   - **Current Attendance %**
   - **Simulated Attendance %**
6. If the simulated percentage falls below your target limit (e.g., 75%), a red warning is shown.
''',
  ),
  _GuideSection(
    title: '13. Planning Future Trips & Leaves',
    openInAppLabel: 'Open Leave Planner',
    openTarget: _GuideOpenTarget.leavePlanner,
    markdown: '''
## Overview
The **Leave Planner** allows you to schedule fests, medical leaves, or personal trips in advance. The app forecasts the impact on your attendance so you can prepare buffer classes beforehand.

---

## Creating a Planned Leave
1. Go to the **Bunk Meter** tab.
2. Tap the **Leave Planner** (calendar checklist) icon in the top app bar.
3. Tap **Add Planned Leave** or the **+** button.
4. Select the **Start Date** and **End Date** for your leave.
5. Provide a **Reason** (e.g., *Technical Fest*, *Medical Leave*).
6. Tap **Save**.

---

## Impact & Forecasting
- **Projected Percentage**: The **Bunk Meter** screen will display both your **Current Attendance** and a **Projected Attendance (after Leave)**.
- **Warnings**: The system warns you if your scheduled leaves will drag any subject below your target attendance limit.

---

## Resolving Planned Leaves
Once the leave period passes, a dialog prompt will ask you to confirm your absences to automatically record them in your attendance logs.
''',
  ),
    _GuideSection(
      title: '14. Google Integrations & Cloud Backup',
      openInAppLabel: 'Open Google Integrations',
      openTarget: _GuideOpenTarget.googleIntegrations,
      markdown: '''
## Overview
AttendMate provides a unified Google account hub under **More > Google Integrations** for Google Calendar synchronization and Google Drive cloud backups.

---

## Google Drive Cloud Backup
- **Daily Midnight Backup**: When enabled, AttendMate automatically creates an encrypted, single JSON cloud backup (`attendmate_cloud_backup.json`) in your Google Drive every night at midnight.
- **No Rapid Rolling Sync**: Unlike local backups, cloud backup strictly avoids high-frequency rolling syncs to preserve battery and respect API quotas.
- **Smart Restore on Login**: When signing in to Google Drive (from Google Integrations, Calendar Sync, or Semester Backup), AttendMate automatically detects if an existing cloud backup exists and prompts you to restore your data immediately.
- **Force Cloud Backup**: Tap **Force Backup to Drive Now** anytime to create an immediate backup.

---

## Google Calendar Sync
- Keep your class schedule synchronized directly to Google Calendar.
- Clean one-tap toggle for easy enabling and disabling without cluttering secondary screens.

> Privacy First: Cloud backups are stored in your private Google Drive app storage and are never shared or accessible by third parties.
''',
    ),
    _GuideSection(
      title: '15. Historical Attendance Import (CSV & JSON)',
      openInAppLabel: 'Open Attendance Import',
      openTarget: _GuideOpenTarget.importAttendance,
      markdown: '''
## Overview
Switching to AttendMate mid-semester or have existing attendance records from your college ERP portal, spreadsheet, or attendance app? You can import all your past attendance history or update your attendance counts in one go using JSON or CSV!

---

## ⚡ Fast AI Import (Screenshot to Attendance in Seconds)
1. Take a screenshot or copy the text table of your attendance records from your college portal, website, or app.
2. Tap **Copy AI Prompt** below to copy our prepared attendance conversion prompt.
3. Paste the prompt along with your screenshot or text into any AI (ChatGPT, Claude, or Gemini).
4. Copy the JSON array returned by the AI.
5. In AttendMate, tap the download/import icon in the **Semester** or **Bunk Meter** header (or tap **Open Attendance Import** above).
6. Paste the JSON into the box (or tap **Paste** inside the text box), then tap **Parse & Preview**.
7. Confirm the matched subjects and before-and-after comparison, then tap **Apply Import** to update your attendance!

---

## How to Import Manually
1. Open **Import Attendance** from the header in the **Semester** or **Bunk Meter** screen.
2. Paste your attendance JSON or CSV directly into the text box, or tap **Upload File** to select a `.json` or `.csv` file.
3. Tap **Parse & Preview**.
4. Review the comparison showing matched subjects, previous held/attended counts vs new counts, and percentage differences.
5. Tap **Apply Import** to save!

---

## Supported Formats & Rules
- **Date Range**: Dates must fall within your configured semester bounds.
- **Subject Matching**: Subject names or acronyms are matched against your existing subjects (fuzzy matching supported).
- **Status Codes**: 
  - `P` / `Present` / `Attended` / `1`
  - `A` / `Absent` / `Bunk` / `0`
  - `H` / `Holiday` / `Cancelled`
- **JSON Format**:
```json
[
  {
    "date": "2026-08-10",
    "subject": "Mathematics",
    "status": "Present",
    "slot": "09:00 - 10:00"
  },
  {
    "date": "2026-08-10",
    "subject": "Physics",
    "status": "Absent"
  }
]
```
- **CSV Format**:
```csv
Date,Subject,Status,Slot
2026-08-10,Mathematics,Present,09:00 - 10:00
2026-08-10,Physics,Absent,10:00 - 11:00
2026-08-11,Chemistry,Present,
```

> **Tip:** Tap **Copy AI Prompt** below to copy the prompt and feed your previous attendance data to AI!
''',
      aiPromptCopyText: _attendanceAiPrompt,
    ),
    _GuideSection(
      title: '16. Semester Backup & 5-Minute Smart Auto-Backup',
      openInAppLabel: 'Open Semester Backup',
      openTarget: _GuideOpenTarget.semesterBackup,
      markdown: '''
## Overview
Semester Backup protects your attendance records, timetable schedules, subject details, location geofences, and app settings against accidental loss.

---

## Setting Up Your Backup Location
1. Go to the **More** tab and tap **Semester Backup**.
2. Tap **Select Location** or **Change Location** to select a dedicated folder on your device storage.
3. Once a custom folder is selected, AttendMate will automatically manage up to **3 rolling backups** in that location.

> **Important**: Internal app storage gets deleted if you uninstall the app. Choosing a custom folder on your device storage ensures your backups survive app uninstallation.

---

## Automatic Backups & Smart 5-Minute App Exit
AttendMate creates backups in three scenarios:
1. **5-Minute Smart App-Close Backup**: When you exit the app, a backup is scheduled 5 minutes later **only if you made changes in that session**. Reopening the app without making changes preserves the pending timer without resetting it.
2. **Daily 10:00 PM Local Backup**: Background task running every night at 10:00 PM for up to 3 rolling backups.
3. **Daily Midnight Cloud Backup**: Backs up to Google Drive at midnight when Google Drive backup is enabled.

---

## Restoring a Backup
1. Open **Semester Backup** from the **More** tab.
2. Tap **Restore This Backup** on any of your saved rolling backups, or tap **Import File** to restore from any `.json` backup file.
3. Confirm the restoration. AttendMate will restore 1:1 exact data state, including all subjects, colors, schedules, attendance history, and preferences.
''',
    ),
    _GuideSection(
      title: '17. Sharing & Importing Semester Templates',
      openInAppLabel: 'Open Semester Page',
      openTarget: _GuideOpenTarget.semesterTab,
      markdown: '''
## Overview
AttendMate allows you to export and share your complete semester schedule, subject timetables, classroom locations, and target attendance percentages directly with a classmate or friend. 

Your friend can import your semester package instantly so they don't have to add all subjects, timeslots, and room locations manually!

---

## Privacy Protection
- **No Attendance History**: When you share a semester package with a friend, your personal attendance records (Present / Absent logs) are **automatically stripped out** to keep your attendance data private.
- **Clean Template**: The shared `.json` file contains only semester dates, target percentage, subjects, schedules, rooms, blocks, and location presets.

---

## How to Share Your Semester
1. Open AttendMate and go to the **Semester** tab (or **More** tab).
2. Tap **Share Semester Data** (or **Share Semester with Friend**).
3. The native Android Share Sheet will appear. You can:
   - Send the `.json` file directly via **WhatsApp**, **Telegram**, or **Email**.
   - Save the `.json` file to your device file manager.
   - Or copy the semester JSON to clipboard.

---

## How to Import a Classmate's Semester

### Method 1: Android "Open With" Direct Launch (Recommended)
1. In WhatsApp, Telegram, or File Manager, tap the `.json` file your classmate sent you.
2. Select **Open With** → **AttendMate**.
3. AttendMate will automatically detect the semester package and present the **Import Semester Setup** preview dialog.

### Method 2: In-App Import
1. Go to the **Semester** tab and tap **Import Classmate's Semester** (or go to **Subjects** → **Import**).
2. Choose your classmate's `.json` file or paste the JSON text.

---

## Import Modes
When previewing the shared semester, you can choose between two import modes:

1. **Fresh Semester Setup (Recommended)**:
   - Completely overwrites your database and sets up the shared semester with **0 attendance recorded**.
   - Wipes old subjects, timetables, and stale location presets so you get a clean slate.

2. **Merge Subjects into Current Semester**:
   - Appends the imported subjects and schedule timeslots to your existing semester without clearing your current attendance logs or subjects.
''',
    ),
    _GuideSection(
      title: '18. GitHub Discussions & Announcements',
      openInAppLabel: 'Open Discussions',
      openTarget: _GuideOpenTarget.githubDiscussions,
      markdown: '''
## Overview
Stay connected with the AttendMate community, read official announcements, ask questions, and share ideas directly from the app.

---

## In-App Discussion Browser
1. Go to **More > Help & Support > GitHub Discussions**.
2. Filter discussions by category chips: **All**, **Announcements**, **General**, **Ideas**, **Q&A**, etc.
3. Tap any discussion card to read the full post formatted in clean markdown.
4. Tap the **Open in GitHub** icon in the header to jump to the official discussion page on GitHub to join the conversation.

---

## Launch Announcement Popups
- When a new official announcement is posted on GitHub, AttendMate automatically notifies you on app launch with an interactive popup dialog.
- Only posts categorized as **Announcements** trigger launch notifications.
- All fetched posts are cached offline so you can read them even without an active internet connection.
''',
    ),
    _GuideSection(
      title: '19. Keep Android Open & Sideloading',
      openInAppLabel: 'Open Keep Android Open',
      openTarget: _GuideOpenTarget.keepAndroidOpen,
      markdown: '''
## Overview
Open platforms allow apps like AttendMate to exist freely without walled gardens, advertising requirements, or platform restrictions.

---

## The Threat to Android Sideloading (Jan 2027)
Starting in January 2027, major platform restrictions are planned that could heavily restrict sideloading apps from outside official app stores, impacting open-source projects, independent developers, and student tools.

---

## Take Action
Learn about the movement to preserve open ecosystems and support developers:
1. Go to **More > Help & Support > Keep Android Open**.
2. **Sign the Petition**: Add your voice to the Change.org petition advocating for user device freedom.
3. **Visit KeepAndroidOpen.org**: Read documentation, analyses, and news on platform openness.
4. **Explore F-Droid**: Discover alternative open-source repositories and free software ecosystems.
5. **FreeDroidWarn**: AttendMate integrates FreeDroidWarn to alert users when OS upgrades threaten sideloading capabilities.
''',
    ),
    _GuideSection(
      title: '20. Background Access',
      openInAppLabel: 'Configure Background Access',
      openTarget: _GuideOpenTarget.batteryOptimization,
      markdown: '''
## Overview
Android battery saver optimization can kill AttendMate when running in the background, causing class reminders, location auto-attendance triggers, and daily automatic backups to stop working after some time.

---

## Why Is Unrestricted Access Required?
1. **Background Notifications**: Ensures class reminders fire reliably even when AttendMate has been closed for hours.
2. **Location Auto-Attendance**: Allows low-power background location checks 5 minutes after class starts.
3. **Automated Backups**: Ensures your daily 10:00 PM rolling backup runs reliably without being killed by Android battery optimization.

---

## How to Grant Exemption
1. Open the **More** tab and scroll to **System > Background Access**.
2. Tap **Fix Access** or the tile to open the prompt.
3. Tap **Get Access** to grant exemption from Android battery optimization.
4. For device-specific guidance (Xiaomi, Samsung, OnePlus, etc.), tap **dontkillmyapp.com Guide**.
''',
    ),
    _GuideSection(
      title: '21. More & App Settings',
      openInAppLabel: 'Open More Page',
      openTarget: _GuideOpenTarget.moreTab,
      markdown: '''
## Overview
The **More** page contains app preferences, integrations, diagnostics, update tools, guide access, and support links.

---

## Available Items
- **Swipe Actions**: Configure left and right swipe actions for attendance cards.
- **Google Integrations**: Centralized Google Account management for Calendar and Drive.
- **Location Manager**: Set up classroom coordinates and auto-attendance geofences.
- **Calendar Sync**: Synchronize schedules to Google or device calendars.
- **Semester Backup**: Rolling local backups, Google Drive backups, and historical attendance import.
- **Diagnostics Log**: In-app operational and error logs.
- **GitHub Discussions**: Community discussions and announcements.
- **Keep Android Open**: Sideloading awareness and petition links.
- **Use 24-hour format** toggle
- **App version & build number**
- **App updates & What's New**
- **Setup Guide & Interactive Tour**
- **Legal**: Privacy Policy and Terms of Service
''',
    ),
    _GuideSection(
      title: '22. Tips & Tricks',
      openInAppLabel: 'Open Today Page',
      openTarget: _GuideOpenTarget.todayTab,
      markdown: '''
## Tips
- Color-code subjects for faster recognition.
- Use **Special Multi-Day Class** for workshops, extra labs, or multi-day guest lectures.
- Use JSON import to save setup time.
- Keep notifications and background permissions enabled for quick marking.
- Use Calendar to fix past mistakes.
- Use **Holiday** when classes are officially cancelled.
- Set up **Google Drive Backup** under Google Integrations to keep your data safe in the cloud.

> All attendance data is stored locally on your device unless you explicitly connect Google Drive.
''',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goToPage(int page) async {
    await _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Future<void> _copyAiPrompt([String? promptText]) async {
    await Clipboard.setData(ClipboardData(text: promptText ?? _aiPrompt));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showReplacingSnackBar(
      const SnackBar(content: Text('AI prompt copied to clipboard.')),
    );
  }

  void _openSectionInApp(_GuideOpenTarget target) {
    switch (target) {
      case _GuideOpenTarget.todayTab:
        return _openHomeTab(0);
      case _GuideOpenTarget.subjectsTab:
        return _openHomeTab(1);
      case _GuideOpenTarget.semesterTab:
        return _openHomeTab(2);
      case _GuideOpenTarget.bunkMeterTab:
        return _openHomeTab(3);
      case _GuideOpenTarget.moreTab:
        return _openHomeTab(4);
      case _GuideOpenTarget.addSubject:
        return _openHomeTab(1, subLevelBuilder: (context) => const AddSubjectScreen());
      case _GuideOpenTarget.importTimetable:
        return _openHomeTab(1, subLevelBuilder: (context) => const UnifiedImportScreen(initialTabIndex: 0));
      case _GuideOpenTarget.calendar:
        return _openHomeTab(0, subLevelBuilder: (context) => const CalendarScreen());
      case _GuideOpenTarget.googleCalendarSync:
        return _openHomeTab(4, subLevelBuilder: (context) => const CalendarSyncSelectionScreen());
      case _GuideOpenTarget.swipeActions:
        return _openHomeTab(4, subLevelBuilder: (context) => const SwipeActionsSettingsScreen());
      case _GuideOpenTarget.locationManager:
        return _openHomeTab(4, subLevelBuilder: (context) => const LocationManagerScreen());
      case _GuideOpenTarget.leavePlanner:
        return _openHomeTab(3, subLevelBuilder: (context) => const LeavePlannerScreen());
      case _GuideOpenTarget.semesterBackup:
        return _openHomeTab(4, subLevelBuilder: (context) => const SemesterBackupScreen());
      case _GuideOpenTarget.importAttendance:
        return _openHomeTab(2, subLevelBuilder: (context) => const UnifiedImportScreen(initialTabIndex: 1));
      case _GuideOpenTarget.googleIntegrations:
        return _openHomeTab(4, subLevelBuilder: (context) => const GoogleIntegrationsScreen());
      case _GuideOpenTarget.githubDiscussions:
        return _openHomeTab(4, subLevelBuilder: (context) => const GitHubDiscussionsScreen());
      case _GuideOpenTarget.keepAndroidOpen:
        return _openHomeTab(4, subLevelBuilder: (context) => const KeepAndroidOpenScreen());
      case _GuideOpenTarget.batteryOptimization:
        BatteryOptimizationService().showBatteryOptimizationDialog(context);
        return;
    }
  }

  void _openHomeTab(
    int tabIndex, {
    WidgetBuilder? subLevelBuilder,
  }) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => HomeScreen(initialPageIndex: tabIndex),
      ),
      (route) => false,
    );

    if (subLevelBuilder != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = navigatorKey.currentState;
        if (nav == null || !nav.mounted) {
          return;
        }
        nav.push(MaterialPageRoute(builder: subLevelBuilder));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final blockquoteBackground = colorScheme.surfaceContainerHighest;
    final codeBackground = colorScheme.surfaceContainerHigh;

    final markdownStyle = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      blockquoteDecoration: BoxDecoration(
        color: blockquoteBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquotePadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: codeBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      code: TextStyle(
        backgroundColor: codeBackground,
      ),
    );

    final totalPages = _sections.length + 1;
    final sectionIndex = _currentPage - 1;
    final appBarTitle = _currentPage == 0
        ? 'Setup Guide'
        : _sections[sectionIndex].title;

    return PopScope(
      canPop: _currentPage == 0,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentPage > 0) {
          await _goToPage(0);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(appBarTitle),
        ),
        body: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (page) {
                  setState(() {
                    _currentPage = page;
                  });
                },
                itemCount: totalPages,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _TableOfContentsPage(
                      sections: _sections,
                      onSelectSection: (section) => _goToPage(section + 1),
                    );
                  }

                  final section = _sections[index - 1];
                  return _GuideSectionPage(
                    markdown: section.markdown,
                    markdownStyle: markdownStyle,
                    aiPromptCopyText: section.aiPromptCopyText,
                    onCopyPrompt: () => _copyAiPrompt(section.aiPromptCopyText),
                    openInAppLabel: section.openInAppLabel,
                    onOpenInApp: section.openTarget == null
                        ? null
                        : () => _openSectionInApp(section.openTarget!),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _currentPage == 0
                        ? null
                        : () => _goToPage(_currentPage - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Center(
                      child: Text('Page ${_currentPage + 1} of $totalPages'),
                    ),
                  ),
                  IconButton(
                    onPressed: _currentPage == totalPages - 1
                        ? null
                        : () => _goToPage(_currentPage + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideSection {
  final String title;
  final String markdown;
  final String? aiPromptCopyText;
  final String? openInAppLabel;
  final _GuideOpenTarget? openTarget;

  _GuideSection({
    required this.title,
    required this.markdown,
    this.aiPromptCopyText,
    this.openInAppLabel,
    this.openTarget,
  });
}

enum _GuideOpenTarget {
  todayTab,
  subjectsTab,
  semesterTab,
  bunkMeterTab,
  moreTab,
  addSubject,
  importTimetable,
  calendar,
  googleCalendarSync,
  swipeActions,
  locationManager,
  leavePlanner,
  semesterBackup,
  importAttendance,
  googleIntegrations,
  githubDiscussions,
  keepAndroidOpen,
  batteryOptimization,
}

class _TableOfContentsPage extends StatelessWidget {
  final List<_GuideSection> sections;
  final ValueChanged<int> onSelectSection;

  const _TableOfContentsPage({
    required this.sections,
    required this.onSelectSection,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'AttendMate — Setup & User Guide',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Swipe like a book, or jump directly using the table of contents.',
        ),
        const SizedBox(height: 16),
        ...List.generate(sections.length, (index) {
          return ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(sections[index].title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onSelectSection(index),
          );
        }),
      ],
    );
  }
}

class _GuideSectionPage extends StatelessWidget {
  final String markdown;
  final MarkdownStyleSheet markdownStyle;
  final String? aiPromptCopyText;
  final VoidCallback onCopyPrompt;
  final String? openInAppLabel;
  final VoidCallback? onOpenInApp;

  const _GuideSectionPage({
    required this.markdown,
    required this.markdownStyle,
    this.aiPromptCopyText,
    required this.onCopyPrompt,
    this.openInAppLabel,
    this.onOpenInApp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (onOpenInApp != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenInApp,
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: Text(openInAppLabel ?? 'Open in App'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MarkdownBody(
                data: markdown,
                styleSheet: markdownStyle,
                selectable: true,
                onTapLink: (text, href, title) {
                  MarkdownLinkHelper.openLink(context, href);
                },
              ),
              if (aiPromptCopyText != null && aiPromptCopyText!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _AiPromptCard(
                    prompt: aiPromptCopyText!,
                    onCopyPrompt: onCopyPrompt,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AiPromptCard extends StatelessWidget {
  final String prompt;
  final VoidCallback onCopyPrompt;

  const _AiPromptCard({
    required this.prompt,
    required this.onCopyPrompt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? colorScheme.surfaceContainerHighest : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Text('AI Prompt', style: theme.textTheme.labelLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: onCopyPrompt,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy'),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              prompt,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}