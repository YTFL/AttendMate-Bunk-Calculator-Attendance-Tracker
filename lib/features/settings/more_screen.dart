import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

import 'package:workmanager/workmanager.dart';
import '../../services/backup_service.dart';
import '../../services/calendar_service.dart';
import '../../services/system_calendar_service.dart';
import '../../models/app_update_model.dart';
import '../../services/database_service.dart';
import '../../services/update_service.dart';
import '../../services/notification_service.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/url_launcher_utils.dart';
import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../home/update_dialog.dart';
import '../semester/semester_model.dart';
import '../semester/semester_provider.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';
import 'calendar_sync_selection_screen.dart';
import 'setup_guide_screen.dart';
import '../tutorial/tutorial_controller.dart';
import 'time_format_provider.dart';
import 'whats_new_screen.dart';
import 'swipe_actions_settings_screen.dart';
import '../location/location_manager_screen.dart';
import 'diagnostics_log_screen.dart';
import 'markdown_viewer_screen.dart';
import 'semester_backup_screen.dart';

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
    if (kDebugMode) {
      _loadDevModeCalendarSync();
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
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      children: [
        _buildSectionHeader('Customization & Gestures', colorScheme),
        ListTile(
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('Use 24-hour format'),
          subtitle: Text(
            timeFormatProvider.is24Hour ? 'Currently: 24-hour' : 'Currently: 12-hour (AM/PM)',
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
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Time picker style'),
          subtitle: Text('Currently: ${timeFormatProvider.clockStyleDisplayName}'),
          onTap: () {
            final isDarkMode = Theme.of(context).brightness == Brightness.dark;
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
        ListTile(
          leading: const Icon(Icons.swipe_outlined),
          title: const Text('Swipe Actions'),
          subtitle: const Text('Customize swipe gestures for your daily classes'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SwipeActionsSettingsScreen()),
            );
          },
        ),

        const Divider(),
        _buildSectionHeader('Features & Integrations', colorScheme),
        KeyedSubtree(
          key: _locationManagerKey,
          child: ListTile(
            leading: const Icon(Icons.pin_drop_outlined),
            title: const Text('Locations & Geofencing'),
            subtitle: const Text('Manage classroom coordinates and auto-attendance'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LocationManagerScreen()),
              );
            },
          ),
        ),
        KeyedSubtree(
          key: _calendarSyncKey,
          child: ListTile(
            enabled: !(kDebugMode && !_devModeCalendarSyncEnabled),
            leading: const Icon(Icons.sync),
            title: const Text('Calendar Sync'),
            subtitle: const Text('Sync your timetable with Google or Device Calendar'),
            trailing: const Icon(Icons.chevron_right),
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
        KeyedSubtree(
          key: _semesterBackupKey,
          child: ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Semester Backup'),
            subtitle: const Text('Backup & restore attendance data (3 rolling backups kept)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SemesterBackupScreen()),
              );
            },
          ),
        ),


        const Divider(),
        _buildSectionHeader('Help & Support', colorScheme),
        KeyedSubtree(
          key: _interactiveTourKey,
          child: ListTile(
            leading: const Icon(Icons.explore_outlined),
            title: const Text('Interactive App Tour'),
            subtitle: const Text('Take the guided feature walkthrough'),
            trailing: const Icon(Icons.play_arrow_rounded),
            onTap: () {
              Provider.of<TutorialController>(context, listen: false).startTutorial(force: true);
            },
          ),
        ),
        KeyedSubtree(
          key: _setupGuideKey,
          child: ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Setup Guide'),
            subtitle: const Text('Learn how to import schedules, set up geofencing, sync calendars, and more'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SetupGuideScreen()),
              );
            },
          ),
        ),
        FutureBuilder<PackageInfo>(
          future: _packageInfoFuture,
          builder: (context, snapshot) {
            final version = snapshot.data?.version;

            return ListTile(
              leading: const Icon(Icons.new_releases_outlined),
              title: const Text('What\'s New'),
              subtitle: Text(
                version == null
                    ? 'See updates in your installed version'
                    : 'See updates in v$version',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const WhatsNewScreen()),
                );
              },
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.favorite_border_outlined),
          title: const Text('Support me'),
          subtitle: const Text('Star the project repository on GitHub'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final isDarkMode = Theme.of(context).brightness == Brightness.dark;
            showDialog(
              context: context,
              barrierColor: isDarkMode
                  ? Colors.white.withValues(alpha: 0.12)
                  : null,
              builder: (dialogContext) {
                return AlertDialog(
                  title: const Text('Support Me'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Please consider starring my GitHub repository to support me.'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        final launched = await UrlLauncherUtils.launchExternalUrl(_repoUrl);
                        if (!context.mounted) return;
                        if (!launched) {
                          ScaffoldMessenger.of(context).showReplacingSnackBar(
                            const SnackBar(content: Text('Could not open the repository page.')),
                          );
                        }
                      },
                      child: const Text('Open GitHub Repo'),
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
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Request feature / Report bug'),
          subtitle: const Text('Submit feedback or suggest improvements'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final isDarkMode = Theme.of(context).brightness == Brightness.dark;
            showDialog(
              context: context,
              barrierColor: isDarkMode
                  ? Colors.white.withValues(alpha: 0.12)
                  : null,
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
                        final launched = await UrlLauncherUtils.launchExternalUrl(_issuesUrl);
                        if (!context.mounted) return;
                        if (!launched) {
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
        const Divider(),
        _buildSectionHeader('Privacy & Terms', colorScheme),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy Policy'),
          subtitle: const Text('Read how your data and location permissions are protected'),
          trailing: const Icon(Icons.chevron_right),
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
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: const Text('Terms of Service'),
          subtitle: const Text('Terms and conditions for using AttendMate'),
          trailing: const Icon(Icons.chevron_right),
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

        const Divider(),
        _buildSectionHeader('System', colorScheme),
        ListTile(
          leading: Icon(
            _availableUpdate != null
                ? Icons.system_update_alt_outlined
                : Icons.system_update_outlined,
          ),
          title: const Text('App updates'),
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
                      : const Icon(Icons.chevron_right),
          onTap: kDebugMode || _isCheckingForUpdate ? null : _onUpdateTileTap,
        ),
        FutureBuilder<PackageInfo>(
          future: _packageInfoFuture,
          builder: (context, snapshot) {
            final version = snapshot.data?.version ?? 'Loading...';
            final buildNumber = snapshot.data?.buildNumber ?? 'Loading...';

            return ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('App version'),
              subtitle: Text('v$version (Build $buildNumber)'),
            );
          },
        ),
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
              leading: const Icon(Icons.update_outlined),
              title: const Text('Current version release date'),
              subtitle: Text(subtitle),
            );
          },
        ),

        if (kDebugMode) ...[
          const Divider(),
          _buildSectionHeader('Developer Options', colorScheme),
          ListTile(
            leading: const Icon(Icons.terminal_outlined, color: Colors.red),
            title: const Text('Diagnostics Log'),
            subtitle: const Text('View and copy app events/errors for debugging'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DiagnosticsLogScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.system_update_outlined, color: Colors.red),
            title: const Text('Simulate Update Screen'),
            subtitle: const Text('Fetch latest release from GitHub and test the update UI & progress'),
            onTap: _simulateUpdateScreen,
          ),
          ListTile(
            leading: const Icon(Icons.sync, color: Colors.red),
            title: const Text('Enable Calendar Sync (Debug)'),
            subtitle: const Text('Allows syncing generated timetable to Google/Device calendar during testing'),
            trailing: Switch(
              value: _devModeCalendarSyncEnabled,
              onChanged: _toggleDevModeCalendarSync,
              activeThumbColor: Colors.red,
            ),
            onTap: () => _toggleDevModeCalendarSync(!_devModeCalendarSyncEnabled),
          ),
          ListTile(
            leading: const Icon(Icons.notification_important_outlined, color: Colors.red),
            title: const Text('Trigger Test Notification (15s)'),
            subtitle: const Text('Schedules a reminder for the most recent unmarked class of today in 15 seconds'),
            onTap: _triggerTestNotification,
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined, color: Colors.red),
            title: const Text('Trigger Test Background Backup (30s)'),
            subtitle: const Text('Schedules a WorkManager background backup in 30 seconds. Close the app to test.'),
            onTap: _triggerTestBackgroundBackup,
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add_check_outlined, color: Colors.red),
            title: const Text('Generate Timetable Data'),
            subtitle: const Text('Generates 120-day semester or just today\'s timetable (5 classes/day)'),
            onTap: _showDemoGenerationConfirmation,
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
            title: const Text('Clear App Data'),
            subtitle: const Text('Wipes DB and SharedPreferences immediately'),
            onTap: _showClearDataConfirmation,
          ),
        ],
      ],
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

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
          color: colorScheme.primary,
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