import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

import '../../services/calendar_service.dart';
import '../../services/system_calendar_service.dart';
import '../../models/app_update_model.dart';
import '../../services/database_service.dart';
import '../../services/update_service.dart';
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
import 'time_format_provider.dart';
import 'whats_new_screen.dart';
import 'swipe_actions_settings_screen.dart';

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
                onInstallNow: () async {
                  routeSetState(() {
                    isDownloading = true;
                  });

                  final navigator = Navigator.of(routeContext);
                  final messenger = ScaffoldMessenger.of(context);

                  try {
                    final apkFile = await _updateService.downloadAPK(update.version);
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

  void _showDemoGenerationConfirmation() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Generate Timetable Data?'),
          content: const Text(
            'This will clear all current semester, subject, and attendance data, and replace it with a 120-day test timetable (60 days before and 60 days after today, 5 classes/day) with random attendance for past days. Proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _generateDemoTimetable();
              },
              child: const Text('Generate', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _showClearDataConfirmation() {
    showDialog(
      context: context,
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

  Future<void> _generateDemoTimetable() async {
    try {
      final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
      final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
      final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);

      await DatabaseService().clearSemesterAndAllData();

      final today = DateTime.now();
      final todayNormalized = DateTime(today.year, today.month, today.day);
      final startDate = todayNormalized.subtract(const Duration(days: 60));
      final endDate = todayNormalized.add(const Duration(days: 60));
      
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
        for (int i = 0; i < 60; i++) {
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
          const SnackBar(content: Text('Demo timetable and attendance generated successfully!')),
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
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);

    return ListView(
      children: [
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
            showDialog<void>(
              context: context,
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
                          children: [
                            RadioListTile<ClockStyle>(
                              title: const Text('Material Dialog'),
                              value: ClockStyle.material,
                            ),
                            RadioListTile<ClockStyle>(
                              title: const Text('Scroll Wheel'),
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
          leading: const Icon(Icons.sync),
          title: const Text('Calendar Sync'),
          subtitle: const Text('Sync your timetable with Google or Device Calendar'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CalendarSyncSelectionScreen()),
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
        FutureBuilder<PackageInfo>(
          future: _packageInfoFuture,
          builder: (context, snapshot) {
            final version = snapshot.data?.version ?? 'Loading...';

            return ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('App version'),
              subtitle: Text(version),
            );
          },
        ),
        FutureBuilder<PackageInfo>(
          future: _packageInfoFuture,
          builder: (context, snapshot) {
            final buildNumber = snapshot.data?.buildNumber ?? 'Loading...';

            return ListTile(
              leading: const Icon(Icons.tag_outlined),
              title: const Text('Build number'),
              subtitle: Text(buildNumber),
            );
          },
        ),
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
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Setup Guide'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SetupGuideScreen()),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.favorite_border_outlined),
          title: const Text('Support me'),
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
        if (kDebugMode) ...[
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Developer Options',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
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
            leading: const Icon(Icons.playlist_add_check_outlined, color: Colors.red),
            title: const Text('Generate Timetable Data'),
            subtitle: const Text('Generates 120-day semester (60d before/after today, 5+ classes/day)'),
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