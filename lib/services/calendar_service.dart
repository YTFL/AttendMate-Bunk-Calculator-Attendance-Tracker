import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import '../features/subject/subject_model.dart';
import '../features/semester/semester_model.dart';
import '../features/attendance/attendance_model.dart';
import 'database_service.dart';
import 'google_auth_service.dart';

class CalendarService {
  static GoogleSignIn get _googleSignIn => GoogleAuthService.instance.googleSignIn;

  /// Global synchronization mutex to prevent concurrent overlapping sync cycles
  static bool _isSyncInProgress = false;

  /// Map of Google Calendar event color IDs (1-11) to their RGB values
  static const Map<String, Color> _googleCalendarColors = {
    '1': Color(0xFFa4bdfc),  // Lavender
    '2': Color(0xFF7ae7bf),  // Sage
    '3': Color(0xFFdbadff),  // Grape
    '4': Color(0xFFff887c),  // Flamingo
    '5': Color(0xFFfbd75b),  // Banana
    '6': Color(0xFFffb878),  // Tangerine
    '7': Color(0xFF46d6db),  // Peacock
    '8': Color(0xFFe1e1e1),  // Graphite
    '9': Color(0xFF5484ed),  // Blueberry
    '10': Color(0xFF51b749), // Basil
    '11': Color(0xFFdc2127), // Tomato
  };

  /// Helper to map any Flutter Color to the nearest Google Calendar event color ID (1-11)
  static String _getNearestGoogleColorId(Color targetColor) {
    double minDistance = double.infinity;
    String nearestId = '1';

    _googleCalendarColors.forEach((id, color) {
      final double rDiff = targetColor.r - color.r;
      final double gDiff = targetColor.g - color.g;
      final double bDiff = targetColor.b - color.b;
      final double distance = rDiff * rDiff + gDiff * gDiff + bDiff * bDiff;

      if (distance < minDistance) {
        minDistance = distance;
        nearestId = id;
      }
    });

    return nearestId;
  }

