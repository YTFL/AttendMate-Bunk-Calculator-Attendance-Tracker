import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:ui';

import 'ambient_theme_provider.dart';
import 'refresh_rate_provider.dart';

import 'package:workmanager/workmanager.dart';
import '../../services/backup_service.dart';
import '../../services/calendar_service.dart';
import '../../services/system_calendar_service.dart';
import '../../services/semester_share_service.dart';
import '../../models/app_update_model.dart';
import '../../services/database_service.dart';
import '../../services/update_service.dart';
import '../../services/notification_service.dart';
import '../../services/battery_optimization_service.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/url_launcher_utils.dart';
import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../home/update_dialog.dart';
import '../semester/semester_model.dart';
import '../semester/semester_provider.dart';
import '../semester/live_timetable_sync_screen.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';
import 'calendar_sync_selection_screen.dart';
import 'google_integrations_screen.dart';
import 'github_discussions_screen.dart';
import 'keep_android_open_screen.dart';
import 'setup_guide_screen.dart';
import '../tutorial/tutorial_controller.dart';
import 'time_format_provider.dart';
import 'whats_new_screen.dart';
import 'swipe_actions_settings_screen.dart';
import '../location/location_manager_screen.dart';
import 'diagnostics_log_screen.dart';
import 'markdown_viewer_screen.dart';
import 'semester_backup_screen.dart';
import '../../utils/github_issue_helper.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final UpdateService _updateService = UpdateService();

  late Future<PackageInfo> _packageInfoFuture;
  late Future<DateTime?> _currentVersionReleaseDateFuture;
  AppUpdate? _availableUpdate;
  bool _isCheckingForUpdate = false;
  bool _hasCheckedForUpdate = false;
  bool _devModeCalendarSyncEnabled = false;
  bool? _isBatteryOptimizationIgnoring;

  static const String _issuesUrl =
      'https://github.com/YTFL/AttendMate-Bunk-Calculator-Attendance-Tracker/issues';
  static final String _repoUrl = _issuesUrl.replaceFirst('/issues', '');

  final GlobalKey _locationManagerKey = GlobalKey();
  final GlobalKey _calendarSyncKey = GlobalKey();
  final GlobalKey _semesterBackupKey = GlobalKey();
  final GlobalKey _interactiveTourKey = GlobalKey();
  final GlobalKey _setupGuideKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
    _currentVersionReleaseDateFuture = _loadBundledReleaseDate();
    _checkBatteryOptimizationStatus();
    if (kDebugMode) {
      _loadDevModeCalendarSync();
    }
  }

  Future<void> _checkBatteryOptimizationStatus() async {
    final isIgnoring = await BatteryOptimizationService().isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _isBatteryOptimizationIgnoring = isIgnoring;
      });
    }
  }

  Future<DateTime?> _loadBundledReleaseDate() async {
    try {
      final releaseNotes = await rootBundle.loadString('git_public/RELEASE_NOTES.md');
      final lines = releaseNotes.replaceAll('\r\n', '\n').split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('**Release Date:**')) {
          final dateText = trimmed.replaceFirst('**Release Date:**', '').trim();
          return DateFormat('MMMM d, y').parseStrict(dateText);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<AppUpdate?> _checkForUpdateManually() async {
    setState(() {
      _isCheckingForUpdate = true;
    });

    final update = await _updateService.checkForUpdate(respectDeferral: false);
    if (!mounted) return null;

    setState(() {
      _isCheckingForUpdate = false;
      _hasCheckedForUpdate = true;
      _availableUpdate = update;
    });

    return update;
  }

  Future<void> _onUpdateTileTap() async {
    if (_isCheckingForUpdate) return;

    final update = await _checkForUpdateManually();
    if (!mounted) return;

    if (update == null) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(content: Text('You are already on the latest version.')),
      );
      return;
    }

    await _showUpdateScreen(update);
    if (!mounted) return;

    setState(() {
      _availableUpdate = update;
      _hasCheckedForUpdate = true;
    });
  }

  Future<void> _showUpdateScreen(AppUpdate update) async {
    var isDownloading = false;
    var downloadProgress = 0.0;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => StatefulBuilder(
          builder: (routeContext, routeSetState) => FutureBuilder<PackageInfo>(
            future: _packageInfoFuture,
            builder: (routeContext, snapshot) {
              final currentVersion = snapshot.data?.version ?? '1.0.1';
              return UpdateFullScreen(
                update: update,
                currentVersion: currentVersion,
                isDownloading: isDownloading,
                downloadProgress: downloadProgress,
                onInstallNow: () async {
                  routeSetState(() {
                    isDownloading = true;
                    downloadProgress = 0.0;
                  });

                  final navigator = Navigator.of(routeContext);
                  final messenger = ScaffoldMessenger.of(context);

                  try {
                    final apkFile = await _updateService.downloadAPK(
                      update.version,
                      onProgress: (progress) {
                        if (mounted) {
                          routeSetState(() {
                            downloadProgress = progress;
                          });
                        }
                      },
                    );
                    if (apkFile != null && mounted) {
                      final installResult = await _updateService.installAPK(apkFile);
                      if (!mounted) return;
                      switch (installResult) {
                        case InstallResult.installerStarted:
                          navigator.pop();
                          messenger.showReplacingSnackBar(
                            const SnackBar(
                              content: Text('Installer opened. Complete the update to continue.'),
                            ),
                          );
                          break;
                        case InstallResult.permissionRequired:
                          messenger.showReplacingSnackBar(
                            const SnackBar(
                              content: Text(
                                'Allow installs from this source, then tap Install Now again.',
                              ),
                            ),
                          );
                          break;
                        case InstallResult.installerUnavailable:
                          messenger.showReplacingSnackBar(
                            const SnackBar(
                              content: Text('No installer found to open the APK on this device.'),
                            ),
                          );
                          break;
                        case InstallResult.failed:
                          messenger.showReplacingSnackBar(
                            const SnackBar(
                              content: Text('Failed to launch installer. APK saved for retry.'),
                            ),
                          );
                          break;
                      }
                    } else if (mounted) {
                      messenger.showReplacingSnackBar(
                        const SnackBar(content: Text('Failed to download update')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      messenger.showReplacingSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  } finally {
                    if (mounted) {
                      routeSetState(() {
                        isDownloading = false;
                      });
                    }
                  }
                },
                onRemindLater: () async {
                  try {
                    await _updateService.deferUpdate();
                    if (routeContext.mounted) {
                      Navigator.of(routeContext).pop();
                    }
                  } catch (e) {
                    debugPrint('Error deferring update: $e');
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _loadDevModeCalendarSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _devModeCalendarSyncEnabled = prefs.getBool('dev_mode_calendar_sync_enabled') ?? false;
      });
    } catch (e) {
      debugPrint('Error loading dev mode calendar sync setting: $e');
    }
  }

  Future<void> _toggleDevModeCalendarSync(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('dev_mode_calendar_sync_enabled', value);
      setState(() {
        _devModeCalendarSyncEnabled = value;
      });
    } catch (e) {
      debugPrint('Error toggling dev mode calendar sync setting: $e');
    }
  }

  Future<void> _triggerTestPreClassNotification() async {
    try {
      final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
      final subjects = subjectProvider.subjects;
      
      final notificationService = NotificationService();
      final title = await notificationService
          .triggerTestPreClassNotificationAfter15Seconds(subjects);

      if (!mounted) return;

      if (title != null) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text('Scheduled pre-class reminder ("$title") in 15 seconds.'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('No unmarked classes scheduled for today.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text('Failed to trigger test pre-class notification: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _triggerTestNotification() async {
    try {
      final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
      final subjects = subjectProvider.subjects;
      
      final notificationService = NotificationService();
      final scheduledSubjectName = await notificationService
          .triggerTestNotificationAfter15Seconds(subjects);

      if (!mounted) return;

      if (scheduledSubjectName != null) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text('Test notification for "$scheduledSubjectName" scheduled in 15 seconds.'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('No unmarked classes scheduled for today.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text('Failed to trigger test notification: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _triggerTestBackgroundBackup() async {
    try {
      final hasBackupFolder = await BackupService().hasUserSetBackupDirectory();
      if (!hasBackupFolder) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('Please select a Backup Storage Folder in Semester Backup first.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      await Workmanager().registerOneOffTask(
        'test_background_backup_${DateTime.now().millisecondsSinceEpoch}',
        'testBackgroundBackup',
        initialDelay: const Duration(seconds: 30),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: const Text('Background backup scheduled in 30 seconds! Close the app now to test.'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text('Failed to schedule test background backup: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDemoGenerationConfirmation() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Generate Timetable Data?'),
          content: const Text(
            'This will clear all current semester, subject, and attendance data, and replace it with a test timetable. Choose duration:',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _generateDemoTimetable(justToday: true);
              },
              child: const Text('Just Today'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _generateDemoTimetable(justToday: false);
              },
              child: const Text('120-Day Semester', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _showClearDataConfirmation() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear All App Data?'),
          content: const Text(
            'This will permanently delete your database and clear all user settings. Proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _clearAppData();
              },
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _generateDemoTimetable({required bool justToday}) async {
    try {
      final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
      final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
      final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);

      await DatabaseService().clearSemesterAndAllData();

      final today = DateTime.now();
      final todayNormalized = DateTime(today.year, today.month, today.day);
      final startDate = justToday ? todayNormalized : todayNormalized.subtract(const Duration(days: 60));
      final endDate = justToday ? todayNormalized : todayNormalized.add(const Duration(days: 60));
      
      final semester = Semester(
        startDate: startDate,
        endDate: endDate,
        targetPercentage: 75.0,
      );

      await semesterProvider.createNewSemester(semester);

      final subjectsData = [
        {'name': 'Mathematics', 'acronym': 'MATH', 'color': Colors.blue},
        {'name': 'Physics', 'acronym': 'PHYS', 'color': Colors.red},
        {'name': 'Chemistry', 'acronym': 'CHEM', 'color': Colors.green},
        {'name': 'Computer Science', 'acronym': 'CS', 'color': Colors.deepPurple},
        {'name': 'English', 'acronym': 'ENGL', 'color': Colors.orange},
        {'name': 'Technical Comm.', 'acronym': 'TECH', 'color': Colors.teal},
      ];

      final dailySchedule = [
        [0, 1, 2, 3, 4], // Mon
        [1, 2, 3, 4, 5], // Tue
        [2, 3, 4, 5, 0], // Wed
        [3, 4, 5, 0, 1], // Thu
        [4, 5, 0, 1, 2], // Fri
        [0, 1, 2, 3, 4], // Sat
        [1, 2, 3, 4, 5], // Sun
      ];

      final Map<int, List<TimeSlot>> subjectSchedules = {};
      for (int sIdx = 0; sIdx < subjectsData.length; sIdx++) {
        subjectSchedules[sIdx] = [];
      }

      final times = [
        {'start': const TimeOfDay(hour: 9, minute: 0), 'end': const TimeOfDay(hour: 10, minute: 0)},
        {'start': const TimeOfDay(hour: 10, minute: 0), 'end': const TimeOfDay(hour: 11, minute: 0)},
        {'start': const TimeOfDay(hour: 11, minute: 0), 'end': const TimeOfDay(hour: 12, minute: 0)},
        {'start': const TimeOfDay(hour: 13, minute: 0), 'end': const TimeOfDay(hour: 14, minute: 0)},
        {'start': const TimeOfDay(hour: 14, minute: 0), 'end': const TimeOfDay(hour: 15, minute: 0)},
      ];

      for (int dayIdx = 0; dayIdx < dailySchedule.length; dayIdx++) {
        final dayOfWeek = DayOfWeek.values[dayIdx];
        final daySlots = dailySchedule[dayIdx];

        for (int slotIdx = 0; slotIdx < daySlots.length; slotIdx++) {
          final subIdx = daySlots[slotIdx];
          final time = times[slotIdx];

          subjectSchedules[subIdx]!.add(
            TimeSlot(
              day: dayOfWeek,
              startTime: time['start']!,
              endTime: time['end']!,
            ),
          );
        }
      }

      final List<Subject> generatedSubjects = [];
      final List<Attendance> allAttendance = [];
      final random = Random();

      for (int sIdx = 0; sIdx < subjectsData.length; sIdx++) {
        final sub = subjectsData[sIdx];
        final subjectId = uuid.v4();
        final schedule = subjectSchedules[sIdx]!;

        final List<Attendance> subjectAttendance = [];
        final limit = justToday ? 0 : 60;
        for (int i = 0; i < limit; i++) {
          final date = startDate.add(Duration(days: i));
          for (final slot in schedule) {
            if (slot.occursOnDate(date)) {
              final status = random.nextDouble() < 0.70
                  ? AttendanceStatus.attended
                  : AttendanceStatus.absent;

              final att = Attendance(
                subjectId: subjectId,
                date: date,
                status: status,
                slotKey: slot.slotKey,
              );
              subjectAttendance.add(att);
              allAttendance.add(att);
            }
          }
        }

        generatedSubjects.add(
          Subject(
            id: subjectId,
            name: sub['name'] as String,
            acronym: sub['acronym'] as String?,
            color: sub['color'] as Color,
            schedule: schedule,
            targetAttendance: 75,
            attendanceRecords: subjectAttendance,
          ),
        );
      }

      await DatabaseService().saveSubjects(generatedSubjects);
      await DatabaseService().saveAttendance(allAttendance);

      await semesterProvider.loadSemester();
      await subjectProvider.reloadSubjects();
      await attendanceProvider.reloadAttendance();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              justToday
                  ? 'Demo timetable for today generated successfully!'
                  : 'Demo timetable and attendance generated successfully!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating demo data: $e')),
        );
      }
    }
  }

  Future<void> _clearAppData() async {
    try {
      final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
      final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
      final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);

      if (kDebugMode) {
        final prefs = await SharedPreferences.getInstance();
        final isDevSyncEnabled = prefs.getBool('dev_mode_calendar_sync_enabled') ?? false;
        if (isDevSyncEnabled) {
          final semester = semesterProvider.semester;
          
          // Delete from System Calendar
          try {
            await SystemCalendarService.deleteSyncedEvents(force: true);
          } catch (e) {
            debugPrint('Failed to clear device calendar: $e');
          }

          // Delete from Google Calendar
          try {
            await CalendarService.deleteAllSyncedEvents(semester, force: true);
          } catch (e) {
            debugPrint('Failed to clear google calendar: $e');
          }
        }
      }

      await DatabaseService().clearSemesterAndAllData();

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      await semesterProvider.loadSemester();
      await subjectProvider.reloadSubjects();
      await attendanceProvider.reloadAttendance();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App data cleared successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing app data: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    tutorialController.registerKey('key_location_manager', _locationManagerKey);
    tutorialController.registerKey('key_calendar_sync', _calendarSyncKey);
    tutorialController.registerKey('key_semester_backup', _semesterBackupKey);
    tutorialController.registerKey('key_interactive_tour', _interactiveTourKey);
    tutorialController.registerKey('key_setup_guide', _setupGuideKey);

    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final chevronIcon = Icon(
      Icons.chevron_right_rounded,
      size: 18,
      color: isDarkMode ? const Color(0xFF636366) : const Color(0xFF8E8E93),
    );

    final ambientProvider = Provider.of<AmbientThemeProvider>(context);
    final refreshRateProvider = Provider.of<RefreshRateProvider>(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
      children: [
        _buildSectionHeader('Customization & Gestures', isDarkMode),
        _buildGroupCard(
          isDarkMode: isDarkMode,
          children: [
            _buildAmbientThemeControl(context, ambientProvider, isDarkMode),
            _buildTileDivider(isDarkMode),
            _buildRefreshRateControl(context, refreshRateProvider, isDarkMode),
            _buildTileDivider(isDarkMode),
            ListTile(
              leading: _buildLeadingIcon(Icons.schedule_outlined, isDarkMode),
              title: Text(
                'Use 24-hour format',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                timeFormatProvider.is24Hour ? 'Currently: 24-hour' : 'Currently: 12-hour (AM/PM)',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: Switch(
                value: timeFormatProvider.is24Hour,
                onChanged: (value) {
                  if (value) {
                    timeFormatProvider.set24HourFormat();
                  } else {
                    timeFormatProvider.set12HourFormat();
                  }
                },
              ),
              onTap: () {
                if (timeFormatProvider.is24Hour) {
                  timeFormatProvider.set12HourFormat();
                } else {
                  timeFormatProvider.set24HourFormat();
                }
              },
            ),
            _buildTileDivider(isDarkMode),
            ListTile(
              leading: _buildLeadingIcon(Icons.timer_outlined, isDarkMode),
              title: Text(
                'Time picker style',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                'Currently: ${timeFormatProvider.clockStyleDisplayName}',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: chevronIcon,
              onTap: () {
                showDialog<void>(
                  context: context,
                  barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
                  builder: (ctx) {
                    return AlertDialog(
                      title: const Text('Select Time Picker Style'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioGroup<ClockStyle>(
                            groupValue: timeFormatProvider.clockStyle,
                            onChanged: (val) {
                              if (val != null) {
                                timeFormatProvider.setClockStyle(val);
                                Navigator.pop(ctx);
                              }
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                RadioListTile<ClockStyle>(
                                  title: Text('Material Dialog'),
                                  value: ClockStyle.material,
                                ),
                                RadioListTile<ClockStyle>(
                                  title: Text('Scroll Wheel'),
                                  value: ClockStyle.scroll,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            _buildTileDivider(isDarkMode),
            ListTile(
              leading: _buildLeadingIcon(Icons.swipe_outlined, isDarkMode),
              title: Text(
                'Swipe Actions',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                'Customize swipe gestures for your daily classes',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: chevronIcon,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SwipeActionsSettingsScreen()),
                );
              },
            ),
          ],
        ),

        _buildSectionHeader('Features & Integrations', isDarkMode),
        _buildGroupCard(
          isDarkMode: isDarkMode,
          children: [
            KeyedSubtree(
              key: _locationManagerKey,
              child: ListTile(
                leading: _buildLeadingIcon(Icons.pin_drop_outlined, isDarkMode),
                title: Text(
                  'Locations & Geofencing',
                  style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                ),
                subtitle: Text(
                  'Manage classroom coordinates and auto-attendance',
                  style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
                ),
                trailing: chevronIcon,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LocationManagerScreen()),
                  );
                },
              ),
            ),
            _buildTileDivider(isDarkMode),
            ListTile(
              leading: _buildLeadingIcon(Icons.hub_outlined, isDarkMode),
              title: Text(
                'Google Integrations',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                'Account connection, Drive cloud backup, & Calendar sync',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: chevronIcon,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GoogleIntegrationsScreen()),
                );
              },
            ),
            _buildTileDivider(isDarkMode),
            KeyedSubtree(
              key: _calendarSyncKey,
              child: ListTile(
                enabled: !(kDebugMode && !_devModeCalendarSyncEnabled),
                leading: _buildLeadingIcon(Icons.sync, isDarkMode),
                title: Text(
                  'Calendar Sync',
                  style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                ),
                subtitle: Text(
                  'Sync your timetable with Google or Device Calendar',
                  style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
                ),
                trailing: chevronIcon,
                onTap: (kDebugMode && !_devModeCalendarSyncEnabled)
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const CalendarSyncSelectionScreen()),
                        );
                      },
              ),
            ),
            _buildTileDivider(isDarkMode),
            KeyedSubtree(
              key: _semesterBackupKey,
              child: ListTile(
                leading: _buildLeadingIcon(Icons.backup_outlined, isDarkMode),
                title: Text(
                  'Semester Backup',
                  style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                ),
                subtitle: Text(
                  'Backup & restore attendance data (3 rolling backups kept)',
                  style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
                ),
                trailing: chevronIcon,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SemesterBackupScreen()),
                  );
                },
              ),
            ),
            _buildTileDivider(isDarkMode),
            ListTile(
              leading: _buildLeadingIcon(Icons.cloud_sync_outlined, isDarkMode),
              title: Text(
                'Classroom Timetable & Sharing',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                'Live sync via Google Drive & one-time semester share',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: chevronIcon,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LiveTimetableSyncScreen()),
                );
              },
            ),
          ],
        ),

        _buildSectionHeader('Help & Support', isDarkMode),
        _buildGroupCard(
          isDarkMode: isDarkMode,
          children: [
            KeyedSubtree(
              key: _interactiveTourKey,
              child: ListTile(
                leading: _buildLeadingIcon(Icons.explore_outlined, isDarkMode),
                title: Text(
                  'Interactive App Tour',
                  style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                ),
                subtitle: Text(
                  'Take the guided feature walkthrough',
                  style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
                ),
                trailing: const Icon(Icons.play_arrow_rounded, size: 20),
                onTap: () {
                  Provider.of<TutorialController>(context, listen: false).startTutorial(force: true);
                },
              ),
            ),
            _buildTileDivider(isDarkMode),
            KeyedSubtree(
              key: _setupGuideKey,
              child: ListTile(
                leading: _buildLeadingIcon(Icons.menu_book_outlined, isDarkMode),
                title: Text(
                  'Setup Guide',
                  style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                ),
                subtitle: Text(
                  'Learn how to import schedules, set up geofencing, sync calendars, and more',
                  style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
                ),
                trailing: chevronIcon,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SetupGuideScreen()),
                  );
                },
              ),
            ),
            _buildTileDivider(isDarkMode),
            FutureBuilder<PackageInfo>(
              future: _packageInfoFuture,
              builder: (context, snapshot) {
                final version = snapshot.data?.version;

                return ListTile(
                  leading: _buildLeadingIcon(Icons.new_releases_outlined, isDarkMode),
                  title: Text(
                    'What\'s New',
                    style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                  ),
                  subtitle: Text(
                    version == null
                        ? 'See updates in your installed version'
                        : 'See updates in v$version',
                    style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
                  ),
                  trailing: chevronIcon,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const WhatsNewScreen()),
                    );
                  },
                );
              },
            ),
            _buildTileDivider(isDarkMode),
            ListTile(
              leading: _buildLeadingIcon(Icons.forum_outlined, isDarkMode),
              title: Text(
                'GitHub Discussions',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                'Connect with the community, announcements, & Q&A',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: chevronIcon,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GitHubDiscussionsScreen()),
                );
              },
            ),
            _buildTileDivider(isDarkMode),
            ListTile(
              leading: _buildLeadingIcon(Icons.shield_outlined, isDarkMode),
              title: Text(
                'Keep Android Open',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                'Sideloading restrictions alert, petition, & FreeDroidWarn',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: chevronIcon,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const KeepAndroidOpenScreen()),
                );
              },
            ),
            _buildTileDivider(isDarkMode),
            ListTile(
              leading: _buildLeadingIcon(Icons.favorite_border_outlined, isDarkMode),
              title: Text(
                'Support me',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                'Star repo or share AttendMate with others',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: chevronIcon,
              onTap: () {
                showDialog(
                  context: context,
                  barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
                  builder: (dialogContext) {
                    return AlertDialog(
                      title: const Text('Support AttendMate'),
                      content: const Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AttendMate is 100% free and open-source. Help support the project by starring the repository or sharing the app with classmates and friends!',
                            style: TextStyle(fontSize: 14, height: 1.4),
                          ),
                        ],
                      ),
                      actions: [
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.star_rounded, size: 20),
                                label: const Text('Star My Repo'),
                                onPressed: () async {
                                  Navigator.of(dialogContext).pop();
                                  final result = await UrlLauncherUtils.launchExternalUrl(
                                    _repoUrl,
                                    context: context,
                                  );
                                  if (!context.mounted) return;
                                  if (result == LaunchResult.failed) {
                                    ScaffoldMessenger.of(context).showReplacingSnackBar(
                                      const SnackBar(content: Text('Could not open the repository page.')),
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              icon: const Icon(Icons.share_rounded, size: 20),
                              tooltip: 'Share App',
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                SemesterShareService().shareAppWithOthers(context);
                              },
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            _buildTileDivider(isDarkMode),
            ListTile(
              leading: _buildLeadingIcon(Icons.bug_report_outlined, isDarkMode),
              title: Text(
                'Request feature / Report bug',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                'Submit feedback or suggest improvements',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: chevronIcon,
              onTap: () {
                showDialog(
                  context: context,
                  barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
                  builder: (dialogContext) {
                    return AlertDialog(
                      title: const Text('Request Feature or Report Bug'),
                      content: const Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Please create a new issue on my GitHub Issues page.'),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () async {
                            Navigator.of(dialogContext).pop();
                            final result = await UrlLauncherUtils.launchExternalUrl(
                              _issuesUrl,
                              context: context,
                            );
                            if (!context.mounted) return;
                            if (result == LaunchResult.failed) {
                              ScaffoldMessenger.of(context).showReplacingSnackBar(
                                const SnackBar(content: Text('Could not open the issues page.')),
                              );
                            }
                          },
                          child: const Text('Open Issues Page'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),

        _buildSectionHeader('System', isDarkMode),
        _buildGroupCard(
          isDarkMode: isDarkMode,
          children: [
            ListTile(
              leading: _buildLeadingIcon(
                _isBatteryOptimizationIgnoring == true
                    ? Icons.battery_charging_full_rounded
                    : Icons.battery_alert_rounded,
                isDarkMode,
                accentColor: _isBatteryOptimizationIgnoring == false ? Colors.orange.shade800 : null,
              ),
              title: Text(
                'Background Access',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                _isBatteryOptimizationIgnoring == null
                    ? 'Checking background access status...'
                    : _isBatteryOptimizationIgnoring!
                        ? 'Granted (Optimal background execution)'
                        : 'Restricted (Tap to allow & view device guides)',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: _isBatteryOptimizationIgnoring == false
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(38),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withAlpha(102)),
                      ),
                      child: const Text(
                        'Fix Access',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    )
                  : chevronIcon,
              onTap: () {
                BatteryOptimizationService().showBatteryOptimizationDialog(
                  context,
                  onStatusChanged: _checkBatteryOptimizationStatus,
                );
              },
            ),
            _buildTileDivider(isDarkMode),
            ListTile(
              leading: _buildLeadingIcon(
                _availableUpdate != null
                    ? Icons.system_update_alt_outlined
                    : Icons.system_update_outlined,
                isDarkMode,
              ),
              title: Text(
                'App updates',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                kDebugMode
                    ? 'Unavailable in debug mode'
                    : _isCheckingForUpdate
                        ? 'Checking for updates...'
                        : _availableUpdate != null
                            ? 'Update to v${_availableUpdate!.version}'
                            : _hasCheckedForUpdate
                                ? 'You are on the latest version'
                                : 'Tap to check for updates',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: kDebugMode
                  ? null
                  : _isCheckingForUpdate
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _availableUpdate != null
                          ? const _UpdateAvailableBadge()
                          : chevronIcon,
              onTap: kDebugMode || _isCheckingForUpdate ? null : _onUpdateTileTap,
            ),
            _buildTileDivider(isDarkMode),
            FutureBuilder<PackageInfo>(
              future: _packageInfoFuture,
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? 'Loading...';
                final buildNumber = snapshot.data?.buildNumber ?? 'Loading...';

                return ListTile(
                  leading: _buildLeadingIcon(Icons.info_outline, isDarkMode),
                  title: Text(
                    'App version',
                    style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                  ),
                  subtitle: Text(
                    'v$version (Build $buildNumber)',
                    style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
                  ),
                );
              },
            ),
            _buildTileDivider(isDarkMode),
            FutureBuilder<DateTime?>(
              future: _currentVersionReleaseDateFuture,
              builder: (context, snapshot) {
                final releaseDate = snapshot.data;
                final subtitle = releaseDate != null
                    ? DateFormat.yMMMd().format(releaseDate)
                    : (snapshot.connectionState == ConnectionState.waiting
                        ? 'Loading...'
                        : 'Unavailable');

                return ListTile(
                  leading: _buildLeadingIcon(Icons.update_outlined, isDarkMode),
                  title: Text(
                    'Current version release date',
                    style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                  ),
                  subtitle: Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
                  ),
                );
              },
            ),
            _buildTileDivider(isDarkMode),
            ListTile(
              leading: _buildLeadingIcon(Icons.terminal_outlined, isDarkMode),
              title: Text(
                'Diagnostics Log',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                'View app events, logs, and report issues on GitHub',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: chevronIcon,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DiagnosticsLogScreen()),
                );
              },
            ),
          ],
        ),

        _buildSectionHeader('Privacy & Terms', isDarkMode),
        _buildGroupCard(
          isDarkMode: isDarkMode,
          children: [
            ListTile(
              leading: _buildLeadingIcon(Icons.privacy_tip_outlined, isDarkMode),
              title: Text(
                'Privacy Policy',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                'Read how your data and location permissions are protected',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: chevronIcon,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MarkdownViewerScreen(
                      title: 'Privacy Policy',
                      assetPath: 'git_public/privacy.md',
                    ),
                  ),
                );
              },
            ),
            _buildTileDivider(isDarkMode),
            ListTile(
              leading: _buildLeadingIcon(Icons.gavel_outlined, isDarkMode),
              title: Text(
                'Terms of Service',
                style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
              ),
              subtitle: Text(
                'Terms and conditions for using AttendMate',
                style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              trailing: chevronIcon,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MarkdownViewerScreen(
                      title: 'Terms of Service',
                      assetPath: 'git_public/terms.md',
                    ),
                  ),
                );
              },
            ),
          ],
        ),

        if (kDebugMode) ...[
          _buildSectionHeader('Developer Options', isDarkMode),
          _buildGroupCard(
            isDarkMode: isDarkMode,
            children: [
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  key: const PageStorageKey<String>('developer_options_tile'),
                  initiallyExpanded: false,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  childrenPadding: EdgeInsets.zero,
                  leading: _buildLeadingIcon(Icons.terminal_rounded, isDarkMode, accentColor: Colors.redAccent),
                  title: Text(
                    'Developer Tools',
                    style: GoogleFonts.roboto(fontWeight: FontWeight.w600, fontSize: 14.5),
                  ),
                  subtitle: Text(
                    'Tap to expand debug tools, simulations, & tests',
                    style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
                  ),
                  iconColor: isDarkMode ? Colors.white : Colors.black,
                  collapsedIconColor: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                  children: [
                    _buildTileDivider(isDarkMode),
                    ListTile(
                      leading: _buildLeadingIcon(Icons.bug_report_outlined, isDarkMode, accentColor: Colors.red),
                      title: Text(
                        'Test GitHub Issue Handler',
                        style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                      ),
                      subtitle: const Text('Triggers a test diagnostic log report using the new GitHub template'),
                      onTap: _testGitHubIssueHandler,
                    ),
                    _buildTileDivider(isDarkMode),
                    ListTile(
                      leading: _buildLeadingIcon(Icons.system_update_outlined, isDarkMode, accentColor: Colors.red),
                      title: Text(
                        'Simulate Update Screen',
                        style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                      ),
                      subtitle: const Text('Fetch latest release from GitHub and test the update UI & progress'),
                      onTap: _simulateUpdateScreen,
                    ),
                    _buildTileDivider(isDarkMode),
                    ListTile(
                      leading: _buildLeadingIcon(Icons.sync, isDarkMode, accentColor: Colors.red),
                      title: Text(
                        'Enable Calendar Sync (Debug)',
                        style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                      ),
                      subtitle: const Text('Allows syncing generated timetable to Google/Device calendar during testing'),
                      trailing: Switch(
                        value: _devModeCalendarSyncEnabled,
                        onChanged: _toggleDevModeCalendarSync,
                        activeThumbColor: Colors.red,
                      ),
                      onTap: () => _toggleDevModeCalendarSync(!_devModeCalendarSyncEnabled),
                    ),
                    _buildTileDivider(isDarkMode),
                    ListTile(
                      leading: _buildLeadingIcon(Icons.meeting_room_outlined, isDarkMode, accentColor: Colors.red),
                      title: Text(
                        'Trigger Test Pre-Class Notification (15s)',
                        style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                      ),
                      subtitle: const Text('Schedules a 5-min location reminder for today\'s next class in 15 seconds'),
                      onTap: _triggerTestPreClassNotification,
                    ),
                    _buildTileDivider(isDarkMode),
                    ListTile(
                      leading: _buildLeadingIcon(Icons.notification_important_outlined, isDarkMode, accentColor: Colors.red),
                      title: Text(
                        'Trigger Test Notification (15s)',
                        style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                      ),
                      subtitle: const Text('Schedules a reminder for the most recent unmarked class of today in 15 seconds'),
                      onTap: _triggerTestNotification,
                    ),
                    _buildTileDivider(isDarkMode),
                    ListTile(
                      leading: _buildLeadingIcon(Icons.backup_outlined, isDarkMode, accentColor: Colors.red),
                      title: Text(
                        'Trigger Test Background Backup (30s)',
                        style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                      ),
                      subtitle: const Text('Schedules a WorkManager background backup in 30 seconds. Close the app to test.'),
                      onTap: _triggerTestBackgroundBackup,
                    ),
                    _buildTileDivider(isDarkMode),
                    ListTile(
                      leading: _buildLeadingIcon(Icons.playlist_add_check_outlined, isDarkMode, accentColor: Colors.red),
                      title: Text(
                        'Generate Timetable Data',
                        style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                      ),
                      subtitle: const Text('Generates 120-day semester or just today\'s timetable (5 classes/day)'),
                      onTap: _showDemoGenerationConfirmation,
                    ),
                    _buildTileDivider(isDarkMode),
                    ListTile(
                      leading: _buildLeadingIcon(Icons.delete_forever_outlined, isDarkMode, accentColor: Colors.red),
                      title: Text(
                        'Clear App Data',
                        style: GoogleFonts.roboto(fontWeight: FontWeight.w500, fontSize: 14.5),
                      ),
                      subtitle: const Text('Wipes DB and SharedPreferences immediately'),
                      onTap: _showClearDataConfirmation,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _testGitHubIssueHandler() async {
    await GitHubIssueHelper.createIssueFromLog(
      context: context,
      tag: 'DeveloperDiagnosticsTest',
      message:
          'Test diagnostic log generated from Developer Options to verify GitHub issue pre-filling and template integration.',
      level: 'ERROR',
      errorStackTrace:
          'TestStackTrace: line 42 at _testGitHubIssueHandler(more_screen.dart)',
    );
  }

  Future<void> _simulateUpdateScreen() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showReplacingSnackBar(
      const SnackBar(
        content: Text('Fetching latest release from GitHub...'),
        duration: Duration(seconds: 1),
      ),
    );

    final update = await _updateService.fetchLatestReleaseForSimulation();
    if (!mounted) return;

    var isDownloading = false;
    var downloadProgress = 0.0;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => StatefulBuilder(
          builder: (routeContext, routeSetState) => FutureBuilder<PackageInfo>(
            future: _packageInfoFuture,
            builder: (routeContext, snapshot) {
              final currentVersion = snapshot.data?.version ?? '1.0.1';
              return UpdateFullScreen(
                update: update,
                currentVersion: currentVersion,
                isDownloading: isDownloading,
                downloadProgress: downloadProgress,
                onInstallNow: () async {
                  routeSetState(() {
                    isDownloading = true;
                    downloadProgress = 0.0;
                  });

                  const totalSteps = 30;
                  for (var i = 1; i <= totalSteps; i++) {
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (!routeContext.mounted) return;
                    routeSetState(() {
                      downloadProgress = i / totalSteps;
                    });
                  }

                  if (!routeContext.mounted) return;

                  ScaffoldMessenger.of(routeContext).showReplacingSnackBar(
                    const SnackBar(
                      content: Text('Simulated download complete! (Installation skipped in debug mode)'),
                    ),
                  );
                  Navigator.of(routeContext).pop();
                },
                onRemindLater: () {
                  Navigator.of(routeContext).pop();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildAmbientThemeControl(
    BuildContext context,
    AmbientThemeProvider ambientProvider,
    bool isDarkMode,
  ) {
    final mode = ambientProvider.mode;
    final isAmoled = ambientProvider.isAmoled;
    final isDynamic = ambientProvider.isDynamic;
    final isAccent = ambientProvider.isAccent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              _buildLeadingIcon(
                isAmoled
                    ? Icons.contrast_rounded
                    : (isDynamic ? Icons.auto_mode_rounded : Icons.palette_outlined),
                isDarkMode,
                accentColor: isAmoled
                    ? (isDarkMode ? Colors.white : Colors.black)
                    : (isDynamic ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Atmosphere & Theme',
                      style: GoogleFonts.roboto(fontWeight: FontWeight.w600, fontSize: 14.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isDynamic
                          ? 'Dynamic Time-Cycle (Adapts to morning, dusk, night)'
                          : (isAmoled
                              ? 'Pure AMOLED Black (Zero glow, saves battery)'
                              : ambientProvider.displayName),
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.tune_rounded,
                  size: 19,
                  color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                ),
                tooltip: 'All Themes',
                onPressed: () => _showAmbientThemeModal(context, ambientProvider, isDarkMode),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Redesigned Segmented Toggle System
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                // 1. Dynamic Toggle Segment
                Expanded(
                  child: _buildThemeSegmentButton(
                    title: 'Dynamic',
                    icon: Icons.auto_mode_rounded,
                    isSelected: isDynamic,
                    isDarkMode: isDarkMode,
                    activeColor: const Color(0xFF38BDF8),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ambientProvider.setMode(AmbientThemeMode.dynamicCycle);
                    },
                  ),
                ),
                const SizedBox(width: 4),

                // 2. AMOLED Toggle Segment
                Expanded(
                  child: _buildThemeSegmentButton(
                    title: 'AMOLED',
                    icon: Icons.contrast_rounded,
                    isSelected: isAmoled,
                    isDarkMode: isDarkMode,
                    activeColor: isDarkMode ? Colors.white : Colors.black,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ambientProvider.setMode(AmbientThemeMode.amoled);
                    },
                  ),
                ),
                const SizedBox(width: 4),

                // 3. Mood / Accent Toggle Segment
                Expanded(
                  child: _buildThemeSegmentButton(
                    title: 'Mood',
                    icon: Icons.palette_outlined,
                    isSelected: isAccent,
                    isDarkMode: isDarkMode,
                    activeColor: const Color(0xFFF59E0B),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      if (!isAccent) {
                        ambientProvider.setMode(AmbientThemeMode.night);
                      } else {
                        _showAmbientThemeModal(context, ambientProvider, isDarkMode);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),

          // Sub-mood presets when Mood / Accent is active
          if (isAccent) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildMoodPresetPill(
                    label: 'Dawn',
                    mode: AmbientThemeMode.morning,
                    currentMode: mode,
                    color: const Color(0xFFF59E0B),
                    icon: Icons.wb_sunny_rounded,
                    isDarkMode: isDarkMode,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ambientProvider.setMode(AmbientThemeMode.morning);
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMoodPresetPill(
                    label: 'Sunset',
                    mode: AmbientThemeMode.afternoon,
                    currentMode: mode,
                    color: const Color(0xFFEA580C),
                    icon: Icons.wb_twilight_rounded,
                    isDarkMode: isDarkMode,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ambientProvider.setMode(AmbientThemeMode.afternoon);
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildMoodPresetPill(
                    label: 'Twilight',
                    mode: AmbientThemeMode.night,
                    currentMode: mode,
                    color: const Color(0xFF3B82F6),
                    icon: Icons.nights_stay_rounded,
                    isDarkMode: isDarkMode,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ambientProvider.setMode(AmbientThemeMode.night);
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThemeSegmentButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required bool isDarkMode,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDarkMode
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.10),
                  width: 0.8,
                )
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14.5,
              color: isSelected
                  ? activeColor
                  : (isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
            ),
            const SizedBox(width: 5),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (isDarkMode ? Colors.white : Colors.black)
                    : (isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoodPresetPill({
    required String label,
    required AmbientThemeMode mode,
    required AmbientThemeMode currentMode,
    required Color color,
    required IconData icon,
    required bool isDarkMode,
    required VoidCallback onTap,
  }) {
    final isSelected = mode == currentMode;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDarkMode ? 0.22 : 0.15)
              : (isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.55)
                : (isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
            width: isSelected ? 1.0 : 0.6,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : (isDarkMode ? Colors.white70 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAmbientThemeModal(
    BuildContext context,
    AmbientThemeProvider ambientProvider,
    bool isDarkMode,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: isDarkMode ? Colors.black.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.3),
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF0C0C12).withValues(alpha: 0.75)
                    : Colors.white.withValues(alpha: 0.82),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: isDarkMode
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.black.withValues(alpha: 0.10),
                    width: 1.0,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.25)
                            : Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        size: 20,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Atmosphere & Ambient Themes',
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose real-time ambient lighting or clean pitch-black AMOLED.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ...AmbientThemeMode.values.map((mode) {
                    final isSelected = ambientProvider.mode == mode;
                    String title;
                    String desc;
                    IconData icon;
                    Color accent;
                    Gradient? previewGradient;

                    switch (mode) {
                      case AmbientThemeMode.dynamicCycle:
                        title = 'Dynamic (Time-Based)';
                        desc = 'Transitions automatically with morning, sunset, and night cycles.';
                        icon = Icons.auto_mode_rounded;
                        accent = const Color(0xFF38BDF8);
                        previewGradient = const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFEA580C), Color(0xFF3B82F6)],
                        );
                        break;
                      case AmbientThemeMode.morning:
                        title = 'Morning Golden Dawn';
                        desc = 'Always illuminated with vibrant golden amber dawn warmth.';
                        icon = Icons.wb_sunny_rounded;
                        accent = const Color(0xFFF59E0B);
                        previewGradient = const LinearGradient(
                          colors: [Color(0xFFFEF3C7), Color(0xFFF59E0B)],
                        );
                        break;
                      case AmbientThemeMode.afternoon:
                        title = 'Afternoon Sunset Coral';
                        desc = 'Always bathed in warm radiant sunset orange hues.';
                        icon = Icons.wb_twilight_rounded;
                        accent = const Color(0xFFEA580C);
                        previewGradient = const LinearGradient(
                          colors: [Color(0xFFFFEDD5), Color(0xFFEA580C)],
                        );
                        break;
                      case AmbientThemeMode.night:
                        title = 'Blue Night Twilight';
                        desc = 'Always bathed in deep midnight sapphire dark blue tones.';
                        icon = Icons.nights_stay_rounded;
                        accent = const Color(0xFF3B82F6);
                        previewGradient = const LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                        );
                        break;
                      case AmbientThemeMode.amoled:
                        title = 'Clean Minimal AMOLED Black';
                        desc = 'Turns off all ambient gradients for true pitch-black OLED clarity.';
                        icon = Icons.contrast_rounded;
                        accent = isDarkMode ? Colors.white : Colors.black;
                        previewGradient = null; // pure black
                        break;
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ambientProvider.setMode(mode);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isDarkMode
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.08))
                                : (isDarkMode
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : Colors.black.withValues(alpha: 0.03)),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? (isDarkMode ? Colors.white : Colors.black)
                                  : (isDarkMode
                                      ? Colors.white.withValues(alpha: 0.10)
                                      : Colors.black.withValues(alpha: 0.06)),
                              width: isSelected ? 1.4 : 0.8,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: mode == AmbientThemeMode.amoled
                                      ? const Color(0xFF000000)
                                      : accent.withValues(alpha: isDarkMode ? 0.22 : 0.16),
                                  gradient: previewGradient != null
                                      ? LinearGradient(
                                          colors: previewGradient.colors
                                              .map((c) => c.withValues(alpha: 0.4))
                                              .toList(),
                                        )
                                      : null,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.35),
                                    width: 0.8,
                                  ),
                                ),
                                child: Icon(icon, size: 18, color: accent),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                        color: isDarkMode ? Colors.white : Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      desc,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 20,
                                  color: accent,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRefreshRateControl(
    BuildContext context,
    RefreshRateProvider refreshRateProvider,
    bool isDarkMode,
  ) {
    final selectedOption = refreshRateProvider.selectedOption;
    final isSupported = refreshRateProvider.isSupportedOnPlatform;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              _buildLeadingIcon(
                Icons.speed_rounded,
                isDarkMode,
                accentColor: const Color(0xFF10B981),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Screen Refresh Rate',
                      style: GoogleFonts.roboto(fontWeight: FontWeight.w600, fontSize: 14.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      refreshRateProvider.statusSubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.tune_rounded,
                  size: 19,
                  color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                ),
                tooltip: 'Refresh Rate Details',
                onPressed: () => _showRefreshRateModal(context, refreshRateProvider, isDarkMode),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 4-Segment Refresh Rate Selector
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                for (final option in RefreshRateOption.values) ...[
                  if (option != RefreshRateOption.values.first)
                    const SizedBox(width: 4),
                  Expanded(
                    child: _buildRefreshRateSegmentButton(
                      option: option,
                      isSelected: selectedOption == option,
                      isHardwareSupported: refreshRateProvider.isOptionSupported(option),
                      isDarkMode: isDarkMode,
                      activeColor: const Color(0xFF10B981),
                      onTap: () async {
                        if (!isSupported) {
                          ScaffoldMessenger.of(context).showReplacingSnackBar(
                            const SnackBar(
                              content: Text('Refresh rate is managed automatically by your operating system.'),
                            ),
                          );
                          return;
                        }

                        if (!refreshRateProvider.isOptionSupported(option)) {
                          final supportedRates = refreshRateProvider.availableRefreshRates;
                          final ratesStr = supportedRates.isEmpty
                              ? '60 Hz'
                              : supportedRates.map((r) => '$r Hz').join(', ');
                          ScaffoldMessenger.of(context).showReplacingSnackBar(
                            SnackBar(
                              content: Text(
                                'This display panel does not support ${option.label}. Supported: $ratesStr',
                              ),
                            ),
                          );
                          return;
                        }

                        HapticFeedback.selectionClick();
                        final success = await refreshRateProvider.setOption(option);
                        if (!success && context.mounted) {
                          ScaffoldMessenger.of(context).showReplacingSnackBar(
                            SnackBar(
                              content: Text('Could not switch to ${option.label}. Restored default.'),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshRateSegmentButton({
    required RefreshRateOption option,
    required bool isSelected,
    required bool isHardwareSupported,
    required bool isDarkMode,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final IconData icon = switch (option) {
      RefreshRateOption.deviceDefault => Icons.auto_mode_rounded,
      RefreshRateOption.hz60 => Icons.battery_saver_rounded,
      RefreshRateOption.hz90 => Icons.speed_rounded,
      RefreshRateOption.hz120 => Icons.bolt_rounded,
    };

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDarkMode
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.10),
                  width: 0.8,
                )
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Opacity(
          opacity: isHardwareSupported ? 1.0 : 0.38,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected
                    ? activeColor
                    : (isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
              ),
              const SizedBox(height: 3),
              Text(
                option.label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (isDarkMode ? Colors.white : Colors.black)
                      : (isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70)),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRefreshRateModal(
    BuildContext context,
    RefreshRateProvider refreshRateProvider,
    bool isDarkMode,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: isDarkMode
          ? Colors.black.withValues(alpha: 0.6)
          : Colors.black.withValues(alpha: 0.3),
      builder: (ctx) {
        final activeHz = refreshRateProvider.activeMode?.refreshRate;
        final isPlatformSupported = refreshRateProvider.isSupportedOnPlatform;
        final availableRates = refreshRateProvider.availableRefreshRates;

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF0C0C12).withValues(alpha: 0.75)
                    : Colors.white.withValues(alpha: 0.82),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: isDarkMode
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.60),
                    width: 1.0,
                  ),
                ),
              ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Title Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: isDarkMode ? 0.2 : 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.speed_rounded,
                          size: 20,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Display & Refresh Rate',
                              style: GoogleFonts.inter(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: isDarkMode ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Customize screen frame rate or use device default',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode
                                    ? const Color(0xFF8E8E93)
                                    : const Color(0xFF6C6C70),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Hardware Status Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hardware Display Detection',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode ? Colors.white70 : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                isPlatformSupported
                                    ? (availableRates.isNotEmpty
                                        ? 'Supported modes: ${availableRates.map((r) => '$r Hz').join(', ')}'
                                        : 'Querying display modes...')
                                    : 'Managed automatically by OS display compositor',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (activeHz != null && activeHz > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              '${activeHz.round()} Hz Active',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Options List
                  ...RefreshRateOption.values.map((option) {
                    final isSelected = refreshRateProvider.selectedOption == option;
                    final isHardwareSupported = refreshRateProvider.isOptionSupported(option);

                    final IconData icon = switch (option) {
                      RefreshRateOption.deviceDefault => Icons.auto_mode_rounded,
                      RefreshRateOption.hz60 => Icons.battery_saver_rounded,
                      RefreshRateOption.hz90 => Icons.speed_rounded,
                      RefreshRateOption.hz120 => Icons.bolt_rounded,
                    };

                    const Color accent = Color(0xFF10B981);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () async {
                          if (!isPlatformSupported) {
                            ScaffoldMessenger.of(context).showReplacingSnackBar(
                              const SnackBar(
                                content: Text('Refresh rate is managed automatically by your operating system.'),
                              ),
                            );
                            return;
                          }

                          if (!isHardwareSupported) {
                            ScaffoldMessenger.of(context).showReplacingSnackBar(
                              SnackBar(
                                content: Text(
                                  'This display does not support ${option.label}. Supported: ${availableRates.map((r) => '$r Hz').join(', ')}',
                                ),
                              ),
                            );
                            return;
                          }

                          HapticFeedback.selectionClick();
                          await refreshRateProvider.setOption(option);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (isDarkMode
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.08))
                                : (isDarkMode
                                    ? Colors.white.withValues(alpha: 0.04)
                                    : Colors.black.withValues(alpha: 0.03)),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? (isDarkMode ? Colors.white : Colors.black)
                                  : (isDarkMode
                                      ? Colors.white.withValues(alpha: 0.10)
                                      : Colors.black.withValues(alpha: 0.06)),
                              width: isSelected ? 1.4 : 0.8,
                            ),
                          ),
                          child: Opacity(
                            opacity: isHardwareSupported ? 1.0 : 0.4,
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: isDarkMode ? 0.22 : 0.16),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.35),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Icon(icon, size: 18, color: accent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            option.title,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                              color: isDarkMode ? Colors.white : Colors.black,
                                            ),
                                          ),
                                          if (!isHardwareSupported) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              '(Unsupported)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.red.withValues(alpha: 0.8),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        option.description,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: isDarkMode
                                              ? const Color(0xFF8E8E93)
                                              : const Color(0xFF6C6C70),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 20,
                                    color: accent,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
      },
    );
  }

  Widget _buildGroupCard({
    required List<Widget> children,
    required bool isDarkMode,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF0D0D12).withValues(alpha: 0.42)
                : Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.60),
              width: 0.9,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _buildTileDivider(bool isDarkMode) {
    return Divider(
      height: 1,
      thickness: 0.6,
      indent: 62,
      endIndent: 16,
      color: isDarkMode ? const Color(0xFF202026) : const Color(0xFFEAEAEA),
    );
  }

  Widget _buildLeadingIcon(IconData icon, bool isDarkMode, {Color? accentColor}) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1B1B20) : const Color(0xFFECECF0),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF282830) : const Color(0xFFDCDCE2),
          width: 0.6,
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 18,
          color: accentColor ?? (isDarkMode ? Colors.white : Colors.black87),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.roboto(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
        ),
      ),
    );
  }
}

class _UpdateAvailableBadge extends StatelessWidget {
  const _UpdateAvailableBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Update available',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}