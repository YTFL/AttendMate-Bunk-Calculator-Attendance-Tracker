// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;
import '../../services/system_calendar_service.dart';
import '../semester/semester_provider.dart';
import '../subject/subject_provider.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/sync_progress_dialog.dart';
import '../../services/notification_service.dart';

class CalendarSyncSelectionScreen extends StatefulWidget {
  const CalendarSyncSelectionScreen({super.key});

  @override
  State<CalendarSyncSelectionScreen> createState() => _CalendarSyncSelectionScreenState();
}

class _CalendarSyncSelectionScreenState extends State<CalendarSyncSelectionScreen> {
  bool _isLoading = true;
  bool _isSyncEnabled = false;
  String? _selectedCalendarId;
  String? _selectedCalendarName;
  String? _selectedCalendarAccount;
  List<dc.Calendar> _calendars = [];
  bool _isActionInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadSyncStatus();
  }

  Future<void> _loadSyncStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _isSyncEnabled = await SystemCalendarService.isSystemSyncEnabled();
      _selectedCalendarId = await SystemCalendarService.getSystemCalendarId();
      _selectedCalendarName = await SystemCalendarService.getSystemCalendarName();
      _selectedCalendarAccount = await SystemCalendarService.getSystemCalendarAccountName();

      if (await SystemCalendarService.checkOrRequestPermissions()) {
        _calendars = await SystemCalendarService.getWritableCalendars();
        if (_selectedCalendarId != null && _calendars.isNotEmpty) {
          final matched = _calendars.where((c) => c.id == _selectedCalendarId);
          if (matched.isNotEmpty) {
            final cal = matched.first;
            _selectedCalendarName = _getCalendarDisplayName(cal);
            _selectedCalendarAccount = _getCalendarAccountName(cal);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading calendar sync status: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getCalendarDisplayName(dc.Calendar cal) {
    if (cal.accountType == 'com.google' && cal.name == cal.accountName) {
      return 'Google Calendar';
    } else if (cal.name.toLowerCase() == 'my calendar') {
      return 'My Calendar';
    } else if (cal.accountType != null && cal.accountType!.toLowerCase().contains('samsung')) {
      return 'Samsung Calendar';
    } else {
      return cal.name.isEmpty ? 'Calendar' : cal.name;
    }
  }

  String _getCalendarAccountName(dc.Calendar cal) {
    if (cal.accountName == null || cal.accountName!.trim().isEmpty) {
      return 'Local Device';
    } else if (cal.accountName!.toLowerCase() == 'my calendar') {
      return 'Local Offline';
    } else {
      return cal.accountName!;
    }
  }

  Future<void> _toggleSync(bool value) async {
    if (value) {
      setState(() => _isActionInProgress = true);
      try {
        final hasPerm = await SystemCalendarService.checkOrRequestPermissions();
        if (!hasPerm) {
          if (mounted) {
            SnackbarUtils.showErrorSnackBar(context, 'Calendar permissions are required to sync timetable.');
          }
          return;
        }

        final calendars = await SystemCalendarService.getWritableCalendars();
        if (calendars.isEmpty) {
          if (mounted) {
            SnackbarUtils.showErrorSnackBar(context, 'No writable calendars found on this device.');
          }
          return;
        }

        dc.Calendar? targetCal;
        if (_selectedCalendarId != null) {
          final found = calendars.where((c) => c.id == _selectedCalendarId);
          if (found.isNotEmpty) {
            targetCal = found.first;
          }
        }

        final targetId = targetCal?.id;
        final targetName = targetCal != null ? _getCalendarDisplayName(targetCal) : null;
        final targetAccount = targetCal != null ? _getCalendarAccountName(targetCal) : null;

        await SystemCalendarService.setSystemSyncEnabled(
          true,
          calendarId: targetId,
          calendarName: targetName,
          accountName: targetAccount,
        );

        if (mounted) {
          setState(() {
            _calendars = calendars;
            _isSyncEnabled = true;
            _selectedCalendarId = targetId;
            _selectedCalendarName = targetName;
            _selectedCalendarAccount = targetAccount;
          });
        }
      } catch (e) {
        if (mounted) {
          SnackbarUtils.showErrorSnackBar(context, 'Error enabling calendar sync: $e');
        }
      } finally {
        if (mounted) {
          setState(() => _isActionInProgress = false);
        }
      }
    } else {
      setState(() => _isActionInProgress = true);
      try {
        final currentCalId = _selectedCalendarId;
        final ok = await SyncProgressDialog.show(
          context: context,
          title: 'Clearing Calendar Events',
          action: (onProgress) => SystemCalendarService.deleteSyncedEvents(
            force: true,
            calendarId: currentCalId,
            onProgress: onProgress,
          ),
        );

        await SystemCalendarService.setSystemSyncEnabled(false);
        if (mounted) {
          setState(() {
            _isSyncEnabled = false;
            _selectedCalendarId = null;
            _selectedCalendarName = null;
            _selectedCalendarAccount = null;
          });
          if (ok == true) {
            SnackbarUtils.showSuccessSnackBar(context, 'Calendar sync disabled. Synced events cleared.');
          }
        }
      } catch (e) {
        if (mounted) {
          SnackbarUtils.showErrorSnackBar(context, 'Error disabling calendar sync: $e');
        }
      } finally {
        if (mounted) {
          setState(() => _isActionInProgress = false);
        }
      }
    }
  }

  Future<void> _onCalendarChanged(dc.Calendar cal) async {
    final targetId = cal.id;
    final targetName = _getCalendarDisplayName(cal);
    final targetAccount = _getCalendarAccountName(cal);

    if (targetId == _selectedCalendarId) return;

    if (!mounted) return;
    setState(() => _isActionInProgress = true);

    try {
      final oldCalId = _selectedCalendarId;
      if (oldCalId != null && oldCalId != targetId) {
        await SyncProgressDialog.show(
          context: context,
          title: 'Pruning Old Calendar Events',
          action: (onProgress) => SystemCalendarService.deleteSyncedEvents(
            force: true,
            calendarId: oldCalId,
            onProgress: onProgress,
          ),
        );
      }

      await SystemCalendarService.setSystemSyncEnabled(
        true,
        calendarId: targetId,
        calendarName: targetName,
        accountName: targetAccount,
      );

      if (mounted) {
        setState(() {
          _selectedCalendarId = targetId;
          _selectedCalendarName = targetName;
          _selectedCalendarAccount = targetAccount;
        });
      }

      await _triggerSystemSync();
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Error changing calendar: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _confirmCleanUpCalendar() async {
    final destination = _selectedCalendarName != null
        ? '$_selectedCalendarName (${_selectedCalendarAccount ?? "Local Device"})'
        : 'your device calendar';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Clean Up Calendar?'),
          ],
        ),
        content: Text(
          'This will permanently delete all timetable classes and schedule entries created by AttendMate from $destination.\n\nYour personal calendar events and schedules will remain completely untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clean Up'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isActionInProgress = true);
    try {
      final currentCalId = _selectedCalendarId;
      final ok = await SyncProgressDialog.show(
        context: context,
        title: 'Pruning Calendar Events',
        action: (onProgress) => SystemCalendarService.deleteSyncedEvents(
          force: true,
          calendarId: currentCalId,
          onProgress: onProgress,
        ),
      );

      if (mounted) {
        if (ok == true) {
          SnackbarUtils.showSuccessSnackBar(context, 'All AttendMate calendar events have been pruned successfully.');
        }
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Error cleaning calendar events: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _triggerSystemSync() async {
    if (_selectedCalendarId == null) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Please select a calendar account from the dropdown first.');
      }
      return;
    }

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

    setState(() => _isActionInProgress = true);

    try {
      final ok = await SyncProgressDialog.show(
        context: context,
        title: 'Syncing Calendar',
        action: (onProgress) => SystemCalendarService.syncFullTimetable(
          subjects: subjectProvider.subjects,
          semester: semesterProvider.semester!,
          isHoliday: subjectProvider.isHoliday,
          onProgress: onProgress,
        ),
      );

      if (ok == true && mounted) {
        final destinationLabel = _selectedCalendarAccount != null
            ? '${_selectedCalendarName ?? "Calendar"} ($_selectedCalendarAccount)'
            : (_selectedCalendarName ?? 'your calendar');
        SnackbarUtils.showSuccessSnackBar(
          context,
          'Timetable successfully synced to $destinationLabel!',
        );
        try {
          await NotificationService().showBackupNotification(
            title: 'Calendar Synced',
            body: 'Timetable was synced to $destinationLabel.',
          );
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Calendar Sync Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isActionInProgress = false);
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat.yMMMd().format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semester = Provider.of<SemesterProvider>(context).semester;
    final subjects = Provider.of<SubjectProvider>(context).subjects;

    return PopScope(
      canPop: !_isActionInProgress,
      child: Scaffold(
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
                      // Primary Sync Card
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
                                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.calendar_month_rounded,
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
                                          'Sync Timetable to Calendar',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _isSyncEnabled && _selectedCalendarName != null
                                              ? 'Synced to $_selectedCalendarName${_selectedCalendarAccount != null ? " ($_selectedCalendarAccount)" : ""}'
                                              : 'Sync class timetable to Google Calendar, Samsung Calendar, or Phone Calendar',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _isSyncEnabled,
                                    onChanged: _isActionInProgress ? null : _toggleSync,
                                  ),
                                ],
                              ),

                              if (_isSyncEnabled) ...[
                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 12),

                                // Active Destination Card (showing App and Account email properly)
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle_rounded,
                                            size: 18,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Active Destination',
                                            style: theme.textTheme.labelMedium?.copyWith(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Text(
                                            'App: ',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              _selectedCalendarName ?? 'None selected',
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: _selectedCalendarName != null
                                                    ? theme.colorScheme.onSurface
                                                    : theme.colorScheme.onSurfaceVariant,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Text(
                                            'Account: ',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              _selectedCalendarAccount ?? 'Select an account below',
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: _selectedCalendarAccount != null
                                                    ? theme.colorScheme.onSurface.withValues(alpha: 0.85)
                                                    : theme.colorScheme.onSurfaceVariant,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Destination Calendar Dropdown Selector (NO icons)
                                Text(
                                  'Select Calendar Account',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                Builder(
                                  builder: (context) {
                                    final hasSelectedCalendar = _selectedCalendarId != null &&
                                        _calendars.any((c) => c.id == _selectedCalendarId);
                                    final dropdownValue = hasSelectedCalendar ? _selectedCalendarId : null;
                                    final seenIds = <String>{};
                                    final dropdownItems = <DropdownMenuItem<String>>[];
                                    for (final cal in _calendars) {
                                      if (cal.id != null && seenIds.add(cal.id!)) {
                                        final appName = _getCalendarDisplayName(cal);
                                        final accName = _getCalendarAccountName(cal);
                                        dropdownItems.add(
                                          DropdownMenuItem<String>(
                                            value: cal.id,
                                            child: Text(
                                              '$appName ($accName)',
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        );
                                      }
                                    }

                                    if (dropdownItems.isEmpty) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 8.0),
                                        child: Text('No writable calendars found on this device.'),
                                      );
                                    }

                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        DropdownButtonFormField<String>(
                                          value: dropdownValue,
                                          isExpanded: true,
                                          hint: Text(
                                            'Select calendar account...',
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          decoration: InputDecoration(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          items: dropdownItems,
                                          onChanged: _isActionInProgress
                                              ? null
                                              : (newId) {
                                                  if (newId != null && newId != _selectedCalendarId) {
                                                    final cal = _calendars.firstWhere((c) => c.id == newId);
                                                    _onCalendarChanged(cal);
                                                  }
                                                },
                                        ),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          width: double.infinity,
                                          child: FilledButton.icon(
                                            icon: const Icon(Icons.sync_rounded, size: 18),
                                            label: const Text('Sync Timetable Now'),
                                            onPressed: (_isActionInProgress || dropdownValue == null)
                                                ? null
                                                : _triggerSystemSync,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            icon: Icon(Icons.delete_sweep_rounded, size: 18, color: theme.colorScheme.error),
                                            label: Text('Clean Up Calendar Events', style: TextStyle(color: theme.colorScheme.error)),
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                                            ),
                                            onPressed: _isActionInProgress ? null : _confirmCleanUpCalendar,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Sync Bounds Card
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
                                'Notice: Only class events within your semester dates are synced. Other personal calendar events remain completely untouched.',
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
                        Icons.bolt_rounded,
                        'Zero Latency & No Rate Limits',
                        'Direct native OS calendar synchronization writes instantly without network lag or API quota restrictions.',
                      ),
                      _buildFeatureTile(
                        Icons.cloud_sync_rounded,
                        'Automatic Cloud Sync',
                        'When syncing to a Google account, Android automatically mirrors your schedule to Google Calendar in the cloud and web.',
                      ),
                      _buildFeatureTile(
                        Icons.auto_mode_rounded,
                        'Automatic Schedule Updates',
                        'Modifications made to classes, rooms, or timeslots automatically reflect in your active calendar in the background.',
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
