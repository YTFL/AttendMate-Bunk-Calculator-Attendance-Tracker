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

      if (await SystemCalendarService.checkOrRequestPermissions()) {
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

  Future<dc.Calendar?> _showCalendarAccountPickerDialog(List<dc.Calendar> calendars) async {
    final theme = Theme.of(context);
    return showDialog<dc.Calendar>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(
            Icons.calendar_month_rounded,
            size: 36,
            color: theme.colorScheme.primary,
          ),
          title: const Text('Select Calendar Account'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose which account or calendar to synchronize your class schedule with:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(dialogContext).size.height * 0.45,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: calendars.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final cal = calendars[index];
                      final isSelected = cal.id == _selectedCalendarId;
                      final displayName = _getCalendarDisplayName(cal);
                      final accountName = _getCalendarAccountName(cal);
                      final calColor = cal.color;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: calColor?.withValues(alpha: 0.15) ?? theme.colorScheme.primaryContainer,
                            border: Border.all(
                              color: calColor ?? theme.colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.calendar_today_rounded,
                            size: 18,
                            color: calColor ?? theme.colorScheme.primary,
                          ),
                        ),
                        title: Text(
                          displayName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          accountName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                            : null,
                        onTap: () => Navigator.of(dialogContext).pop(cal),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleSync(bool value) async {
    if (value) {
      // 1. Request / check permissions
      setState(() => _isActionInProgress = true);
      final hasPerm = await SystemCalendarService.checkOrRequestPermissions();
      if (!hasPerm) {
        setState(() => _isActionInProgress = false);
        if (mounted) {
          SnackbarUtils.showErrorSnackBar(context, 'Calendar permissions are required to sync timetable.');
        }
        return;
      }

      // 2. Query writable calendars
      final calendars = await SystemCalendarService.getWritableCalendars();
      setState(() {
        _isActionInProgress = false;
      });

      if (calendars.isEmpty) {
        if (mounted) {
          SnackbarUtils.showErrorSnackBar(context, 'No writable calendars found on this device.');
        }
        return;
      }

      // 3. User must select account before sync begins
      final chosenCal = await _showCalendarAccountPickerDialog(calendars);
      if (chosenCal == null) {
        // User cancelled picker -> keep toggle OFF
        return;
      }

      final targetId = chosenCal.id;
      final targetName = _getCalendarDisplayName(chosenCal);

      await SystemCalendarService.setSystemSyncEnabled(
        true,
        calendarId: targetId,
        calendarName: targetName,
      );

      if (mounted) {
        setState(() {
          _isSyncEnabled = true;
          _selectedCalendarId = targetId;
          _selectedCalendarName = targetName;
        });
      }

      // 4. Trigger initial full sync
      await _triggerSystemSync();
    } else {
      // Toggle OFF: Confirm and clear events
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

  Future<void> _handleChangeAccount() async {
    setState(() => _isActionInProgress = true);
    final hasPerm = await SystemCalendarService.checkOrRequestPermissions();
    if (!hasPerm) {
      setState(() => _isActionInProgress = false);
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Calendar permissions required.');
      }
      return;
    }

    final calendars = await SystemCalendarService.getWritableCalendars();
    setState(() {
      _isActionInProgress = false;
    });

    if (calendars.isEmpty) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'No writable calendars found on this device.');
      }
      return;
    }

    final chosenCal = await _showCalendarAccountPickerDialog(calendars);
    if (chosenCal == null || chosenCal.id == _selectedCalendarId) {
      return;
    }

    if (!mounted) return;
    setState(() => _isActionInProgress = true);
    try {
      final oldCalId = _selectedCalendarId;
      if (oldCalId != null) {
        await SyncProgressDialog.show(
          context: context,
          title: 'Clearing Previous Calendar Events',
          action: (onProgress) => SystemCalendarService.deleteSyncedEvents(
            force: true,
            calendarId: oldCalId,
            onProgress: onProgress,
          ),
        );
      }

      final targetId = chosenCal.id;
      final targetName = _getCalendarDisplayName(chosenCal);

      await SystemCalendarService.setSystemSyncEnabled(
        true,
        calendarId: targetId,
        calendarName: targetName,
      );

      if (mounted) {
        setState(() {
          _selectedCalendarId = targetId;
          _selectedCalendarName = targetName;
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
        SnackbarUtils.showSuccessSnackBar(
          context,
          'Timetable successfully synced to ${_selectedCalendarName ?? "your calendar"}!',
        );
        try {
          await NotificationService().showBackupNotification(
            title: 'Calendar Synced',
            body: 'Timetable was synced to ${_selectedCalendarName ?? "calendar"}.',
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
                                              ? 'Synced to $_selectedCalendarName'
                                              : 'Sync class timetable to Google, Outlook, or Phone Calendar',
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

                                // Current active calendar display
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 20,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Active Destination',
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                color: theme.colorScheme.onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            Text(
                                              _selectedCalendarName ?? 'Calendar',
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      OutlinedButton(
                                        onPressed: _isActionInProgress ? null : _handleChangeAccount,
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                        ),
                                        child: const Text('Change Account'),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    icon: const Icon(Icons.sync_rounded, size: 18),
                                    label: const Text('Sync Timetable Now'),
                                    onPressed: _isActionInProgress ? null : _triggerSystemSync,
                                  ),
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
                        'When syncing to a Google or Outlook account, Android automatically mirrors your schedule to Google Calendar and Outlook in the cloud.',
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
