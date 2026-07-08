// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart' as dc;
import '../../services/calendar_service.dart';
import '../../services/system_calendar_service.dart';
import '../semester/semester_provider.dart';
import '../subject/subject_provider.dart';
import 'google_calendar_sync_screen.dart';
import '../../utils/snackbar_utils.dart';

class CalendarSyncSelectionScreen extends StatefulWidget {
  const CalendarSyncSelectionScreen({super.key});

  @override
  State<CalendarSyncSelectionScreen> createState() => _CalendarSyncSelectionScreenState();
}

class _CalendarSyncSelectionScreenState extends State<CalendarSyncSelectionScreen> {
  bool _isLoading = true;
  bool _isGoogleConnected = false;
  String? _googleEmail;

  bool _isSystemSyncEnabled = false;
  String? _selectedSystemCalendarId;
  String? _selectedSystemCalendarName;
  List<dc.Calendar> _systemCalendars = [];

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
      // 1. Google Status
      _isGoogleConnected = await CalendarService.isUserSignedIn();
      if (_isGoogleConnected) {
        _googleEmail = await CalendarService.getSignedInUserEmail();
      } else {
        _googleEmail = null;
      }

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
      setState(() {
        _isLoading = false;
      });
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
            ScaffoldMessenger.of(context).showReplacingSnackBar(
              const SnackBar(
                content: Text('Calendar permissions are required to sync to device calendars.'),
                backgroundColor: Colors.red,
              ),
            );
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
            ScaffoldMessenger.of(context).showReplacingSnackBar(
              const SnackBar(
                content: Text('No writable calendars found on this device.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          setState(() {
            _isActionInProgress = false;
          });
          return;
        }

        // Set default calendar if none selected
        final defaultCalendar = calendars.first;
        final targetId = _selectedSystemCalendarId ?? defaultCalendar.id;
        final targetName = _selectedSystemCalendarName ?? defaultCalendar.name;

        await SystemCalendarService.setSystemSyncEnabled(true, calendarId: targetId, calendarName: targetName);
        _selectedSystemCalendarId = targetId;
        _selectedSystemCalendarName = targetName;
        _isSystemSyncEnabled = true;

        // Perform initial sync in background
        _triggerSystemSync();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showReplacingSnackBar(
            SnackBar(
              content: Text('Error enabling system sync: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        setState(() {
          _isActionInProgress = false;
        });
      }
    } else {
      // Disable and clean up
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
          ScaffoldMessenger.of(context).showReplacingSnackBar(
            const SnackBar(
              content: Text('Disabled device calendar sync and removed all events.'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showReplacingSnackBar(
            SnackBar(
              content: Text('Error disabling system sync: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        setState(() {
          _isActionInProgress = false;
        });
      }
    }
  }

  Future<void> _changeSystemCalendar(String calendarId) async {
    final selectedCal = _systemCalendars.firstWhere((cal) => cal.id == calendarId);
    
    setState(() {
      _isActionInProgress = true;
    });

    try {
      // 1. Delete events from old calendar
      await SystemCalendarService.deleteSyncedEvents();

      // 2. Set new calendar
      await SystemCalendarService.setSystemSyncEnabled(
        true,
        calendarId: selectedCal.id,
        calendarName: selectedCal.name,
      );

      setState(() {
        _selectedSystemCalendarId = selectedCal.id;
        _selectedSystemCalendarName = selectedCal.name;
      });

      // 3. Sync to new calendar
      await _triggerSystemSync();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text('Error changing calendar: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('Timetable will sync once semester dates are configured in Semester Details.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (subjectProvider.subjects.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('No subjects/schedule to sync.'),
            backgroundColor: Colors.orange,
          ),
        );
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
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text('Timetable successfully synced to "$_selectedSystemCalendarName"!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text('Device Calendar Sync Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
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
      displayName = cal.name;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar Synchronization'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Info Header Card
                Card(
                  elevation: 0,
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.sync_rounded,
                          color: theme.colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unified Timetable Sync',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Keep your weekly schedules, timetable classes, and cancelled dates perfectly synced. Choose Google Calendar (tied to your Google account) or Device Calendar (writes to Samsung, Outlook, or other local accounts).',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Card: Google Calendar Sync Option
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GoogleCalendarSyncScreen(),
                        ),
                      );
                      _loadSyncStatus(); // reload status upon return
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
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
                                const SizedBox(height: 4),
                                Text(
                                  _isGoogleConnected
                                      ? 'Connected: $_googleEmail'
                                      : 'Not connected. Connect to write schedules online.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: _isGoogleConnected
                                        ? Colors.green.shade700
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: theme.colorScheme.outline,
                          ),
                        ],
                      ),
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
                                color: theme.colorScheme.secondary.withValues(alpha: 0.08),
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
                                  const SizedBox(height: 4),
                                  Text(
                                    _isSystemSyncEnabled
                                        ? (() {
                                            final cal = _systemCalendars.cast<dc.Calendar?>().firstWhere(
                                              (c) => c?.id == _selectedSystemCalendarId,
                                              orElse: () => null,
                                            );
                                            if (cal != null) {
                                              return 'Syncing to: ${_formatCalendarLabel(cal)}';
                                            }
                                            return 'Syncing to: ${_selectedSystemCalendarName ?? "No calendar selected"}';
                                          })()
                                        : 'Writes directly to local accounts (Outlook, etc.).',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: _isSystemSyncEnabled
                                          ? Colors.green.shade700
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_isActionInProgress)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              Switch(
                                value: _isSystemSyncEnabled,
                                onChanged: _toggleSystemSync,
                              ),
                          ],
                        ),

                        // Calendar Selector & Sync Action if enabled
                        if (_isSystemSyncEnabled && !_isActionInProgress) ...[
                          const SizedBox(height: 20),
                          const Divider(),
                          const SizedBox(height: 12),
                          
                          // Dropdown selector
                          Text(
                            'Select Destination Calendar',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedSystemCalendarId,
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
                            onChanged: (val) {
                              if (val != null && val != _selectedSystemCalendarId) {
                                _changeSystemCalendar(val);
                              }
                            },
                          ),
                          const SizedBox(height: 20),

                          // Manual Force Sync Button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _triggerSystemSync,
                              icon: const Icon(Icons.sync_rounded),
                              label: const Text('Sync to Device Calendar Now'),
                              style: ElevatedButton.styleFrom(
                                foregroundColor: theme.colorScheme.onPrimary,
                                backgroundColor: theme.colorScheme.secondary,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
