// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/calendar_service.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_drive_backup_service.dart';
import '../../services/system_calendar_service.dart';
import '../semester/semester_provider.dart';
import '../subject/subject_provider.dart';
import '../../utils/snackbar_utils.dart';

class CalendarSyncSelectionScreen extends StatefulWidget {
  const CalendarSyncSelectionScreen({super.key});

  @override
  State<CalendarSyncSelectionScreen> createState() => _CalendarSyncSelectionScreenState();
}

class _CalendarSyncSelectionScreenState extends State<CalendarSyncSelectionScreen> {
  static const String _prefGoogleCalendarSyncEnabledKey = 'google_calendar_sync_enabled';

  bool _isLoading = true;
  bool _isGoogleConnected = false;
  bool _isGoogleSyncEnabled = false;

  bool _isSystemSyncEnabled = false;
  String? _selectedSystemCalendarId;
  String? _selectedSystemCalendarName;
  List<dc.Calendar> _systemCalendars = [];

  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    GoogleAuthService.instance.addListener(_onAuthStateChanged);
    _loadSyncStatus();
  }

  @override
  void dispose() {
    GoogleAuthService.instance.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  void _onAuthStateChanged() {
    if (mounted) {
      _loadSyncStatus();
    }
  }

  Future<void> _loadSyncStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Google Status
      _isGoogleConnected = await GoogleAuthService.instance.isSignedIn();
      _isGoogleSyncEnabled = prefs.getBool(_prefGoogleCalendarSyncEnabledKey) ?? _isGoogleConnected;

      // 2. System Status
      _isSystemSyncEnabled = await SystemCalendarService.isSystemSyncEnabled();
      _selectedSystemCalendarId = await SystemCalendarService.getSystemCalendarId();
      _selectedSystemCalendarName = await SystemCalendarService.getSystemCalendarName();

      if (await SystemCalendarService.checkOrRequestPermissions()) {
        _systemCalendars = await SystemCalendarService.getWritableCalendars();
      }
    } catch (e) {
      debugPrint('Error loading sync status: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isActionInProgress = true);
    final account = await GoogleAuthService.instance.signIn();
    setState(() => _isActionInProgress = false);

    if (account != null && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefGoogleCalendarSyncEnabledKey, true);
      if (!mounted) return;
      setState(() {
        _isGoogleConnected = true;
        _isGoogleSyncEnabled = true;
      });

      SnackbarUtils.showSuccessSnackBar(context, 'Signed in with Google.');
      await _checkExistingCloudBackup();
      if (!mounted) return;
      await _triggerGoogleSync(showFeedback: true);
    }
  }

  Future<void> _checkExistingCloudBackup() async {
    final driveService = GoogleDriveBackupService();
    final backup = await driveService.checkForExistingBackup();

    if (backup != null && mounted) {
      final formattedDate = DateFormat.yMMMd().add_jm().format(backup.modifiedTime);
      final sizeKb = (backup.sizeBytes / 1024).toStringAsFixed(1);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.cloud_download_outlined, size: 40, color: Colors.blue),
          title: const Text('Cloud Backup Found'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A previous AttendMate backup was found on your Google Drive:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Date: $formattedDate', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Size: $sizeKb KB'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Would you like to restore your subjects and attendance from this backup now?',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep Local Data'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() => _isActionInProgress = true);
                final ok = await driveService.restoreLatestBackupFromDrive(context: context);
                setState(() => _isActionInProgress = false);
                if (mounted) {
                  if (ok) {
                    SnackbarUtils.showSuccessSnackBar(context, 'Restored database from Google Drive.');
                  } else {
                    SnackbarUtils.showErrorSnackBar(context, 'Failed to restore backup from Drive.');
                  }
                }
              },
              child: const Text('Restore from Drive'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _toggleGoogleSync(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefGoogleCalendarSyncEnabledKey, enabled);
    if (!mounted) return;
    setState(() => _isGoogleSyncEnabled = enabled);

    if (enabled) {
      await _triggerGoogleSync(showFeedback: true);
    } else {
      final semester = Provider.of<SemesterProvider>(context, listen: false).semester;
      setState(() => _isActionInProgress = true);
      await CalendarService.deleteAllSyncedEvents(semester, force: true);
      if (!mounted) return;
      setState(() => _isActionInProgress = false);
      SnackbarUtils.showSuccessSnackBar(context, 'Google Calendar sync disabled. Synced events cleared.');
    }
  }

  Future<void> _triggerGoogleSync({bool showFeedback = false}) async {
    final semester = Provider.of<SemesterProvider>(context, listen: false).semester;
    final subjects = Provider.of<SubjectProvider>(context, listen: false).subjects;

    if (semester == null) {
      if (showFeedback && mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Please set up semester dates before syncing.');
      }
      return;
    }

    setState(() => _isActionInProgress = true);
    try {
      final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);

      await CalendarService.syncFullTimetable(
        subjects: subjects,
        semester: semester,
        isHoliday: subjectProvider.isHoliday,
      );

      if (showFeedback && mounted) {
        SnackbarUtils.showSuccessSnackBar(context, 'Google Calendar synchronized successfully.');
      }
    } catch (e) {
      if (showFeedback && mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Google Calendar Sync Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _toggleSystemSync(bool value) async {
    if (value) {
      setState(() {
        _isActionInProgress = true;
      });

      try {
        final hasPerm = await SystemCalendarService.checkOrRequestPermissions();
        if (!hasPerm) {
          if (mounted) {
            SnackbarUtils.showErrorSnackBar(context, 'Calendar permissions are required to sync to device calendars.');
          }
          setState(() {
            _isActionInProgress = false;
          });
          return;
        }

        final calendars = await SystemCalendarService.getWritableCalendars();
        setState(() {
          _systemCalendars = calendars;
        });

        if (calendars.isEmpty) {
          if (mounted) {
            SnackbarUtils.showErrorSnackBar(context, 'No writable calendars found on this device.');
          }
          setState(() {
            _isActionInProgress = false;
          });
          return;
        }

        final defaultCalendar = calendars.first;
        final targetId = _selectedSystemCalendarId ?? defaultCalendar.id;
        final targetName = _selectedSystemCalendarName ?? defaultCalendar.name;

        await SystemCalendarService.setSystemSyncEnabled(true, calendarId: targetId, calendarName: targetName);
        _selectedSystemCalendarId = targetId;
        _selectedSystemCalendarName = targetName;
        _isSystemSyncEnabled = true;

        _triggerSystemSync();
      } catch (e) {
        if (mounted) {
          SnackbarUtils.showErrorSnackBar(context, 'Error enabling system sync: $e');
        }
      } finally {
        setState(() {
          _isActionInProgress = false;
        });
      }
    } else {
      setState(() {
        _isActionInProgress = true;
      });

      try {
        await SystemCalendarService.deleteSyncedEvents();
        await SystemCalendarService.setSystemSyncEnabled(false);
        setState(() {
          _isSystemSyncEnabled = false;
          _selectedSystemCalendarId = null;
          _selectedSystemCalendarName = null;
        });
        if (mounted) {
          SnackbarUtils.showSuccessSnackBar(context, 'Device Calendar sync disabled.');
        }
      } catch (e) {
        if (mounted) {
          SnackbarUtils.showErrorSnackBar(context, 'Error disabling system sync: $e');
        }
      } finally {
        setState(() {
          _isActionInProgress = false;
        });
      }
    }
  }

  Future<void> _changeSystemCalendar(String calendarId, String calendarName) async {
    setState(() {
      _isActionInProgress = true;
    });

    try {
      await SystemCalendarService.deleteSyncedEvents();
      await SystemCalendarService.setSystemSyncEnabled(true, calendarId: calendarId, calendarName: calendarName);
      setState(() {
        _selectedSystemCalendarId = calendarId;
        _selectedSystemCalendarName = calendarName;
      });
      _triggerSystemSync();
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Error changing calendar: $e');
      }
    } finally {
      setState(() {
        _isActionInProgress = false;
      });
    }
  }

  Future<void> _triggerSystemSync() async {
    final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);

    if (semesterProvider.semester == null) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Timetable will sync once semester dates are configured.');
      }
      return;
    }

    if (subjectProvider.subjects.isEmpty) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'No subjects/schedule to sync.');
      }
      return;
    }

    setState(() {
      _isActionInProgress = true;
    });

    try {
      await SystemCalendarService.syncFullTimetable(
        subjects: subjectProvider.subjects,
        semester: semesterProvider.semester!,
        isHoliday: subjectProvider.isHoliday,
      );
      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(context, 'Timetable successfully synced to "$_selectedSystemCalendarName"!');
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Device Calendar Sync Error: $e');
      }
    } finally {
      setState(() {
        _isActionInProgress = false;
      });
    }
  }

  String _formatCalendarLabel(dc.Calendar cal) {
    final String displayName;
    if (cal.accountType == 'com.google' && cal.name == cal.accountName) {
      displayName = 'Google Calendar';
    } else if (cal.name.toLowerCase() == 'my calendar') {
      displayName = 'My Calendar';
    } else {
      displayName = cal.name.isEmpty ? 'Calendar' : cal.name;
    }

    final String account;
    if (cal.accountName == null || cal.accountName!.trim().isEmpty) {
      account = 'Local Device';
    } else if (cal.accountName!.toLowerCase() == 'my calendar') {
      account = 'Local Offline';
    } else {
      account = cal.accountName!;
    }

    return '$displayName ($account)';
  }

  String _formatDate(DateTime date) {
    return DateFormat.yMMMd().format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semester = Provider.of<SemesterProvider>(context).semester;
    final subjects = Provider.of<SubjectProvider>(context).subjects;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar Synchronization'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Card: Google Calendar Sync Option
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.cloud_queue_rounded,
                                    color: theme.colorScheme.primary,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Google Calendar Sync',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _isGoogleConnected
                                            ? 'Sync timetable to your Google Calendar'
                                            : 'Connect Google Account to enable sync',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_isGoogleConnected)
                                  Switch(
                                    value: _isGoogleSyncEnabled,
                                    onChanged: _isActionInProgress ? null : _toggleGoogleSync,
                                  ),
                              ],
                            ),
                            if (!_isGoogleConnected) ...[
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _isActionInProgress ? null : _handleGoogleSignIn,
                                  icon: const Icon(Icons.login_rounded),
                                  label: const Text('Sign in with Google'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Card: Device Calendar Sync Option
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.calendar_today_rounded,
                                    color: theme.colorScheme.secondary,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Device Calendar Sync',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Write directly to native Android calendars',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _isSystemSyncEnabled,
                                  onChanged: _isActionInProgress ? null : _toggleSystemSync,
                                ),
                              ],
                            ),

                            if (_isSystemSyncEnabled) ...[
                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 8),

                              Text(
                                'Destination Calendar',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),

                              if (_systemCalendars.isNotEmpty)
                                DropdownButtonFormField<String>(
                                  value: _selectedSystemCalendarId,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  items: _systemCalendars.map((cal) {
                                    return DropdownMenuItem<String>(
                                      value: cal.id,
                                      child: Text(
                                        _formatCalendarLabel(cal),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: _isActionInProgress
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            final selectedCal = _systemCalendars.firstWhere((c) => c.id == value);
                                            _changeSystemCalendar(value, selectedCal.name.isEmpty ? 'Device Calendar' : selectedCal.name);
                                          }
                                        },
                                )
                              else
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8.0),
                                  child: Text('No writable calendars found on this device.'),
                                ),

                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.sync_rounded, size: 18),
                                  label: const Text('Sync to Device Calendar Now'),
                                  onPressed: _isActionInProgress ? null : _triggerSystemSync,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Unified Sync Bounds Card
                    if (semester != null) ...[
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.security_rounded,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Sync Bounds (Semester Only)',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _buildScopeRow(
                              Icons.calendar_month_rounded,
                              'Active Semester',
                              'Active (${semester.targetPercentage.toInt()}% Target)',
                            ),
                            const SizedBox(height: 8),
                            _buildScopeRow(
                              Icons.date_range_rounded,
                              'Sync Scope',
                              '${_formatDate(semester.startDate)} — ${_formatDate(semester.endDate)}',
                            ),
                            const SizedBox(height: 8),
                            _buildScopeRow(
                              Icons.subject_rounded,
                              'Selected Subjects',
                              '${subjects.length} subject${subjects.length == 1 ? '' : 's'} to export',
                            ),
                            const SizedBox(height: 12),
                            const Divider(),
                            const SizedBox(height: 6),
                            Text(
                              'Notice: Only calendar events falling within your semester dates are managed or modified. Other personal calendar events remain completely untouched.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                height: 1.35,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Integration Capabilities Overview
                    Text(
                      'Integration Capabilities',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildFeatureTile(
                      Icons.sync_rounded,
                      'Unified Timetable Sync',
                      'Keep your weekly schedules, timetable classes, and cancellations synchronized across Google Calendar and native device calendars.',
                    ),
                    _buildFeatureTile(
                      Icons.auto_mode_rounded,
                      'Automatic Schedule Updates',
                      'Modifications made to classes, rooms, or timeslots automatically reflect in your active calendar.',
                    ),
                    _buildFeatureTile(
                      Icons.beach_access_rounded,
                      'Holiday & Cancellation Exclusion',
                      'Marking dates as holidays or cancelling individual classes automatically excludes those event occurrences.',
                    ),
                    _buildFeatureTile(
                      Icons.palette_outlined,
                      'Smart Color Mapping',
                      'Subject colors are automatically mapped to nearest matching calendar palette colors.',
                    ),
                  ],
                ),

                if (_isActionInProgress)
                  Container(
                    color: Colors.black26,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }

  Widget _buildScopeRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45)),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureTile(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        height: 1.3,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