  static String _getBaseSubjectName(String name) {
    String normalized = name.toLowerCase().trim();
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\b(lab|practical|tutorial|pract|tut|l|p|t)\b', caseSensitive: false), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// 64-bit FNV-1a deterministic content hashing algorithm.
  /// Generates a fast 16-character hex hash to detect whether a slot's calendar representation has changed.
  static String _computeSlotHash(String rawContent) {
    BigInt hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final BigInt fnvPrime = BigInt.parse('100000001b3', radix: 16);
    final BigInt mask = BigInt.parse('ffffffffffffffff', radix: 16);
    for (int i = 0; i < rawContent.length; i++) {
      hash = (hash ^ BigInt.from(rawContent.codeUnitAt(i))) * fnvPrime & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Checks if the user is currently signed in
  static Future<bool> isUserSignedIn() async {
    return await GoogleAuthService.instance.isSignedIn();
  }

  /// Preference key for Google Calendar sync toggle
  static const String prefGoogleCalendarSyncEnabledKey = 'google_calendar_sync_enabled';

  static bool? _cachedIsSyncEnabled;
  /// Fast synchronous getter for in-memory cached state
  static bool get isGoogleCalendarSyncEnabledSync => _cachedIsSyncEnabled ?? false;

  /// Checks if Google Calendar synchronization is explicitly enabled by the user.
  /// Defaults to false so logging in for Google Drive backup does NOT silently enable calendar sync.
  static Future<bool> isGoogleCalendarSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getBool(prefGoogleCalendarSyncEnabledKey) ?? false;
    _cachedIsSyncEnabled = val;
    return val;
  }

  /// Sets Google Calendar synchronization preference
  static Future<void> setGoogleCalendarSyncEnabled(bool enabled) async {
    _cachedIsSyncEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefGoogleCalendarSyncEnabledKey, enabled);
  }

  /// Get the current signed-in user's email
  static Future<String?> getSignedInUserEmail() async {
    return await GoogleAuthService.instance.getSignedInUserEmail();
  }

  /// Sign out from Google Account
  static Future<void> signOut() async {
    await GoogleAuthService.instance.signOut();
  }

  /// Verification predicate for AttendMate events
  static bool _isStrictAttendMateEvent(cal.Event event) {
    final iCalUID = event.iCalUID?.toLowerCase() ?? '';
    final desc = event.description?.toLowerCase() ?? '';

    // RFC 5545 UID schema stamped exclusively by AttendMate
    if (iCalUID.startsWith('sched_') && iCalUID.endsWith('@attendmate.app')) {
      return true;
    }

    // Explicit metadata tag stamped exclusively by AttendMate
    if (desc.contains('imported from attendmate') || desc.contains('created with attendmate')) {
      return true;
    }

    return false;
  }

  /// Deletes all events synced by AttendMate from Google Calendar and purges SQLite tracking.
  static Future<void> deleteAllSyncedEvents(Semester? semester, {bool force = false}) async {
    try {
      if (kDebugMode && !force) {
        final prefs = await SharedPreferences.getInstance();
        final isDevSyncEnabled = prefs.getBool('dev_mode_calendar_sync_enabled') ?? false;
        if (!isDevSyncEnabled) {
          debugPrint('Google Calendar deleteAllSyncedEvents bypassed in debug mode (disabled under Developer Options).');
          return;
        }
      }
      GoogleSignInAccount? googleUser = _googleSignIn.currentUser;
      googleUser ??= await _googleSignIn.signInSilently();
      if (googleUser == null) return;

      final httpClient = (await _googleSignIn.authenticatedClient())!;
      final calendarApi = cal.CalendarApi(httpClient);
      final db = DatabaseService();

      // 1. Delete all tracked events in local database
      final cachedEvents = await db.getAllGoogleCalendarEvents();
      final Set<String> deletedIds = {};
      for (final eventMap in cachedEvents) {
        final eventId = eventMap['googleEventId'] as String;
        try {
          await calendarApi.events.delete("primary", eventId);
          deletedIds.add(eventId);
        } catch (e) {
          debugPrint("Failed to delete tracked Google event $eventId: $e");
        }
      }
      await db.clearGoogleCalendarEvents();

      // 2. Comprehensive Paged Prune: Search Google Calendar for any remaining AttendMate events
      // (Handles events created across any date range without semester boundary constraints)
      String? pageToken;
      do {
        final cal.Events searchEvents = await calendarApi.events.list(
          "primary",
          q: "Imported from AttendMate",
          maxResults: 250,
          pageToken: pageToken,
        );
        for (final event in searchEvents.items ?? <cal.Event>[]) {
          final eventId = event.id;
          if (eventId != null && !deletedIds.contains(eventId)) {
            if (_isStrictAttendMateEvent(event)) {
              try {
                await calendarApi.events.delete("primary", eventId);
                deletedIds.add(eventId);
              } catch (e) {
                debugPrint('Error deleting event $eventId: $e');
              }
            }
          }
        }
        pageToken = searchEvents.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);

    } catch (e) {
      debugPrint("Failed to clear Google Calendar events: $e");
    }
  }

  /// Deep scan and prune all events created by AttendMate across the primary Google Calendar.
  static Future<int> pruneAllAttendMateEvents() async {
    int prunedCount = 0;
    try {
      GoogleSignInAccount? googleUser = _googleSignIn.currentUser;
      googleUser ??= await _googleSignIn.signInSilently();
      if (googleUser == null) {
        debugPrint('Google Calendar prune skipped: user not signed in.');
        return 0;
      }

      final httpClient = (await _googleSignIn.authenticatedClient())!;
      final calendarApi = cal.CalendarApi(httpClient);
      final Set<String> deletedIds = {};

      // 1. Paged search by query: "Imported from AttendMate"
      String? pageToken;
      do {
        final cal.Events searchEvents = await calendarApi.events.list(
          "primary",
          q: "Imported from AttendMate",
          maxResults: 250,
          pageToken: pageToken,
        );
        for (final event in searchEvents.items ?? <cal.Event>[]) {
          final eventId = event.id;
          if (eventId != null && !deletedIds.contains(eventId)) {
            if (_isStrictAttendMateEvent(event)) {
              try {
                await calendarApi.events.delete("primary", eventId);
                deletedIds.add(eventId);
                prunedCount++;
              } catch (e) {
                debugPrint('Error deleting event $eventId: $e');
              }
            }
          }
        }
        pageToken = searchEvents.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);

      // 2. Wide date-range scan (last 2 years to next 2 years) to catch recurring events and tombstones
      final now = DateTime.now();
      final timeMin = now.subtract(const Duration(days: 730)).toUtc();
      final timeMax = now.add(const Duration(days: 730)).toUtc();
      pageToken = null;
      do {
        final cal.Events windowEvents = await calendarApi.events.list(
          "primary",
          timeMin: timeMin,
          timeMax: timeMax,
          maxResults: 250,
          pageToken: pageToken,
          singleEvents: false,
        );
        for (final event in windowEvents.items ?? <cal.Event>[]) {
          final eventId = event.id;
          if (eventId == null || deletedIds.contains(eventId)) continue;

          if (_isStrictAttendMateEvent(event)) {
            try {
              await calendarApi.events.delete("primary", eventId);
              deletedIds.add(eventId);
              prunedCount++;
            } catch (e) {
              debugPrint('Error deleting event $eventId: $e');
            }
          }
        }
        pageToken = windowEvents.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);

      // Clear local database tracking
      await DatabaseService().clearGoogleCalendarEvents();
      debugPrint('Google Calendar prune complete: safely deleted $prunedCount AttendMate events.');
    } catch (e) {
      debugPrint("Error pruning Google Calendar events: $e");
      rethrow;
    }
    return prunedCount;
  }

  /// Synchronizes all subjects and their timeslots to Google Calendar.
  /// Uses local SQLite state tracking and content hashing for differential synchronization.
  /// Unchanged slots make 0 API requests; modified slots make exactly 1 API request.
  static Future<void> syncFullTimetable({
    required List<Subject> subjects,
    required Semester? semester,
    required bool Function(DateTime) isHoliday,
  }) async {
    if (_isSyncInProgress) {
      debugPrint('Google Calendar sync skipped: another sync cycle is already in progress.');
      return;
    }
    _isSyncInProgress = true;

    try {
      if (kDebugMode) {
        final prefs = await SharedPreferences.getInstance();
        final isDevSyncEnabled = prefs.getBool('dev_mode_calendar_sync_enabled') ?? false;
        if (!isDevSyncEnabled) {
          debugPrint('Google Calendar Sync bypassed in debug mode (disabled under Developer Options).');
          return;
        }
      }

      // 1. Google Account Session
      GoogleSignInAccount? googleUser = _googleSignIn.currentUser;
      googleUser ??= await _googleSignIn.signInSilently();
      googleUser ??= await _googleSignIn.signIn();

      if (googleUser == null) {
        throw Exception("User cancelled Google login.");
      }

      if (semester == null || subjects.isEmpty) {
        return;
      }

      final db = DatabaseService();
      final plannedLeaves = await db.loadPlannedLeaves();

      // Wrap the authorized user session
      final httpClient = (await _googleSignIn.authenticatedClient())!;
      final calendarApi = cal.CalendarApi(httpClient);

      // Load cached Google Calendar event records from SQLite
      final cachedEventsList = await db.getAllGoogleCalendarEvents();
      final Map<String, Map<String, dynamic>> cachedMap = {
        for (final row in cachedEventsList)
          "${row['subjectId']}_${row['slotKey']}": row,
      };

      final Set<String> activeKeys = {};
      final Set<String> activeICalIds = {};

      // 2. Map colors for subjects using linear probing and base name matching
      final Map<String, String> baseNameToColorId = {};
      final Set<String> occupiedColorIds = {};

      for (final subject in subjects) {
        final String baseName = _getBaseSubjectName(subject.name);
        if (baseNameToColorId.containsKey(baseName)) {
          continue;
        }

        final String nearestId = _getNearestGoogleColorId(subject.color);
        if (!occupiedColorIds.contains(nearestId)) {
          baseNameToColorId[baseName] = nearestId;
          occupiedColorIds.add(nearestId);
        } else {
          final int startIndex = int.parse(nearestId);
          String assignedId = nearestId;
          for (int i = 0; i < 11; i++) {
            final int probedInt = ((startIndex - 1 + i) % 11) + 1;
            final String probedId = probedInt.toString();
            if (!occupiedColorIds.contains(probedId)) {
              assignedId = probedId;
              occupiedColorIds.add(probedId);
              break;
            }
          }
          baseNameToColorId[baseName] = assignedId;
        }
      }

      // 3. Sync each subject's schedule
      for (final subject in subjects) {
        final String baseName = _getBaseSubjectName(subject.name);
        final String colorId = baseNameToColorId[baseName] ?? _getNearestGoogleColorId(subject.color);

        for (final slot in subject.schedule) {
          DateTime startDateTime;
          DateTime endDateTime;
          DateTime untilDate = semester.endDate;

          if (slot.isSpecialClass) {
            final date = slot.specificDate!;
            final occStart = DateTime(date.year, date.month, date.day, slot.startTime.hour, slot.startTime.minute);
            final occEnd = DateTime(date.year, date.month, date.day, slot.endTime.hour, slot.endTime.minute);

            bool isExcluded = isHoliday(date);
            if (!isExcluded) {
              for (final leave in plannedLeaves) {
                if (leave.affectedSubjectIds.isEmpty || leave.affectedSubjectIds.contains(subject.id)) {
                  if (occStart.isBefore(leave.endDate) && occEnd.isAfter(leave.startDate)) {
                    isExcluded = true;
                    break;
                  }
                }
              }
            }
            for (final record in subject.attendanceRecords) {
              if (_isSameDay(record.date, date) && (record.slotKey == null || record.slotKey == slot.slotKey || record.slotKey!.isEmpty)) {
                if (record.status == AttendanceStatus.cancelled || record.status == AttendanceStatus.absent) {
                  isExcluded = true;
                } else if (record.status == AttendanceStatus.attended) {
                  isExcluded = false;
                }
                break;
              }
            }

            if (isExcluded) {
              // Excluded one-time event; do not import
              continue;
            }

            startDateTime = occStart;
            endDateTime = occEnd;
            untilDate = date;
          } else {
            // Regular weekly slot
            DateTime calcStart = semester.startDate;
            if (slot.effectiveFrom != null && slot.effectiveFrom!.isAfter(calcStart)) {
              calcStart = slot.effectiveFrom!;
            }
            int daysToAdd = (slot.day.index + 1 - calcStart.weekday + 7) % 7;
            DateTime firstDate = calcStart.add(Duration(days: daysToAdd));

            startDateTime = DateTime(firstDate.year, firstDate.month, firstDate.day, slot.startTime.hour, slot.startTime.minute);
            endDateTime = DateTime(firstDate.year, firstDate.month, firstDate.day, slot.endTime.hour, slot.endTime.minute);

            if (slot.effectiveUntil != null && slot.effectiveUntil!.isBefore(untilDate)) {
              untilDate = slot.effectiveUntil!;
            }
          }

          // Format clean unique RFC 5545 UID
          final String slotKeyId = slot.slotKey.replaceAll(':', '_').replaceAll('-', '_');
          final String uniqueICalId = "sched_${subject.id}_slot_$slotKeyId@attendmate.app".toLowerCase();
          final String mappingKey = "${subject.id}_${slot.slotKey}";
          activeKeys.add(mappingKey);
          activeICalIds.add(uniqueICalId);

          // 4. Construct RRULE and EXDATE exceptions for weekly events
          List<String>? recurrenceRule;
          if (!slot.isSpecialClass) {
            // Ensure until covers the full last day (23:59:59) so classes on the semester end date are included
            final untilInclusive = DateTime(untilDate.year, untilDate.month, untilDate.day, 23, 59, 59);
            final String untilFormatted = "${untilInclusive.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z";
            recurrenceRule = ["RRULE:FREQ=WEEKLY;UNTIL=$untilFormatted"];

            DateTime currentDate = DateTime(startDateTime.year, startDateTime.month, startDateTime.day);
            final DateTime checkUntil = DateTime(untilDate.year, untilDate.month, untilDate.day);

            while (currentDate.isBefore(checkUntil) || _isSameDay(currentDate, checkUntil)) {
              final occStart = DateTime(currentDate.year, currentDate.month, currentDate.day, slot.startTime.hour, slot.startTime.minute);
              final occEnd = DateTime(currentDate.year, currentDate.month, currentDate.day, slot.endTime.hour, slot.endTime.minute);

              bool isExcluded = isHoliday(currentDate);
              if (!isExcluded) {
                for (final leave in plannedLeaves) {
                  if (leave.affectedSubjectIds.isEmpty || leave.affectedSubjectIds.contains(subject.id)) {
                    if (occStart.isBefore(leave.endDate) && occEnd.isAfter(leave.startDate)) {
                      isExcluded = true;
                      break;
                    }
                  }
                }
              }
              for (final record in subject.attendanceRecords) {
                if (_isSameDay(record.date, currentDate) && (record.slotKey == null || record.slotKey == slot.slotKey || record.slotKey!.isEmpty)) {
                  if (record.status == AttendanceStatus.cancelled || record.status == AttendanceStatus.absent) {
                    isExcluded = true;
                  } else if (record.status == AttendanceStatus.attended) {
                    isExcluded = false;
                  }
                  break;
                }
              }

              if (isExcluded) {
                final occurrenceUtcStart = occStart.toUtc();
                final exdateStr = "${occurrenceUtcStart.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z";
                recurrenceRule.add("EXDATE:$exdateStr");
              }

              currentDate = currentDate.add(const Duration(days: 7));
            }
          }

          final room = subject.getEffectiveRoom(slot);
          final block = subject.getEffectiveBlock(slot);
          final locationStr = room != null ? '$room${block != null && block.isNotEmpty ? ' ($block)' : ''}' : null;
          final summaryStr = "${subject.name} ${subject.acronym != null ? '(${subject.acronym})' : ''}".trim();

          // 5. Compute deterministic slot content hash
          final rawContentSignature = [
            summaryStr,
            colorId,
            startDateTime.toUtc().toIso8601String(),
            endDateTime.toUtc().toIso8601String(),
            locationStr ?? '',
            subject.targetAttendance.toString(),
            if (recurrenceRule != null) ...recurrenceRule,
          ].join('||');
          final currentHash = _computeSlotHash(rawContentSignature);

          // Check cached record
          final cachedRow = cachedMap[mappingKey];
          if (cachedRow != null && cachedRow['contentHash'] == currentHash) {
            // Unchanged: Skip entirely. 0 API requests made.
            continue;
          }

          // Build Google Calendar Event resource
          final cal.Event eventPayload = cal.Event()
            ..iCalUID = uniqueICalId
            ..summary = summaryStr
            ..description = "Imported from AttendMate. Re-importing updates this specific schedule.\nTarget attendance: ${subject.targetAttendance}%."
            ..colorId = colorId
            ..start = (cal.EventDateTime()..dateTime = startDateTime.toUtc()..timeZone = "UTC")
            ..end = (cal.EventDateTime()..dateTime = endDateTime.toUtc()..timeZone = "UTC")
            ..recurrence = recurrenceRule;

          if (locationStr != null) {
            eventPayload.location = locationStr;
          }

          // 6. Execute differential update / upsert
          String? resolvedEventId = cachedRow?['googleEventId'] as String?;

          if (resolvedEventId != null) {
            try {
              // Direct update to existing Google event ID: Exactly 1 API call
              eventPayload.status = "confirmed";
              await calendarApi.events.update(eventPayload, "primary", resolvedEventId);
              await db.saveGoogleCalendarEvent(
                subjectId: subject.id,
                slotKey: slot.slotKey,
                googleEventId: resolvedEventId,
                contentHash: currentHash,
              );
              continue;
            } catch (e) {
              debugPrint('Direct update failed for $resolvedEventId, falling back to lookup: $e');
              resolvedEventId = null;
            }
          }

          // If not cached or update failed (e.g. event deleted on Google web):
          // Perform idempotent upsert by iCalUID
          final listResult = await calendarApi.events.list(
            "primary",
            iCalUID: uniqueICalId,
            showDeleted: true,
          );

          final existingItems = listResult.items ?? [];
          if (existingItems.isNotEmpty) {
            final existingEvent = existingItems.first;
            final existingId = existingEvent.id!;
            eventPayload.status = "confirmed";
            await calendarApi.events.update(eventPayload, "primary", existingId);
            await db.saveGoogleCalendarEvent(
              subjectId: subject.id,
              slotKey: slot.slotKey,
              googleEventId: existingId,
              contentHash: currentHash,
            );
          } else {
            // Fresh import: 1 API call
            final importedEvent = await calendarApi.events.import(eventPayload, "primary");
            if (importedEvent.id != null) {
              await db.saveGoogleCalendarEvent(
                subjectId: subject.id,
                slotKey: slot.slotKey,
                googleEventId: importedEvent.id!,
                contentHash: currentHash,
              );
            }
          }
        }
      }

      // 7. Clean up deleted classes
      // 7A: Remove slots that were previously tracked but are no longer active in the timetable
      for (final cached in cachedEventsList) {
        final key = "${cached['subjectId']}_${cached['slotKey']}";
        if (!activeKeys.contains(key)) {
          final eventId = cached['googleEventId'] as String;
          try {
            await calendarApi.events.delete("primary", eventId);
          } catch (e) {
            debugPrint("Failed to delete removed slot event $eventId: $e");
          }
          await db.deleteGoogleCalendarEvent(
            subjectId: cached['subjectId'] as String,
            slotKey: cached['slotKey'] as String,
          );
        }
      }

      // 7B: Safety-net paged cleanup across Google Calendar for any untracked or legacy orphaned AttendMate events
      String? pageToken;
      do {
        final cal.Events existingEvents = await calendarApi.events.list(
          "primary",
          q: "Imported from AttendMate",
          maxResults: 250,
          pageToken: pageToken,
        );

        for (final event in existingEvents.items ?? <cal.Event>[]) {
          final iCalUID = event.iCalUID?.toLowerCase();
          if (iCalUID != null && iCalUID.startsWith("sched_") && iCalUID.endsWith("@attendmate.app")) {
            if (!activeICalIds.contains(iCalUID)) {
              final eventId = event.id;
              if (eventId != null) {
                try {
                  await calendarApi.events.delete("primary", eventId);
                } catch (e) {
                  debugPrint("Failed to delete orphaned Google event $eventId: $e");
                }
              }
            }
          }
        }
        pageToken = existingEvents.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);

    } catch (e) {
      rethrow;
    } finally {
      _isSyncInProgress = false;
    }
  }
}
