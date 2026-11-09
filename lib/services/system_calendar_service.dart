import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/subject/subject_model.dart';
import '../features/semester/semester_model.dart';
import '../features/attendance/attendance_model.dart';
import 'database_service.dart';

class SystemCalendarService {
  /// Concurrency mutex to prevent parallel overlapping sync cycles
  static bool _isSyncInProgress = false;

  /// Native Android MethodChannel for direct calendar provider interaction and sync trigger
  static const MethodChannel _nativeChannel = MethodChannel('com.attendmate.app/calendar');

  static Future<int> _nativePruneEvents(String? calendarId) async {
    try {
      final int? count = await _nativeChannel.invokeMethod<int>('pruneAttendMateEvents', {'calendarId': calendarId});
      return count ?? 0;
    } catch (e) {
      debugPrint('Native pruneAttendMateEvents error: $e');
      return 0;
    }
  }

  static Future<bool> _nativeDeleteEvent(String eventId) async {
    try {
      final bool? ok = await _nativeChannel.invokeMethod<bool>('deleteEvent', {'eventId': eventId});
      return ok ?? false;
    } catch (e) {
      debugPrint('Native deleteEvent error: $e');
      return false;
    }
  }

  static Future<bool> _nativeSetEventColor(String eventId, int color) async {
    try {
      final bool? ok = await _nativeChannel.invokeMethod<bool>('setEventColor', {
        'eventId': eventId,
        'color': color,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('Native setEventColor error: $e');
      return false;
    }
  }

  static Future<void> _nativeTriggerSync() async {
    try {
      await _nativeChannel.invokeMethod('triggerCalendarSync');
    } catch (e) {
      debugPrint('Native triggerCalendarSync error: $e');
    }
  }

  /// Checks and requests permissions to read/write device calendars.
  static Future<bool> checkOrRequestPermissions() async {
    final plugin = DeviceCalendar.instance;
    var permissionsResult = await plugin.hasPermissions();
    if (permissionsResult == CalendarPermissionStatus.granted) {
      return true;
    }
    permissionsResult = await plugin.requestPermissions();
    return permissionsResult == CalendarPermissionStatus.granted;
  }

  /// Retrieves a list of writable calendars on the user's device.
  static Future<List<Calendar>> getWritableCalendars() async {
    try {
      final plugin = DeviceCalendar.instance;
      final hasPerm = await checkOrRequestPermissions();
      if (!hasPerm) return [];

      final result = await plugin.listCalendars();
      for (final cal in result) {
        debugPrint('RETRIEVED CALENDAR: id=${cal.id}, name=${cal.name}, accountName=${cal.accountName}, accountType=${cal.accountType}, readOnly=${cal.readOnly}');
      }
      // Return only writable calendars, and exclude holiday and Outlook/Exchange read-only feeds
      return result.where((cal) {
        if (cal.readOnly == true) return false;
        final name = cal.name.toLowerCase();
        if (name.contains('holidays in')) return false;
        if (name.contains('outlook')) return false;
        if (cal.accountType != null) {
          final accType = cal.accountType!.toLowerCase();
          if (accType.contains('outlook') || accType.contains('exchange') || accType.contains('office365')) {
            return false;
          }
        }
        return true;
      }).toList();
    } catch (e) {
      debugPrint('Error retrieving calendars: $e');
    }
    return [];
  }

  /// Sets system calendar synchronization preferences in SharedPreferences.
  static Future<void> setSystemSyncEnabled(
    bool enabled, {
    String? calendarId,
    String? calendarName,
    String? accountName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('system_calendar_sync_enabled', enabled);
    if (enabled && calendarId != null && calendarName != null) {
      await prefs.setString('system_calendar_id', calendarId);
      await prefs.setString('system_calendar_name', calendarName);
      if (accountName != null) {
        await prefs.setString('system_calendar_account_name', accountName);
      }
    } else if (!enabled) {
      await prefs.remove('system_calendar_id');
      await prefs.remove('system_calendar_name');
      await prefs.remove('system_calendar_account_name');
    }
  }

  /// Retrieves the selected system calendar's account name / email.
  static Future<String?> getSystemCalendarAccountName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('system_calendar_account_name');
  }

  /// Checks if system calendar synchronization is enabled.
  static Future<bool> isSystemSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('system_calendar_sync_enabled') ?? false;
  }

  /// Retrieves the selected system calendar ID from SharedPreferences.
  static Future<String?> getSystemCalendarId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('system_calendar_id');
  }

