import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../models/app_update_model.dart';
import '../../services/update_service.dart';
import '../../utils/snackbar_utils.dart';
import '../bunk_meter/bunk_meter_screen.dart';
import '../calendar/calendar_screen.dart';
import '../settings/more_screen.dart';
import '../semester/semester_provider.dart';
import '../semester/semester_screen.dart';
import '../subject/add_subject_screen.dart';
import '../subject/import_timetable_screen.dart';
import '../subject/subject_screen.dart';
import 'todays_schedule.dart';
import 'update_dialog.dart';

class HomeScreen extends StatefulWidget {
  final int initialPageIndex;
  const HomeScreen({super.key, this.initialPageIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;
  final UpdateService _updateService = UpdateService();
  AppUpdate? _pendingUpdate;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialPageIndex;
    _checkForUpdates();
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => StatefulBuilder(
        builder: (routeContext, setState) => FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (routeContext, snapshot) {
            final currentVersion = snapshot.data?.version ?? '1.0.1';
            return UpdateFullScreen(
              update: update,
              currentVersion: currentVersion,
              isDownloading: _isDownloading,
              onInstallNow: () async {
                setState(() {
                  _isDownloading = true;
                });
                
                if (!mounted) return;
                final navigator = Navigator.of(routeContext);
                final messenger = ScaffoldMessenger.of(routeContext);
                
                try {
                  // Download APK
                  final apkFile = await _updateService.downloadAPK(_pendingUpdate!.version);
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
                    setState(() {
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
  }

  Widget _buildSemesterRequiredWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.info_outline, size: 50, color: Colors.amber),
            const SizedBox(height: 16),
            const Text(
              'Please Create a Semester',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'You need to set up a semester before you can add subjects or track attendance.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
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
    final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
    final startDate = semesterProvider.semester!.startDate;
    final formattedDate = '${startDate.day}/${startDate.month}/${startDate.year}';
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.pending_actions, size: 50, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'Semester Yet to Begin',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Your semester will start on $formattedDate. Attendance tracking will begin from that date.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitles[_selectedIndex]),
        actions: [
          if (isSemesterSet && hasSemesterStarted && !hasSemesterEnded)
            IconButton(
              icon: const Icon(Icons.calendar_month),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CalendarScreen()),
                );
              },
              tooltip: 'Attendance Calendar',
            ),
          if (_selectedIndex == 1 && isSemesterSet && !hasSemesterEnded)
            IconButton(
              icon: const Icon(Icons.download_for_offline),
              onPressed: () {
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
            child: Center(
              child: widgetOptions.elementAt(_selectedIndex),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.today),
            label: 'Today',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.subject),
            label: 'Subjects',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.school),
            label: 'Semester',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calculate),
            label: 'Bunk Meter',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed, // Ensures all labels are visible
      ),
      floatingActionButton: _selectedIndex == 1 && isSemesterSet && !hasSemesterEnded
          ? FloatingActionButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AddSubjectScreen()),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
