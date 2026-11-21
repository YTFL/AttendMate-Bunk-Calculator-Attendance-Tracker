import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/attendance/attendance_model.dart';
import '../features/subject/subject_model.dart' as sub;
import '../features/semester/semester_model.dart';
import 'database_service.dart';

class SystemCalendarService {
  /// Concurrency mutex to prevent parallel overlapping sync/delete cycles
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

  static Future<int> _nativeDeleteEvents(List<String> eventIds) async {
    if (eventIds.isEmpty) return 0;
    try {
      final int? count = await _nativeChannel.invokeMethod<int>('deleteEvents', {'eventIds': eventIds});
      return count ?? 0;
    } catch (e) {
      debugPrint('Native deleteEvents error: $e');
      return 0;
    }
  }

  /// Immediately deletes a single calendar event natively and via fallback
  static Future<bool> deleteEventDirectly(String eventId) async {
    bool ok = await _nativeDeleteEvent(eventId);
    if (!ok) {
      try {
        await DeviceCalendar.instance.deleteEvent(eventId: eventId);
        ok = true;
      } catch (_) {}
    }
    if (ok) {
      unawaited(_nativeTriggerSync());
    }
    return ok;
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

  static Future<void> _nativeTriggerSync([String? calendarId]) async {
    try {
      await _nativeChannel.invokeMethod('triggerCalendarSync', {'calendarId': calendarId});
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

  /// Returns a clean, user-friendly display name for a calendar account
  static String getCalendarDisplayName(Calendar cal) {
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

  /// Returns a clean account name/type label for a calendar
  static String getCalendarAccountName(Calendar cal) {
    if (cal.accountName == null || cal.accountName!.trim().isEmpty) {
      return 'Local Device';
    } else if (cal.accountName!.toLowerCase() == 'my calendar') {
      return 'Local Offline';
    } else {
      return cal.accountName!;
    }
  }

  /// Retrieves a list of writable calendars on the user's device.
  static Future<List<Calendar>> getWritableCalendars() async {
    try {
      final plugin = DeviceCalendar.instance;
      final hasPerm = await checkOrRequestPermissions();
      if (!hasPerm) return [];

      final result = await plugin.listCalendars();
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
  /// Uses a single-pass native atomic batch purge for sub-second, error-free clean-up.
  static Future<void> deleteSyncedEvents({
    bool force = false,
    String? calendarId,
    void Function(double progress, String statusMessage)? onProgress,
  }) async {
    if (_isSyncInProgress) {
      debugPrint('System Calendar delete skipped: another sync/delete operation is already in progress.');
      return;
    }
    _isSyncInProgress = true;

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

      final db = DatabaseService();
      onProgress?.call(0.15, 'Pruning calendar events...');

      // 1. Native batch prune matching AttendMate events via atomic ContentProvider operations
      final nativePruned = await _nativePruneEvents(calendarId);
      debugPrint('Native batch pruned $nativePruned AttendMate events.');

      // 2. Also delete any specifically recorded event IDs from SQLite to ensure 100% clean-up
      onProgress?.call(0.60, 'Clearing recorded events...');
      final trackedIds = await db.getAllSystemCalendarEventIds();
      if (trackedIds.isNotEmpty) {
        await _nativeDeleteEvents(trackedIds);
      }
      await db.clearSystemCalendarEvents();

      // 3. Trigger cloud sync for affected accounts
      onProgress?.call(0.85, 'Synchronizing device calendars...');
      await _nativeTriggerSync(calendarId);

      onProgress?.call(1.0, 'Calendar events cleared successfully.');
    } catch (e) {
      debugPrint('Error deleting synced system events: $e');
      rethrow;
    } finally {
      _isSyncInProgress = false;
    }
  }

  /// Deep scan and prune all events created by AttendMate across all writable device calendars.
  static Future<int> pruneAllAttendMateEvents() async {
    int prunedCount = 0;
    try {
      final hasPerm = await checkOrRequestPermissions();
      if (!hasPerm) {
        debugPrint('System Calendar prune failed: permissions not granted.');
        return 0;
      }

      // Native batch delete across all calendars via atomic ContentProvider operations
      prunedCount += await _nativePruneEvents(null);

      final db = DatabaseService();
      final trackedIds = await db.getAllSystemCalendarEventIds();
      if (trackedIds.isNotEmpty) {
        prunedCount += await _nativeDeleteEvents(trackedIds);
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

  /// Synchronizes weekly timetable schedule as recurring series (RRULE) to the chosen system calendar.
  /// Generates clean repeating weekly series instead of hundreds of detached daily single events.
  static Future<void> syncFullTimetable({
    required List<sub.Subject> subjects,
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

      final Set<String> activeEventIds = {};
      final DateTime startDate = semester.startDate;

      final totalSlots = subjects.fold<int>(0, (sum, s) => sum + s.schedule.length);
      int completedSlots = 0;
      onProgress?.call(0.05, 'Preparing class schedules...');

      for (final subject in subjects) {
        final subjectTitle = (subject.acronym != null && subject.acronym!.trim().isNotEmpty)
            ? '${subject.name} (${subject.acronym!.trim()})'
            : subject.name;

        for (final slot in subject.schedule) {
          final isOneOff = slot.specificDate != null;

          // Find anchor date (first date on or after startDate matching slot weekday)
          final targetWeekday = slot.day.index + 1; // 1 (Mon) - 7 (Sun)
          DateTime anchorDate;

          if (isOneOff) {
            anchorDate = slot.specificDate!;

            // Check if one-off class date is a holiday or cancelled
            final isDayHoliday = isHoliday(anchorDate);
            bool isSlotCancelled = false;
            for (final record in subject.attendanceRecords) {
              if (record.date.year == anchorDate.year &&
                  record.date.month == anchorDate.month &&
                  record.date.day == anchorDate.day &&
                  (record.slotKey == null || record.slotKey == slot.slotKey || record.slotKey!.isEmpty) &&
                  record.status == AttendanceStatus.cancelled) {
                isSlotCancelled = true;
                break;
              }
            }

            if (isDayHoliday || isSlotCancelled) {
              final existingEventId = await db.getSystemCalendarEvent(
                subjectId: subject.id,
                slotKey: slot.slotKey,
              );
              if (existingEventId != null) {
                await deleteEventDirectly(existingEventId);
                await db.deleteSystemCalendarEvent(existingEventId);
              }
              continue;
            }
          } else {
            DateTime testDate = startDate;
            if (slot.effectiveFrom != null && slot.effectiveFrom!.isAfter(testDate)) {
              testDate = slot.effectiveFrom!;
            }
            while (testDate.weekday != targetWeekday) {
              testDate = testDate.add(const Duration(days: 1));
            }
            anchorDate = testDate;
          }

          // Effective until date
          DateTime untilDate = semester.endDate;
          if (slot.effectiveUntil != null && slot.effectiveUntil!.isBefore(untilDate)) {
            untilDate = slot.effectiveUntil!;
          }

          // Boundary guard: if anchor date is already beyond untilDate, slot does not occur
          if (anchorDate.isAfter(untilDate)) {
            continue;
          }

          final startDateTime = DateTime(
            anchorDate.year,
            anchorDate.month,
            anchorDate.day,
            slot.startTime.hour,
            slot.startTime.minute,
          );
          final endDateTime = DateTime(
            anchorDate.year,
            anchorDate.month,
            anchorDate.day,
            slot.endTime.hour,
            slot.endTime.minute,
          );

          // Build room/block location string
          final effectiveRoom = subject.getEffectiveRoom(slot);
          final effectiveBlock = subject.getEffectiveBlock(slot);
          final locationStr = effectiveRoom != null
              ? '$effectiveRoom${effectiveBlock != null && effectiveBlock.isNotEmpty ? ' ($effectiveBlock)' : ''}'
              : null;

          final recurrence = isOneOff
              ? null
              : WeeklyRecurrence(
                  daysOfWeek: [DayOfWeek.values[slot.day.index]],
                  end: UntilEnd(untilDate),
                );

          final String slotKey = slot.slotKey;
          final existingEventId = await db.getSystemCalendarEvent(
            subjectId: subject.id,
            slotKey: slotKey,
          );

          String? targetEventId = existingEventId;
          if (existingEventId != null) {
            final existing = await plugin.getEvent(existingEventId);
            if (existing != null && existing.calendarId == calendarId) {
              try {
                await plugin.updateEvent(
                  eventId: existingEventId,
                  title: subjectTitle,
                  startDate: startDateTime,
                  endDate: endDateTime,
                  description: Patch.set('Imported from AttendMate'),
                  location: locationStr != null ? Patch.set(locationStr) : const Patch.clear(),
                );
                await _nativeSetEventColor(existingEventId, subject.color.toARGB32());
                activeEventIds.add(existingEventId);
              } catch (e) {
                debugPrint('Failed to update event: $e');
                targetEventId = null;
              }
            } else {
              if (existing != null && existing.calendarId != calendarId) {
                await deleteEventDirectly(existingEventId);
              }
              targetEventId = null;
            }
          }

          if (targetEventId == null) {
            if (existingEventId != null) {
              await deleteEventDirectly(existingEventId);
            }
            final newEventId = await plugin.createEvent(
              calendarId: calendarId,
              title: subjectTitle,
              startDate: startDateTime,
              endDate: endDateTime,
              description: 'Imported from AttendMate',
              location: locationStr,
              recurrenceRule: recurrence,
            );

            if (newEventId.isNotEmpty) {
              activeEventIds.add(newEventId);
              await _nativeSetEventColor(newEventId, subject.color.toARGB32());
              await db.saveSystemCalendarEvent(
                eventId: newEventId,
                subjectId: subject.id,
                slotKey: slotKey,
                date: anchorDate,
              );
            }
          }

          completedSlots++;
          final progress = totalSlots > 0 ? (completedSlots / totalSlots) * 0.9 : 0.9;
          onProgress?.call(progress, 'Syncing ${subject.name} ($completedSlots/$totalSlots)...');
        }
      }

      // Cleanup obsolete events (which were generated previously but are no longer in this schedule)
      final allSavedEvents = await db.getAllSystemCalendarEvents();
      final obsoleteEvents = allSavedEvents.where((e) => !activeEventIds.contains(e['eventId'] as String)).toList();

      if (obsoleteEvents.isNotEmpty) {
        final obsoleteIds = obsoleteEvents
            .map((e) => e['eventId'] as String)
            .where((id) => id.isNotEmpty)
            .toList();

        onProgress?.call(0.92, 'Cleaning obsolete events (${obsoleteIds.length})...');
        await _nativeDeleteEvents(obsoleteIds);
        for (final evId in obsoleteIds) {
          await db.deleteSystemCalendarEvent(evId);
        }
      }

      await _nativeTriggerSync(calendarId);
      onProgress?.call(1.0, 'Calendar synced successfully!');
    } catch (e) {
      debugPrint('SystemCalendarService sync error: $e');
      rethrow;
    } finally {
      _isSyncInProgress = false;
    }
  }
}
