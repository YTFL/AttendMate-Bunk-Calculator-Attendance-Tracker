import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import '../features/subject/subject_model.dart';
import '../features/semester/semester_model.dart';
import '../features/attendance/attendance_model.dart';

class CalendarService {
  static const MethodChannel _buildConfigChannel = MethodChannel('com.attendmate.app/build_config');
  static GoogleSignIn? _googleSignIn;

  static Future<GoogleSignIn> _getGoogleSignIn() async {
    final existing = _googleSignIn;
    if (existing != null) {
      return existing;
    }

    String? clientId;
    try {
      clientId = await _buildConfigChannel.invokeMethod<String>('getGoogleClientId');
    } catch (_) {
      clientId = null;
    }

    final instance = GoogleSignIn(
      scopes: [cal.CalendarApi.calendarEventsScope],
      serverClientId: clientId,
    );
    _googleSignIn = instance;
    return instance;
  }

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
    // Normalizes name by converting to lowercase, removing non-alphanumeric chars,
    // and stripping common "lab", "practical", "tutorial", "pract", "tut" keywords/suffixes.
    String normalized = name.toLowerCase().trim();
    
    // Replace punctuation/delimiters with space to isolate words
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    
    // Remove standalone words like lab, tutorial, practical, tut, pract, l, p, t
    normalized = normalized.replaceAll(RegExp(r'\b(lab|practical|tutorial|pract|tut|l|p|t)\b', caseSensitive: false), ' ');
    
    // Normalize spaces
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    return normalized;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Checks if the user is currently signed in
  static Future<bool> isUserSignedIn() async {
    final googleSignIn = await _getGoogleSignIn();
    return await googleSignIn.isSignedIn();
  }

  /// Get the current signed-in user's email
  static Future<String?> getSignedInUserEmail() async {
    final googleSignIn = await _getGoogleSignIn();
    final account = googleSignIn.currentUser ?? await googleSignIn.signInSilently();
    return account?.email;
  }

  /// Sign out from Google Account
  static Future<void> signOut() async {
    final googleSignIn = await _getGoogleSignIn();
    await googleSignIn.signOut();
  }