  /// Retrieves the selected system calendar display name from SharedPreferences.
  static Future<String?> getSystemCalendarName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('system_calendar_name');
  }

  /// Deletes all events synced by AttendMate from the system calendar and purges SQLite mappings.
  /// Employs a multi-round pruning strategy:
  /// Round 1: Native batch delete directly from CalendarProvider (without CALLER_IS_SYNCADAPTER).
  /// Round 2: Native + plugin deletion of all tracked SQLite mappings.
  /// Round 3: Multi-pass inspection sweep to guarantee 0 leftovers across the entire date spectrum.
  static Future<void> deleteSyncedEvents({
    bool force = false,
    String? calendarId,
    void Function(double progress, String statusMessage)? onProgress,
  }) async {
    try {
      if (kDebugMode && !force) {
        final prefs = await SharedPreferences.getInstance();
        final isDevSyncEnabled = prefs.getBool('dev_mode_calendar_sync_enabled') ?? false;
        if (!isDevSyncEnabled) {
          debugPrint('System Calendar deleteSyncedEvents bypassed in debug mode (disabled under Developer Options).');
          return;
        }
      }

      final hasPerm = await checkOrRequestPermissions();
      if (!hasPerm) {
        debugPrint('System Calendar delete skipped: calendar permissions not granted.');
        onProgress?.call(1.0, 'Calendar permissions not granted.');
        return;
      }

      final plugin = DeviceCalendar.instance;
      final db = DatabaseService();
      final targetCalId = calendarId ?? await getSystemCalendarId();

      onProgress?.call(0.1, 'Pruning calendar events...');

      // Round 1: Native direct batch delete on CalendarProvider (marks DELETED=1 & DIRTY=1)
      final nativePruned = await _nativePruneEvents(targetCalId);
      debugPrint('Native batch pruned $nativePruned AttendMate events.');

      // Round 2: Delete all events recorded in local SQLite database
      final events = await db.getAllSystemCalendarEvents();
      int completed = 0;
      final total = events.length;
      for (final eventMap in events) {
        final String eventId = eventMap['eventId'] as String;
        try {
          final ok = await _nativeDeleteEvent(eventId);
          if (!ok) {
            await plugin.deleteEvent(eventId: eventId);
          }
        } catch (e) {
          debugPrint('Failed to delete system event $eventId: $e');
        }
        completed++;
        final p = total > 0 ? (0.2 + (completed / total) * 0.4) : 0.6;
        onProgress?.call(p, 'Clearing recorded events ($completed/$total)...');
      }
      await db.clearSystemCalendarEvents();

      // Round 3: Multi-pass inspection sweep to verify 0 leftover AttendMate events
      onProgress?.call(0.65, 'Verifying calendar clean-up...');
      final List<String> calIdsToScan = [];
      if (targetCalId != null) {
        calIdsToScan.add(targetCalId);
      } else {
        final allCals = await getWritableCalendars();
        calIdsToScan.addAll(allCals.map((c) => c.id).whereType<String>());
      }

      if (calIdsToScan.isNotEmpty) {
        final now = DateTime.now();
        final startDate = now.subtract(const Duration(days: 1095));
        final endDate = now.add(const Duration(days: 1095));

        for (int pass = 1; pass <= 2; pass++) {
          final Set<String> leftovers = {};
          for (final calId in calIdsToScan) {
            try {
              final listedEvents = await plugin.listEvents(startDate, endDate, calendarIds: [calId]);
              for (final ev in listedEvents) {
                final desc = ev.description?.toLowerCase() ?? '';
                final title = ev.title?.toLowerCase() ?? '';
                final isMatch = desc.contains('imported from attendmate') ||
                    desc.contains('created with attendmate') ||
                    desc.contains('attendmate') ||
                    title.contains('attendmate');
                if (isMatch) {
                  leftovers.add(ev.eventId);
                }
              }
            } catch (e) {
              debugPrint('Error inspecting calendar $calId on pass $pass: $e');
            }
          }

          if (leftovers.isEmpty) break;

          int sweepCompleted = 0;
          for (final evId in leftovers) {
            try {
              final ok = await _nativeDeleteEvent(evId);
              if (!ok) {
                await plugin.deleteEvent(eventId: evId);
              }
            } catch (e) {
              debugPrint('Failed to sweep device calendar event $evId: $e');
            }
            sweepCompleted++;
            final p = 0.7 + (sweepCompleted / leftovers.length) * 0.25;
            onProgress?.call(p, 'Pruning leftovers ($sweepCompleted/${leftovers.length})...');
          }
        }
      }

      await _nativeTriggerSync();
      onProgress?.call(1.0, 'Calendar events cleared successfully.');
    } catch (e) {
      debugPrint('Error deleting synced system events: $e');
    }
  }

  /// Deep scan and prune all events created by AttendMate across all writable device calendars.
  static Future<int> pruneAllAttendMateEvents() async {
    int prunedCount = 0;
    try {
      final plugin = DeviceCalendar.instance;
      final hasPerm = await checkOrRequestPermissions();
      if (!hasPerm) {
        debugPrint('System Calendar prune failed: permissions not granted.');
        return 0;
      }

      // Native batch delete across all calendars
      prunedCount += await _nativePruneEvents(null);

      final Set<String> deletedEventIds = {};
      final calendars = await getWritableCalendars();
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 1095));
      final endDate = now.add(const Duration(days: 1095));

      for (final cal in calendars) {
        try {
          final events = await plugin.listEvents(startDate, endDate, calendarIds: [cal.id]);
          for (final event in events) {
            final desc = event.description?.toLowerCase() ?? '';
            final title = event.title?.toLowerCase() ?? '';

            final isMatch = desc.contains('imported from attendmate') ||
                desc.contains('created with attendmate') ||
                desc.contains('attendmate') ||
                title.contains('attendmate');

            if (isMatch && !deletedEventIds.contains(event.eventId)) {
              try {
                final ok = await _nativeDeleteEvent(event.eventId);
                if (!ok) {
                  await plugin.deleteEvent(eventId: event.eventId);
                }
                deletedEventIds.add(event.eventId);
                prunedCount++;
              } catch (e) {
                debugPrint('Failed to delete system event ${event.eventId}: $e');
              }
            }
          }
        } catch (e) {
          debugPrint('Error scanning calendar ${cal.id}: $e');
        }
      }

      final db = DatabaseService();
      final savedEvents = await db.getAllSystemCalendarEvents();
      for (final eventMap in savedEvents) {
        final String eventId = eventMap['eventId'] as String;
        if (!deletedEventIds.contains(eventId)) {
          try {
            final ok = await _nativeDeleteEvent(eventId);
            if (!ok) {
              await plugin.deleteEvent(eventId: eventId);
            }
            deletedEventIds.add(eventId);
            prunedCount++;
          } catch (e) {
            debugPrint('Failed to delete system event $eventId: $e');
          }
        }
      }

      await db.clearSystemCalendarEvents();
      await _nativeTriggerSync();
      debugPrint('Pruned $prunedCount system calendar events.');
    } catch (e) {
      debugPrint('Error pruning system calendar events: $e');
      rethrow;
    }
    return prunedCount;
  }

  /// Declaratively synchronizes subjects, slots, holidays, and cancellations to the chosen system calendar.
  /// Includes real-time event-by-event progress calculation and subject color synchronization.
  static Future<void> syncFullTimetable({
    required List<Subject> subjects,
    required Semester? semester,
    required bool Function(DateTime) isHoliday,
    void Function(double progress, String statusMessage)? onProgress,
  }) async {
    if (_isSyncInProgress) {
      debugPrint('System Calendar sync skipped: another sync cycle is already in progress.');
      return;
    }
    _isSyncInProgress = true;

    try {
      if (kDebugMode) {
        final prefs = await SharedPreferences.getInstance();
        final isDevSyncEnabled = prefs.getBool('dev_mode_calendar_sync_enabled') ?? false;
        if (!isDevSyncEnabled) {
          debugPrint('System Calendar Sync bypassed in debug mode (disabled under Developer Options).');
          return;
        }
      }
      if (semester == null || subjects.isEmpty) return;

      final calendarId = await getSystemCalendarId();
      final enabled = await isSystemSyncEnabled();
      if (!enabled || calendarId == null) return;

      final plugin = DeviceCalendar.instance;
      final db = DatabaseService();

      final plannedLeaves = await db.loadPlannedLeaves();

      // Track active event IDs in this run
      final Set<String> activeEventIds = {};

      // Calculate start and end dates
      final DateTime startDate = semester.startDate;
      final DateTime endDate = semester.endDate;

      // 1. Precompute all class occurrences to obtain exact total class count for smooth progress
      final List<_TimetableSyncItem> itemsToSync = [];

      for (final subject in subjects) {
        for (final slot in subject.schedule) {
          final targetWeekday = slot.day.index + 1; // weekday in DateTime is 1-7

          DateTime currentDate = startDate;
          while (!currentDate.isAfter(endDate)) {
            if (currentDate.weekday == targetWeekday) {
              final dateOnly = DateTime(currentDate.year, currentDate.month, currentDate.day);

              final slotFrom = slot.effectiveFrom;
              final slotUntil = slot.effectiveUntil;
              final specificDate = slot.specificDate;

              bool withinValidity = true;
              if (specificDate != null &&
                  (dateOnly.year != specificDate.year ||
                      dateOnly.month != specificDate.month ||
                      dateOnly.day != specificDate.day)) {
                withinValidity = false;
              }
              if (slotFrom != null && dateOnly.isBefore(DateTime(slotFrom.year, slotFrom.month, slotFrom.day))) {
                withinValidity = false;
              }
              if (slotUntil != null && dateOnly.isAfter(DateTime(slotUntil.year, slotUntil.month, dateOnly.day))) {
                withinValidity = false;
              }

              if (withinValidity) {
                itemsToSync.add(_TimetableSyncItem(
                  subject: subject,
                  slot: slot,
                  dateOnly: dateOnly,
                ));
              }
            }
            currentDate = currentDate.add(const Duration(days: 1));
          }
        }
      }

      final totalEvents = itemsToSync.length;
      int completedEvents = 0;
      onProgress?.call(0.02, 'Preparing to sync $totalEvents class schedule entries...');

      for (final item in itemsToSync) {
        final subject = item.subject;
        final slot = item.slot;
        final dateOnly = item.dateOnly;

        final startDateTime = DateTime(
          dateOnly.year,
          dateOnly.month,
          dateOnly.day,
          slot.startTime.hour,
          slot.startTime.minute,
        );
        final endDateTime = DateTime(
          dateOnly.year,
          dateOnly.month,
          dateOnly.day,
          slot.endTime.hour,
          slot.endTime.minute,
        );

        bool isExcluded = isHoliday(dateOnly);
        if (!isExcluded) {
          for (final leave in plannedLeaves) {
            if (leave.affectedSubjectIds.isEmpty || leave.affectedSubjectIds.contains(subject.id)) {
              if (startDateTime.isBefore(leave.endDate) && endDateTime.isAfter(leave.startDate)) {
                isExcluded = true;
                break;
              }
            }
          }
        }

        for (final record in subject.attendanceRecords) {
          if (record.date.year == dateOnly.year &&
              record.date.month == dateOnly.month &&
              record.date.day == dateOnly.day &&
              (record.slotKey == null || record.slotKey == slot.slotKey || record.slotKey!.isEmpty)) {
            if (record.status == AttendanceStatus.cancelled || record.status == AttendanceStatus.absent) {
              isExcluded = true;
            } else if (record.status == AttendanceStatus.attended) {
              isExcluded = false;
            }
            break;
          }
        }

        final String slotKey = slot.slotKey;
        final existingEventId = await db.getSystemCalendarEvent(
          subjectId: subject.id,
          slotKey: slotKey,
          date: dateOnly,
        );

        if (isExcluded) {
          // If cancelled/holiday/leave/absent, delete existing event
          if (existingEventId != null) {
            try {
              final ok = await _nativeDeleteEvent(existingEventId);
              if (!ok) {
                await plugin.deleteEvent(eventId: existingEventId);
              }
            } catch (e) {
              debugPrint('Failed to delete cancelled system event $existingEventId: $e');
            }
            await db.deleteSystemCalendarEvent(existingEventId);
          }
        } else {
          String? newEventId;
          if (existingEventId != null) {
            try {
              await plugin.updateEvent(
                eventId: existingEventId,
                title: subject.name,
                startDate: startDateTime,
                endDate: endDateTime,
                description: Patch.set('Imported from AttendMate'),
              );
              newEventId = existingEventId;
            } catch (e) {
              debugPrint('Failed to update event: $e');
            }
          } else {
            newEventId = await plugin.createEvent(
              calendarId: calendarId,
              title: subject.name,
              startDate: startDateTime,
              endDate: endDateTime,
              description: 'Imported from AttendMate',
            );
          }

          if (newEventId != null) {
            activeEventIds.add(newEventId);

            // Sync subject custom color natively
            await _nativeSetEventColor(newEventId, subject.color.value);

            // Save to SQLite
            await db.saveSystemCalendarEvent(
              eventId: newEventId,
              subjectId: subject.id,
              slotKey: slotKey,
              date: dateOnly,
            );
          }
        }

        completedEvents++;
        final progress = totalEvents > 0 ? (completedEvents / totalEvents) * 0.9 : 0.9;
        onProgress?.call(progress, 'Syncing ${subject.name} ($completedEvents/$totalEvents)...');
      }

      // Cleanup obsolete events (which were generated previously but are no longer in this run)
      final allSavedEvents = await db.getAllSystemCalendarEvents();
      final obsoleteEvents = allSavedEvents.where((e) => !activeEventIds.contains(e['eventId'] as String)).toList();

      int obsoleteDone = 0;
      for (final eventMap in obsoleteEvents) {
        final String eventId = eventMap['eventId'] as String;
        try {
          final ok = await _nativeDeleteEvent(eventId);
          if (!ok) {
            await plugin.deleteEvent(eventId: eventId);
          }
        } catch (e) {
          debugPrint('Failed to delete obsolete system event $eventId: $e');
        }
        await db.deleteSystemCalendarEvent(eventId);
        obsoleteDone++;
        final p = 0.9 + (obsoleteDone / (obsoleteEvents.isEmpty ? 1 : obsoleteEvents.length)) * 0.1;
        onProgress?.call(p, 'Cleaning obsolete events ($obsoleteDone/${obsoleteEvents.length})...');
      }

      await _nativeTriggerSync();
      onProgress?.call(1.0, 'Calendar synced successfully!');
    } catch (e) {
      debugPrint('SystemCalendarService sync error: $e');
      rethrow;
    } finally {
      _isSyncInProgress = false;
    }
  }
}

class _TimetableSyncItem {
  final Subject subject;
  final SubjectSchedule slot;
  final DateTime dateOnly;

  const _TimetableSyncItem({
    required this.subject,
    required this.slot,
    required this.dateOnly,
  });
}
