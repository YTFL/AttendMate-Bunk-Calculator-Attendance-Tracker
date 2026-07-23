import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TutorialRouteAction {
  none,
  addSubject,
  importTimetable,
  calendar,
  bunkCalculator,
  leavePlanner,
}

class TutorialStep {
  final int stepIndex;
  final String title;
  final String description;
  final int? targetTabIndex;
  final String? targetKeyName;
  final EdgeInsets targetPadding;
  final BorderRadius borderRadius;
  final bool isActionRequired;
  final bool preferPositionAbove;

  const TutorialStep({
    required this.stepIndex,
    required this.title,
    required this.description,
    this.targetTabIndex,
    this.targetKeyName,
    this.targetPadding = const EdgeInsets.all(8.0),
    this.borderRadius = const BorderRadius.all(Radius.circular(12.0)),
    this.isActionRequired = false,
    this.preferPositionAbove = false,
  });
}

class TutorialController extends ChangeNotifier {
  static const String prefsKey = 'has_completed_interactive_tutorial_v1';

  final Map<String, GlobalKey> _registeredKeys = {};
  int _currentStepIndex = -1;
  bool _isActive = false;
  Function(int tabIndex)? _tabSwitcher;
  Function(TutorialRouteAction action)? _routeHandler;

  bool get isActive => _isActive;
  int get currentStepIndex => _currentStepIndex;
  int get totalSteps => tutorialSteps.length;
  TutorialStep? get currentStep =>
      (_isActive && _currentStepIndex >= 0 && _currentStepIndex < tutorialSteps.length)
          ? tutorialSteps[_currentStepIndex]
          : null;

  void registerTabSwitcher(Function(int tabIndex) tabSwitcher) {
    _tabSwitcher = tabSwitcher;
  }

  void registerRouteHandler(Function(TutorialRouteAction action) handler) {
    _routeHandler = handler;
  }

  void registerKey(String name, GlobalKey key) {
    _registeredKeys[name] = key;
  }

  GlobalKey? getKey(String? name) {
    if (name == null) return null;
    return _registeredKeys[name];
  }

  Future<void> startTutorial({bool force = false}) async {
    if (!force) {
      final prefs = await SharedPreferences.getInstance();
      final hasCompleted = prefs.getBool(prefsKey) ?? false;
      if (hasCompleted) return;
    }

    _isActive = true;
    _currentStepIndex = 0;
    _onStepChanged(-1, 0);
    notifyListeners();
  }

  void nextStep() {
    if (!_isActive) return;
    if (_currentStepIndex < tutorialSteps.length - 1) {
      final oldIndex = _currentStepIndex;
      _currentStepIndex++;
      _onStepChanged(oldIndex, _currentStepIndex);
      notifyListeners();
    } else {
      completeTutorial();
    }
  }

  void previousStep() {
    if (!_isActive) return;
    if (_currentStepIndex > 0) {
      final oldIndex = _currentStepIndex;
      _currentStepIndex--;
      _onStepChanged(oldIndex, _currentStepIndex);
      notifyListeners();
    }
  }

  void skipTutorial() {
    completeTutorial();
  }