  /// Synchronizes all subjects and their timeslots to Google Calendar
  static Future<void> syncFullTimetable({
    required List<Subject> subjects,
    required Semester? semester,
    required bool Function(DateTime) isHoliday,
  }) async {
    try {
      final googleSignIn = await _getGoogleSignIn();

      // 1. Trigger Google login popup
      GoogleSignInAccount? googleUser = googleSignIn.currentUser;
      googleUser ??= await googleSignIn.signInSilently();
      googleUser ??= await googleSignIn.signIn();
      
      if (googleUser == null) {
        throw Exception("User cancelled the Google login.");
      }

      if (semester == null || subjects.isEmpty) {
        return;
      }

      // 2. Wrap the authorized user session
      final httpClient = (await googleSignIn.authenticatedClient())!;
      final calendarApi = cal.CalendarApi(httpClient);

      // Track active iCalUIDs to determine what to keep
      final Set<String> activeICalIds = {};

      // 3. Map colors for subjects using linear probing and base name matching
      final Map<String, String> baseNameToColorId = {};
      final Set<String> occupiedColorIds = {};

      for (final subject in subjects) {
        final String baseName = _getBaseSubjectName(subject.name);
        if (baseNameToColorId.containsKey(baseName)) {
          continue; // Already mapped (e.g. Lab matching its parent subject)
        }

        final String nearestId = _getNearestGoogleColorId(subject.color);
        if (!occupiedColorIds.contains(nearestId)) {
          baseNameToColorId[baseName] = nearestId;
          occupiedColorIds.add(nearestId);
        } else {
          // Linear probing: search starting from nearestId
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

      // 4. Sync each subject's schedule
      for (final subject in subjects) {
        final String baseName = _getBaseSubjectName(subject.name);
        final String colorId = baseNameToColorId[baseName] ?? _getNearestGoogleColorId(subject.color);

        for (final slot in subject.schedule) {
          DateTime startDateTime;
          DateTime endDateTime;
          DateTime untilDate = semester.endDate;

          if (slot.isSpecialClass) {
            final date = slot.specificDate!;
            
            // Check if special class is a holiday or specifically cancelled
            final isDayHoliday = isHoliday(date);
            bool isSlotCancelled = false;
            for (final record in subject.attendanceRecords) {
              if (_isSameDay(record.date, date) &&
                  record.slotKey == slot.slotKey &&
                  record.status == AttendanceStatus.cancelled) {
                isSlotCancelled = true;
                break;
              }
            }

            if (isDayHoliday || isSlotCancelled) {
              // Skip importing entirely (cleanup will delete it if it existed)
              continue;
            }

            startDateTime = DateTime(date.year, date.month, date.day, slot.startTime.hour, slot.startTime.minute);
            endDateTime = DateTime(date.year, date.month, date.day, slot.endTime.hour, slot.endTime.minute);
            untilDate = date; // One-time event
          } else {
            // Find first occurrence date on/after semester start (or slot effectiveFrom)
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

          // Format clean unique ID (alphanumeric characters, underscores, and dashes only)
          final String slotKeyId = slot.slotKey.replaceAll(':', '_').replaceAll('-', '_');
          final String uniqueICalId = "sched_${subject.id}_slot_$slotKeyId@attendmate.app".toLowerCase();
          activeICalIds.add(uniqueICalId);

          // 4. Construct RRULE and EXDATE exceptions for weekly events
          List<String>? recurrenceRule;
          if (!slot.isSpecialClass) {
            final String untilFormatted = "${untilDate.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z";
            recurrenceRule = ["RRULE:FREQ=WEEKLY;UNTIL=$untilFormatted"];

            // Find all occurrence dates and check for holidays/cancellations
            DateTime currentDate = DateTime(startDateTime.year, startDateTime.month, startDateTime.day);
            final DateTime checkUntil = DateTime(untilDate.year, untilDate.month, untilDate.day);

            while (currentDate.isBefore(checkUntil) || _isSameDay(currentDate, checkUntil)) {
              final isDayHoliday = isHoliday(currentDate);
              bool isSlotCancelled = false;

              for (final record in subject.attendanceRecords) {
                if (_isSameDay(record.date, currentDate) &&
                    record.slotKey == slot.slotKey &&
                    record.status == AttendanceStatus.cancelled) {
                  isSlotCancelled = true;
                  break;
                }
              }

              if (isDayHoliday || isSlotCancelled) {
                // Convert occurrence local start time to UTC for the EXDATE
                final occurrenceLocalStart = DateTime(
                  currentDate.year,
                  currentDate.month,
                  currentDate.day,
                  slot.startTime.hour,
                  slot.startTime.minute,
                );
                final occurrenceUtcStart = occurrenceLocalStart.toUtc();
                final exdateStr = "${occurrenceUtcStart.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z";
                recurrenceRule.add("EXDATE:$exdateStr");
              }

              currentDate = currentDate.add(const Duration(days: 7));
            }
          }

          // 5. Build Event resource
          final cal.Event eventToImport = cal.Event()
            ..iCalUID = uniqueICalId
            ..summary = "${subject.name} ${subject.acronym != null ? '(${subject.acronym})' : ''}".trim()
            ..description = "Imported from AttendMate. Re-importing updates this specific schedule.\nTarget attendance: ${subject.targetAttendance}%."
            ..colorId = colorId
            ..start = (cal.EventDateTime()..dateTime = startDateTime.toUtc()..timeZone = "UTC")
            ..end = (cal.EventDateTime()..dateTime = endDateTime.toUtc()..timeZone = "UTC")
            ..recurrence = recurrenceRule;

          // 6. Execute import
          try {
            await calendarApi.events.import(eventToImport, "primary");
          } catch (e) {
            // Handle edge case: if event was deleted on Google Calendar, it exists in a "tombstone" (cancelled) state.
            // Google API import might fail. In this case, we search for the tombstoned event and revive it via update/PUT.
            final listResult = await calendarApi.events.list(
              "primary", 
              iCalUID: uniqueICalId, 
              showDeleted: true
            );
            
            final existingEvents = listResult.items ?? [];
            if (existingEvents.isNotEmpty) {
              final existingEvent = existingEvents.first;
              final eventId = existingEvent.id;
              
              if (eventId != null) {
                // Revive the event by updating its details and setting status to "confirmed"
                eventToImport.status = "confirmed";
                await calendarApi.events.update(eventToImport, "primary", eventId);
              } else {
                rethrow;
              }
            } else {
              rethrow;
            }
          }
        }
      }

      // 7. Clean up deleted classes (strictly within the active semester schedule range only)
      // Retrieve all existing events imported by AttendMate
      final cal.Events existingEvents = await calendarApi.events.list(
        "primary",
        q: "Imported from AttendMate",
        maxResults: 250,
      );

      final List<cal.Event> items = existingEvents.items ?? [];
      for (final event in items) {
        final iCalUID = event.iCalUID;
        if (iCalUID != null && iCalUID.startsWith("sched_") && iCalUID.endsWith("@attendmate.app")) {
          final eventStart = event.start?.dateTime ?? event.start?.date;
          if (eventStart != null) {
            
            // Only touch events that fall within the current semester range
            if ((eventStart.isAfter(semester.startDate) || _isSameDay(eventStart, semester.startDate)) &&
                (eventStart.isBefore(semester.endDate) || _isSameDay(eventStart, semester.endDate))) {
              
              if (!activeICalIds.contains(iCalUID)) {
                final eventId = event.id;
                if (eventId != null) {
                  await calendarApi.events.delete("primary", eventId);
                }
              }
            }
          }
        }
      }
    } catch (e) {
      rethrow;
    }
  }
}
