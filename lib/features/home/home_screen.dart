import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:workmanager/workmanager.dart';

import '../../main.dart';
import '../../models/app_update_model.dart';
import '../../services/backup_service.dart';
import '../../services/update_service.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../bunk_meter/bunk_meter_screen.dart';
import '../bunk_meter/what_if_calculator_sheet.dart';
import '../calendar/calendar_screen.dart';
import '../planner/leave_planner_screen.dart';
import '../settings/more_screen.dart';
import '../semester/semester_provider.dart';
import '../semester/semester_screen.dart';
import '../subject/add_subject_screen.dart';
import '../subject/import_timetable_screen.dart';
import '../subject/subject_provider.dart';
import '../subject/subject_screen.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_overlay.dart';
import 'todays_schedule.dart';
import 'update_dialog.dart';

class HomeScreen extends StatefulWidget {
  final int initialPageIndex;
  const HomeScreen({super.key, this.initialPageIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late int _selectedIndex;
  final UpdateService _updateService = UpdateService();
  AppUpdate? _pendingUpdate;
  bool _isDownloading = false;

  final GlobalKey _todayTabKey = GlobalKey();
  final GlobalKey _subjectTabKey = GlobalKey();
  final GlobalKey _semesterTabKey = GlobalKey();
  final GlobalKey _bunkTabKey = GlobalKey();
  final GlobalKey _moreTabKey = GlobalKey();
  final GlobalKey _calendarKey = GlobalKey();
  final GlobalKey _importKey = GlobalKey();
  final GlobalKey _fabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialPageIndex;
    if (!kDebugMode) {
      _checkForUpdates();
    }
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tutorialController = Provider.of<TutorialController>(context, listen: false);
      tutorialController.registerTabSwitcher((index) {
        if (mounted) {
          setState(() {
            _selectedIndex = index;
          });
        }
      });
      tutorialController.registerRouteHandler((action) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          switch (action) {
            case TutorialRouteAction.addSubject:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AddSubjectScreen()),
              );
              break;
            case TutorialRouteAction.importTimetable:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ImportTimetableScreen()),
              );
              break;
            case TutorialRouteAction.calendar:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CalendarScreen()),
              );
              break;
            case TutorialRouteAction.bunkCalculator:
              final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
              final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
              final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);

              if (semesterProvider.semester != null) {
                final Map<String, List<Attendance>> recordsBySubject = {};
                for (final record in attendanceProvider.attendanceRecords) {
                  recordsBySubject.putIfAbsent(record.subjectId, () => []).add(record);
                }

                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  barrierColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.12)
                      : null,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  builder: (ctx) => WhatIfCalculatorSheet(
                    subjects: subjectProvider.subjects,
                    recordsBySubject: recordsBySubject,
                    semester: semesterProvider.semester!,
                  ),
                );
              }
              break;
            case TutorialRouteAction.leavePlanner:
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LeavePlannerScreen()),
              );
              break;
            case TutorialRouteAction.none:
              break;
          }
        });
      });
      tutorialController.registerKey('nav_tab_today', _todayTabKey);
      tutorialController.registerKey('nav_tab_subjects', _subjectTabKey);
      tutorialController.registerKey('nav_tab_semester', _semesterTabKey);
      tutorialController.registerKey('nav_tab_bunk_meter', _bunkTabKey);
      tutorialController.registerKey('nav_tab_more', _moreTabKey);
      tutorialController.registerKey('appbar_calendar', _calendarKey);
      tutorialController.registerKey('appbar_import_timetable', _importKey);
      tutorialController.registerKey('fab_add_subject', _fabKey);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Cancel pending 15-minute exit backup if user reopens the app before 15 minutes
      try {
        Workmanager().cancelByUniqueName('app_close_15min_backup');
      } catch (e) {
        debugPrint('Failed to cancel delayed backup task on resume: $e');
      }

      try {
        final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
        final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
        
        attendanceProvider.reloadAttendance();
        subjectProvider.reloadSubjects();
      } catch (e) {
        debugPrint('Failed to reload database on app resume: $e');
      }
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      // Schedule 15-minute delayed background backup ONLY IF backups are enabled and data changes occurred
      try {
        final backupService = BackupService();
        Future.wait([
          backupService.isBackupEnabled(),
          backupService.hasUnbackedDataChanges(),
        ]).then((results) {
          final isEnabled = results[0];
          final hasChanges = results[1];
          if (isEnabled && hasChanges) {
            Workmanager().registerOneOffTask(
              'app_close_15min_backup',
              'appCloseBackupTask',
              initialDelay: const Duration(minutes: 15),
              existingWorkPolicy: ExistingWorkPolicy.replace,
            );
          } else {
            debugPrint('HomeScreen: Skipping 15-min exit backup (enabled: $isEnabled, changes: $hasChanges).');
          }
        });
      } catch (e) {
        debugPrint('Failed to schedule 15-min exit backup task: $e');
      }
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      // Check for updates on every app launch (regardless of last check time)
      final update = await _updateService.checkForUpdate();
      if (update != null && mounted) {
        setState(() {
          _pendingUpdate = update;
        });
        _showUpdateScreen(update);
      }
    } catch (e) {
      debugPrint('Error checking for updates: $e');
    }
  }

  void _showUpdateScreen(AppUpdate update) {
    var downloadProgress = 0.0;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => StatefulBuilder(
          builder: (routeContext, routeSetState) => FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (routeContext, snapshot) {
              final currentVersion = snapshot.data?.version ?? '1.0.1';
              return UpdateFullScreen(
                update: update,
                currentVersion: currentVersion,
                isDownloading: _isDownloading,
                downloadProgress: downloadProgress,
                onInstallNow: () async {
                  routeSetState(() {
                    _isDownloading = true;
                    downloadProgress = 0.0;
                  });

                  if (!mounted) return;
                  final navigator = Navigator.of(routeContext);
                  final messenger = ScaffoldMessenger.of(routeContext);

                  try {
                    // Download APK with progress callback
                    final apkFile = await _updateService.downloadAPK(
                      _pendingUpdate!.version,
                      onProgress: (progress) {
                        if (mounted) {
                          routeSetState(() {
                            downloadProgress = progress;
                          });
                        }
                      },
                    );
                    if (apkFile != null && mounted) {
                      // Trigger installation
                      final installResult = await _updateService.installAPK(apkFile);
                      if (mounted) {
                        switch (installResult) {
                          case InstallResult.installerStarted:
                            navigator.pop();
                            messenger.showReplacingSnackBar(
                              const SnackBar(content: Text('Installer opened. Complete the update to continue.')),
                            );
                            break;
                          case InstallResult.permissionRequired:
                            messenger.showReplacingSnackBar(
                              const SnackBar(
                                content: Text('Allow installs from this source, then tap Install Now again.'),
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
                        _isDownloading = false;
                      });
                    }
                  }
                },
                onRemindLater: () async {
                  if (!mounted) return;
                  final navigator = Navigator.of(routeContext);

                  try {
                    await _updateService.deferUpdate();
                    if (mounted) {
                      navigator.pop();
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

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    if (tutorialController.isActive && tutorialController.currentStep?.targetTabIndex == index) {
      if (tutorialController.currentStep?.isActionRequired == true) {
        final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
        if (semesterProvider.semester == null) return;
      }
      tutorialController.nextStep();
    }
  }

  Widget _buildSemesterRequiredWidget() {
    final rs = context.rs;
    return Center(
      child: Padding(
        padding: rs.insetsAll(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: rs.scale(50), color: Colors.amber),
            SizedBox(height: rs.height(16)),
            Text(
              'Please Create a Semester',
              style: TextStyle(fontSize: rs.font(22), fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: rs.height(8)),
            const Text(
              'You need to set up a semester before you can add subjects or track attendance.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: rs.height(24)),
            ElevatedButton.icon(
              icon: const Icon(Icons.school),
              label: const Text('Go to Semester Setup'),
              onPressed: () {
                setState(() {
                  _selectedIndex = 2; // Navigate to the Semester screen
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSemesterYetToBeginWidget() {
    final rs = context.rs;
    final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
    final startDate = semesterProvider.semester!.startDate;
    final formattedDate = '${startDate.day}/${startDate.month}/${startDate.year}';
    
    return Center(
      child: Padding(
        padding: rs.insetsAll(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.pending_actions, size: rs.scale(50), color: Colors.blue),
            SizedBox(height: rs.height(16)),
            Text(
              'Semester Yet to Begin',
              style: TextStyle(fontSize: rs.font(22), fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: rs.height(8)),
            Text(
              'Your semester will start on $formattedDate. Attendance tracking will begin from that date.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: rs.font(16)),
            ),
            SizedBox(height: rs.height(24)),
            ElevatedButton.icon(
              icon: const Icon(Icons.school),
              label: const Text('View Semester Details'),
              onPressed: () {
                setState(() {
                  _selectedIndex = 2; // Navigate to the Semester screen
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final tutorialController = Provider.of<TutorialController>(context, listen: false);

    final bool isSemesterSet = semesterProvider.semester != null;
    final bool hasSemesterStarted = semesterProvider.hasSemesterStarted;
    final bool hasSemesterEnded = semesterProvider.hasSemesterEnded;

    final List<Widget> widgetOptions = <Widget>[
      isSemesterSet
          ? (hasSemesterStarted ? const TodaySchedule() : _buildSemesterYetToBeginWidget())
          : _buildSemesterRequiredWidget(),
      isSemesterSet ? const SubjectScreen() : _buildSemesterRequiredWidget(),
      const SemesterScreen(),
      isSemesterSet
          ? (hasSemesterStarted ? const BunkMeterScreen() : _buildSemesterYetToBeginWidget())
          : _buildSemesterRequiredWidget(),
      const MoreScreen(),
    ];

    const List<String> appBarTitles = <String>[
      'Today\'s Schedule',
      'Subjects',
      'Semester Details',
      'Bunk Meter',
      'More',
    ];

    return TutorialOverlay(
      child: Scaffold(
        appBar: AppBar(
          title: Text(appBarTitles[_selectedIndex]),
          actions: [
            if (isSemesterSet && hasSemesterStarted && !hasSemesterEnded)
              IconButton(
                icon: KeyedSubtree(key: _calendarKey, child: const Icon(Icons.calendar_month)),
                onPressed: () {
                  if (tutorialController.isActive && tutorialController.currentStepIndex == 15) {
                    tutorialController.nextStep();
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CalendarScreen()),
                  );
                },
                tooltip: 'Attendance Calendar',
              ),
            if (_selectedIndex == 1 && isSemesterSet && !hasSemesterEnded)
              IconButton(
                icon: KeyedSubtree(key: _importKey, child: const Icon(Icons.download_for_offline)),
                onPressed: () {
                  if (tutorialController.isActive && tutorialController.currentStepIndex == 10) {
                    tutorialController.nextStep();
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ImportTimetableScreen()),
                  );
                },
                tooltip: 'Import Timetable',
              ),
            PopupMenuButton<ThemeMode>(
              tooltip: 'Theme',
              icon: Icon(
                switch (themeProvider.themeMode) {
                  ThemeMode.light => Icons.light_mode,
                  ThemeMode.dark => Icons.dark_mode,
                  ThemeMode.system => Icons.phone_android,
                },
              ),
              onSelected: (mode) => themeProvider.setThemeMode(mode),
              itemBuilder: (context) => [
                const PopupMenuItem<ThemeMode>(
                  value: ThemeMode.light,
                  child: Row(
                    children: [
                      Icon(Icons.light_mode),
                      SizedBox(width: 12),
                      Text('Light'),
                    ],
                  ),
                ),
                const PopupMenuItem<ThemeMode>(
                  value: ThemeMode.dark,
                  child: Row(
                    children: [
                      Icon(Icons.dark_mode),
                      SizedBox(width: 12),
                      Text('Dark'),
                    ],
                  ),
                ),
                const PopupMenuItem<ThemeMode>(
                  value: ThemeMode.system,
                  child: Row(
                    children: [
                      Icon(Icons.phone_android),
                      SizedBox(width: 12),
                      Text('System'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              height: 1,
              color: Theme.of(context).brightness == Brightness.light ? Colors.black : Colors.white,
            ),
            Expanded(
              child: widgetOptions.elementAt(_selectedIndex),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: KeyedSubtree(key: _todayTabKey, child: const Icon(Icons.today)),
              label: 'Today',
            ),
            BottomNavigationBarItem(
              icon: KeyedSubtree(key: _subjectTabKey, child: const Icon(Icons.subject)),
              label: 'Subjects',
            ),
            BottomNavigationBarItem(
              icon: KeyedSubtree(key: _semesterTabKey, child: const Icon(Icons.school)),
              label: 'Semester',
            ),
            BottomNavigationBarItem(
              icon: KeyedSubtree(key: _bunkTabKey, child: const Icon(Icons.calculate)),
              label: 'Bunk Meter',
            ),
            BottomNavigationBarItem(
              icon: KeyedSubtree(key: _moreTabKey, child: const Icon(Icons.more_horiz)),
              label: 'More',
            ),
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed, // Ensures all labels are visible
        ),
        floatingActionButton: _selectedIndex == 1 && isSemesterSet && !hasSemesterEnded
            ? FloatingActionButton(
                key: _fabKey,
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  if (tutorialController.isActive && tutorialController.currentStepIndex == 4) {
                    tutorialController.nextStep();
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AddSubjectScreen()),
                  );
                },
                child: const Icon(Icons.add),
              )
            : null,
      ),
    );
  }
}
