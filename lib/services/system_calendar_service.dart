import 'package:flutter/material.dart';
import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/subject/subject_model.dart';
import '../features/semester/semester_model.dart';
import '../features/attendance/attendance_model.dart';
import 'database_service.dart';

class SystemCalendarService {
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
      // Return only writable calendars, and exclude holiday/special read-only system feeds
      return result.where((cal) {
        if (cal.readOnly == true) return false;
        final name = cal.name.toLowerCase();
        if (name.contains('holidays in')) return false;
        return true;
      }).toList();
    } catch (e) {
      debugPrint('Error retrieving calendars: $e');
    }
    return [];
  }

  /// Sets system calendar synchronization preferences in SharedPreferences.
  static Future<void> setSystemSyncEnabled(bool enabled, {String? calendarId, String? calendarName}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('system_calendar_sync_enabled', enabled);
    if (enabled && calendarId != null && calendarName != null) {
      await prefs.setString('system_calendar_id', calendarId);
      await prefs.setString('system_calendar_name', calendarName);
    } else if (!enabled) {
      await prefs.remove('system_calendar_id');
      await prefs.remove('system_calendar_name');
    }
  }

  /// Checks if system calendar synchronization is enabled.
  static Future<bool> isSystemSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('system_calendar_sync_enabled') ?? false;
  }

  /// Retrieves the selected system calendar's ID.
  static Future<String?> getSystemCalendarId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('system_calendar_id');
  }

  /// Retrieves the selected system calendar's display name.
  static Future<String?> getSystemCalendarName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('system_calendar_name');
  }

  /// Deletes all events synced by AttendMate from the system calendar and purges SQLite mappings.
  static Future<void> deleteSyncedEvents() async {
    try {
      final plugin = DeviceCalendar.instance;
      final db = DatabaseService();
      final events = await db.getAllSystemCalendarEvents();

      for (final eventMap in events) {
        final String eventId = eventMap['eventId'] as String;
        try {
          await plugin.deleteEvent(eventId: eventId);
        } catch (e) {
          debugPrint('Failed to delete system event $eventId: $e');
        }
      }

      await db.clearSystemCalendarEvents();
    } catch (e) {
      debugPrint('Error deleting synced system events: $e');
    }
  }

  /// Declaratively synchronizes subjects, slots, holidays, and cancellations to the chosen system calendar.
  static Future<void> syncFullTimetable({
    required List<Subject> subjects,
    required Semester? semester,
    required bool Function(DateTime) isHoliday,
  }) async {
    try {
      if (semester == null || subjects.isEmpty) return;

      final calendarId = await getSystemCalendarId();
      final enabled = await isSystemSyncEnabled();
      if (!enabled || calendarId == null) return;

      final plugin = DeviceCalendar.instance;
      final db = DatabaseService();

      // Track active event IDs in this run
      final Set<String> activeEventIds = {};

      // Calculate start and end dates
      final DateTime startDate = semester.startDate;
      final DateTime endDate = semester.endDate;

      for (final subject in subjects) {
        for (final slot in subject.schedule) {
          // Determine the weekday integer (1 for Monday, 7 for Sunday in DateTime)
          // In our app, DayOfWeek starts at 0 (Monday) to 6 (Sunday)
          final targetWeekday = slot.day.index + 1; // weekday in DateTime is 1-7

          // Generate all dates for this slot's weekday within the semester dates
          DateTime currentDate = startDate;
          while (!currentDate.isAfter(endDate)) {
            if (currentDate.weekday == targetWeekday) {
              final dateOnly = DateTime(currentDate.year, currentDate.month, currentDate.day);

              // Check if date falls in slot's effective dates range
              final slotFrom = slot.effectiveFrom;
              final slotUntil = slot.effectiveUntil;

              bool withinValidity = true;
              if (slotFrom != null && dateOnly.isBefore(DateTime(slotFrom.year, slotFrom.month, slotFrom.day))) {
                withinValidity = false;
              }
              if (slotUntil != null && dateOnly.isAfter(DateTime(slotUntil.year, slotUntil.month, dateOnly.day))) {
                withinValidity = false;
              }

              if (withinValidity) {
                // Check if this slot key has a cancellation or is marked holiday
                final isDayHoliday = isHoliday(dateOnly);
                bool isSlotCancelled = false;
                for (final record in subject.attendanceRecords) {
                  if (record.date.year == dateOnly.year &&
                      record.date.month == dateOnly.month &&
                      record.date.day == dateOnly.day &&
                      record.slotKey == slot.slotKey &&
                      record.status == AttendanceStatus.cancelled) {
                    isSlotCancelled = true;
                    break;
                  }
                }

                final String slotKey = slot.slotKey;
                final existingEventId = await db.getSystemCalendarEvent(
                  subjectId: subject.id,
                  slotKey: slotKey,
                  date: dateOnly,
                );

                if (isDayHoliday || isSlotCancelled) {
                  // If it's cancelled/holiday, delete the event if it exists
                  if (existingEventId != null) {
                    try {
                      await plugin.deleteEvent(eventId: existingEventId);
                    } catch (e) {
                      debugPrint('Failed to delete cancelled system event $existingEventId: $e');
                    }
                    await db.deleteSystemCalendarEvent(existingEventId);
                  }
                } else {
                  // Create/Update the event
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

                    // Save to SQLite
                    await db.saveSystemCalendarEvent(
                      eventId: newEventId,
                      subjectId: subject.id,
                      slotKey: slotKey,
                      date: dateOnly,
                    );
                  }
                }
              }
            }
            currentDate = currentDate.add(const Duration(days: 1));
          }
        }
      }

      // Cleanup obsolete events (which were generated previously but are no longer in this run)
      final allSavedEvents = await db.getAllSystemCalendarEvents();
      for (final eventMap in allSavedEvents) {
        final String eventId = eventMap['eventId'] as String;
        if (!activeEventIds.contains(eventId)) {
          try {
            await plugin.deleteEvent(eventId: eventId);
          } catch (e) {
            debugPrint('Failed to delete obsolete system event $eventId: $e');
          }
          await db.deleteSystemCalendarEvent(eventId);
        }
      }
    } catch (e) {
      debugPrint('SystemCalendarService sync error: $e');
      rethrow;
    }
  }
}