  Future<void> completeTutorial() async {
    _isActive = false;
    _currentStepIndex = -1;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, true);
    } catch (_) {}
  }

  void _onStepChanged(int oldStepIndex, int newStepIndex) {
    final step = currentStep;
    if (step != null && step.targetTabIndex != null && _tabSwitcher != null) {
      _tabSwitcher!(step.targetTabIndex!);
    }

    if (oldStepIndex == 4 && newStepIndex == 5) {
      _routeHandler?.call(TutorialRouteAction.addSubject);
    } else if (oldStepIndex == 10 && newStepIndex == 11) {
      _routeHandler?.call(TutorialRouteAction.importTimetable);
    } else if (oldStepIndex == 15 && newStepIndex == 16) {
      _routeHandler?.call(TutorialRouteAction.calendar);
    } else if (oldStepIndex == 20 && newStepIndex == 21) {
      _routeHandler?.call(TutorialRouteAction.bunkCalculator);
    } else if (oldStepIndex == 22 && newStepIndex == 23) {
      _routeHandler?.call(TutorialRouteAction.leavePlanner);
    }
  }

  static final List<TutorialStep> tutorialSteps = [
    const TutorialStep(
      stepIndex: 0,
      title: 'Welcome to AttendMate!',
      description:
          'Let\'s take a quick guided tour of AttendMate so you can track and manage your attendance effortlessly.',
      targetKeyName: null,
    ),
    const TutorialStep(
      stepIndex: 1,
      title: '1. Go to Semester Setup',
      description:
          'Tap the highlighted "Semester" tab below to open your semester configuration.',
      targetTabIndex: 2,
      targetKeyName: 'nav_tab_semester',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 2,
      title: '2. Set Up Your Semester',
      description:
          'Please select your Start Date, End Date, and Target Attendance % (e.g. 75%), then tap Create Semester to unlock the app.',
      targetTabIndex: 2,
      targetKeyName: 'btn_setup_semester',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
      isActionRequired: true,
    ),
    const TutorialStep(
      stepIndex: 3,
      title: '3. Go to Subjects',
      description:
          'Great! Now tap the highlighted "Subjects" tab below to view and manage your courses.',
      targetTabIndex: 1,
      targetKeyName: 'nav_tab_subjects',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 4,
      title: '4. Add a Subject',
      description:
          'Tap the "+" button to open the subject creator screen.',
      targetTabIndex: 1,
      targetKeyName: 'fab_add_subject',
      borderRadius: BorderRadius.all(Radius.circular(28.0)),
    ),
    const TutorialStep(
      stepIndex: 5,
      title: '5. Subject Name & Acronym',
      description:
          'Enter the Subject Name (e.g. Mathematics) and optional short Acronym (e.g. MTH).',
      targetKeyName: 'key_subject_name',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 6,
      title: '6. Class Location (Geofencing)',
      description:
          'Select a saved room/location for this subject. When inside a 25m radius during class time, auto-attendance logs you Present!',
      targetKeyName: 'key_location_dropdown',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 7,
      title: '7. Special One-Day Class Toggle',
      description:
          'Toggle "Special One-Day Class" for single extra/makeup lectures, or leave off for regular weekly recurring schedules.',
      targetKeyName: 'key_special_toggle',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 8,
      title: '8. Weekly Schedule Time Slots',
      description:
          'Add recurring weekly day & time slots for your lectures (e.g. Mon 9:00 AM - 10:00 AM).',
      targetKeyName: 'key_add_slot',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 9,
      title: '9. Save Subject or Go Back',
      description:
          'Tap "Save" in the top right to save your new subject, or press Next to return to Subjects.',
      targetKeyName: 'key_save_subject',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 10,
      title: '10. Import Timetable & AI Prompt',
      description:
          'Tap the Import icon in the top right of the Subjects screen to import timetable files or copy AI prompts.',
      targetTabIndex: 1,
      targetKeyName: 'appbar_import_timetable',
      borderRadius: BorderRadius.all(Radius.circular(20.0)),
    ),
    const TutorialStep(
      stepIndex: 11,
      title: '11. Paste JSON/CSV or Load File',
      description:
          'Paste timetable JSON/CSV data here, or tap the file import icon inside the box to select a .json/.csv file.',
      targetKeyName: 'key_import_input',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 12,
      title: '12. Export Schedule & Formats',
      description:
          'Tap the menu in the top right to export your timetable as JSON, CSV, or PDF, or copy reference formats.',
      targetKeyName: 'key_export_menu',
      borderRadius: BorderRadius.all(Radius.circular(20.0)),
    ),
    const TutorialStep(
      stepIndex: 13,
      title: '13. Go to Today\'s Schedule',
      description:
          'Tap the highlighted "Today" tab below to see your daily class timeline.',
      targetTabIndex: 0,
      targetKeyName: 'nav_tab_today',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 14,
      title: '14. Marking Attendance via Swipe Gestures',
      description:
          'Swipe class cards Right to mark Present, or Left to mark Absent. Swiping in the same direction again unmarks it! Use the top Holiday / Skip Day buttons for bulk day actions.',
      targetTabIndex: 0,
      targetKeyName: 'nav_tab_today',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 15,
      title: '15. Check Attendance Calendar',
      description:
          'Tap the Calendar icon in the app bar to inspect past dates, fix historical attendance, or mark bulk holidays.',
      targetTabIndex: 0,
      targetKeyName: 'appbar_calendar',
      borderRadius: BorderRadius.all(Radius.circular(20.0)),
    ),
    const TutorialStep(
      stepIndex: 16,
      title: '16. Calendar Month Navigation',
      description:
          'Use month arrows or tap "Today" to jump back to current month and review past/future monthly attendance.',
      targetKeyName: 'key_calendar_header',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 17,
      title: '17. Interactive Legend',
      description:
          'Tap any legend status chip (e.g. Attended, Bunked, Holiday) to filter and highlight matching days on the grid.',
      targetKeyName: 'key_calendar_legend',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 18,
      title: '18. Calendar Day Tiles & Details',
      description:
          'Tap any day tile on the calendar to view attendance records or mark past/future bulk actions. Press Next to return to Today\'s schedule.',
      targetKeyName: 'key_calendar_grid',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
      preferPositionAbove: true,
    ),
    const TutorialStep(
      stepIndex: 19,
      title: '19. Go to Bunk Meter',
      description:
          'Tap the highlighted "Bunk Meter" tab below to check your overall attendance safety status.',
      targetTabIndex: 3,
      targetKeyName: 'nav_tab_bunk_meter',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 20,
      title: '20. Open Bunk Calculator',
      description:
          'Tap the Bunk Calculator button to open scenario simulation.',
      targetTabIndex: 3,
      targetKeyName: 'appbar_bunk_calculator',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 21,
      title: '21. Simulate Bunk Scenarios',
      description:
          'Select a subject, choose future class count, and toggle Attend/Bunk to test scenarios like "What if I bunk the next 3 classes?". Press Next to return.',
      targetKeyName: 'key_bunk_calculator_card',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 22,
      title: '22. Open Leave Planner',
      description:
          'Tap the Leave Planner button to open future event planning.',
      targetTabIndex: 3,
      targetKeyName: 'appbar_leave_planner',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 23,
      title: '23. Schedule Planned Leaves',
      description:
          'Tap "Add Leave" to schedule upcoming fests, medical leaves, or trips and forecast attendance safety impact. Press Next to return to Bunk Meter.',
      targetKeyName: 'key_leave_planner_add',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 24,
      title: '24. Go to More & Settings',
      description:
          'Tap the highlighted "More" tab below to access settings, Location Manager, and Calendar Sync.',
      targetTabIndex: 4,
      targetKeyName: 'nav_tab_more',
      borderRadius: BorderRadius.all(Radius.circular(16.0)),
    ),
    const TutorialStep(
      stepIndex: 25,
      title: '25. Location Auto-Attendance (Geofencing)',
      description:
          'Tap Locations & Geofencing here to set classroom GPS coordinates. Inside a 25m radius 5 mins after class starts, auto-marking logs you Present!',
      targetTabIndex: 4,
      targetKeyName: 'key_location_manager',
      borderRadius: BorderRadius.all(Radius.circular(12.0)),
    ),
    const TutorialStep(
      stepIndex: 26,
      title: '26. Calendar Synchronization',
      description:
          'Tap Calendar Sync here to connect your Google Calendar or sync directly with your phone (Samsung/Outlook/Local calendars).',
      targetTabIndex: 4,
      targetKeyName: 'key_calendar_sync',
      borderRadius: BorderRadius.all(Radius.circular(12.0)),
    ),
    const TutorialStep(
      stepIndex: 27,
      title: '27. Replay Tour Anytime',
      description:
          'Tap Interactive App Tour anytime here in the More tab to restart this guided walkthrough whenever you need a quick refresher!',
      targetTabIndex: 4,
      targetKeyName: 'key_interactive_tour',
      borderRadius: BorderRadius.all(Radius.circular(12.0)),
    ),
    const TutorialStep(
      stepIndex: 28,
      title: '28. Read Detailed Setup Guide',
      description:
          'Tap Setup Guide anytime to read step-by-step documentation on timetable formats, geofencing, swipe gestures, calendar sync, or troubleshooting!',
      targetTabIndex: 4,
      targetKeyName: 'key_setup_guide',
      borderRadius: BorderRadius.all(Radius.circular(12.0)),
    ),
    const TutorialStep(
      stepIndex: 29,
      title: '29. Set Up Semester Backup Folder',
      description:
          'Tap Semester Backup to select a dedicated folder on your device storage. Setting your backup location ensures 3 rolling backups protect your data against accidental deletion or app uninstallation!',
      targetTabIndex: 4,
      targetKeyName: 'key_semester_backup',
      borderRadius: BorderRadius.all(Radius.circular(12.0)),
    ),
    const TutorialStep(
      stepIndex: 30,
      title: 'Tutorial Completed!',
      description:
          'You are now ready to track and optimize your attendance with AttendMate.',
      targetKeyName: null,
    ),
  ];
}
