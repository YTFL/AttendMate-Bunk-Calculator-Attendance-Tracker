import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../features/attendance/attendance_model.dart';
import '../features/subject/subject_model.dart';

class ParsedAttendanceItem {
  final DateTime date;
  final String rawSubjectName;
  final Subject? matchedSubject;
  final AttendanceStatus status;
  final String? slot;

  ParsedAttendanceItem({
    required this.date,
    required this.rawSubjectName,
    required this.matchedSubject,
    required this.status,
    this.slot,
  });

  bool get isMatched => matchedSubject != null;

  Attendance toAttendance() {
    if (matchedSubject == null) {
      throw StateError('Cannot convert unmatched item to Attendance');
    }
    return Attendance(
      subjectId: matchedSubject!.id,
      date: DateTime(date.year, date.month, date.day),
      status: status,
      slotKey: slot?.trim().isNotEmpty == true ? slot!.trim() : null,
    );
  }
}

class ParsedSubjectAttendanceBaseline {
  final Subject subject;
  final int classesHeld;
  final int classesAttended;

  ParsedSubjectAttendanceBaseline({
    required this.subject,
    required this.classesHeld,
    required this.classesAttended,
  });

  int get classesAbsent => (classesHeld - classesAttended).clamp(0, classesHeld);

  double get percentage =>
      classesHeld > 0 ? (classesAttended / classesHeld) * 100 : 0.0;
}

class AttendanceImportResult {
  final List<ParsedAttendanceItem> items;
  final List<ParsedSubjectAttendanceBaseline> directBaselines;
  final Set<String> unmatchedSubjectNames;
  final List<String> errors;
  final int totalRows;

  AttendanceImportResult({
    required this.items,
    this.directBaselines = const [],
    required this.unmatchedSubjectNames,
    required this.errors,
    required this.totalRows,
  });

  List<ParsedAttendanceItem> get matchedItems =>
      items.where((item) => item.isMatched).toList();

  int get matchedCount => directBaselines.isNotEmpty
      ? directBaselines.length
      : matchedItems.length;
  int get unmatchedCount => unmatchedSubjectNames.length;

  int get attendedCount => directBaselines.isNotEmpty
      ? directBaselines.fold<int>(0, (sum, b) => sum + b.classesAttended)
      : matchedItems.where((i) => i.status == AttendanceStatus.attended).length;

  int get absentCount => directBaselines.isNotEmpty
      ? directBaselines.fold<int>(0, (sum, b) => sum + b.classesAbsent)
      : matchedItems.where((i) => i.status == AttendanceStatus.absent).length;

  int get cancelledCount => matchedItems.where((i) => i.status == AttendanceStatus.cancelled).length;

  DateTime? get earliestDate {
    if (matchedItems.isEmpty) return null;
    return matchedItems.map((i) => i.date).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  DateTime? get latestDate {
    if (matchedItems.isEmpty) return null;
    return matchedItems.map((i) => i.date).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// Calculates the aggregated baseline per matched subject from either
  /// direct summary baselines (e.g. held/attended) or granular items.
  Map<String, ParsedSubjectAttendanceBaseline> computeBaselinesPerSubject() {
    final map = <String, ParsedSubjectAttendanceBaseline>{};

    if (directBaselines.isNotEmpty) {
      for (final b in directBaselines) {
        map[b.subject.id] = b;
      }
      return map;
    }

    final grouped = <Subject, List<ParsedAttendanceItem>>{};
    for (final item in matchedItems) {
      if (item.matchedSubject != null) {
        grouped.putIfAbsent(item.matchedSubject!, () => []).add(item);
      }
    }

    for (final entry in grouped.entries) {
      final subject = entry.key;
      final subjectItems = entry.value;

      final held = subjectItems.where((i) =>
          i.status == AttendanceStatus.attended ||
          i.status == AttendanceStatus.absent).length;
      final attended = subjectItems.where((i) => i.status == AttendanceStatus.attended).length;

      map[subject.id] = ParsedSubjectAttendanceBaseline(
        subject: subject,
        classesHeld: held,
        classesAttended: attended,
      );
    }

    return map;
  }
}

class AttendanceImportUtils {
  static const String sampleCsvTemplate = '''date,subject,status,slot
2026-08-10,Mathematics,Present,09:00 - 10:00
2026-08-10,Physics,Absent,10:00 - 11:00
2026-08-11,Chemistry,Present,
2026-08-12,Mathematics,Absent,09:00 - 10:00''';

  static const String sampleSummaryCsvTemplate = '''subject,held,attended
Mathematics,24,20
Physics,20,17
Chemistry,18,16''';

  static const String sampleJsonTemplate = '''[
  {
    "date": "2026-08-10",
    "subject": "Mathematics",
    "status": "Present",
    "slot": "09:00 - 10:00"
  },
  {
    "date": "2026-08-10",
    "subject": "Physics",
    "status": "Absent",
    "slot": "10:00 - 11:00"
  },
  {
    "date": "2026-08-11",
    "subject": "Chemistry",
    "status": "Present"
  },
  {
    "date": "2026-08-12",
    "subject": "Mathematics",
    "status": "Absent",
    "slot": "09:00 - 10:00"
  }
]''';

  static const String sampleSummaryJsonTemplate = '''[
  {
    "subject": "Mathematics",
    "held": 24,
    "attended": 20
  },
  {
    "subject": "Physics",
    "held": 20,
    "attended": 17
  },
  {
    "subject": "Chemistry",
    "held": 18,
    "attended": 16
  }
]''';

  static const String attendanceAiPrompt = '''I have provided an image, screenshot, or text of my college attendance records/portal. Convert all attendance records into the following JSON summary format:

[
  {
    "subject": "Mathematics",
    "held": 24,
    "attended": 20
  },
  {
    "subject": "Physics",
    "held": 20,
    "attended": 17
  }
]

Rules to follow:
- "subject" must match the exact subject name, acronym, or course code from my timetable.
- "held" is the total number of classes conducted.
- "attended" is the total number of classes present/attended.
- Return ONLY the raw valid JSON array with no markdown code blocks, preamble, or explanation.''';

  /// Matches raw subject string against available Subject list
  static Subject? matchSubject(String rawName, List<Subject> subjects) {
    final cleaned = rawName.trim().toLowerCase();
    if (cleaned.isEmpty) return null;

    // 1. Match by exact subject ID
    for (final s in subjects) {
      if (s.id.toLowerCase() == cleaned) return s;
    }

    // 2. Match by exact name (case-insensitive)
    for (final s in subjects) {
      if (s.name.trim().toLowerCase() == cleaned) return s;
    }

    // 3. Match by exact acronym (case-insensitive)
    for (final s in subjects) {
      if (s.acronym?.trim().toLowerCase() == cleaned) return s;
    }

    // 4. Normalized substring match
    for (final s in subjects) {
      final sName = s.name.trim().toLowerCase();
      if (sName.contains(cleaned) || cleaned.contains(sName)) return s;
    }

    return null;
  }

  /// Parse status string into AttendanceStatus
  static AttendanceStatus? parseStatus(String rawStatus) {
    final s = rawStatus.trim().toLowerCase();
    if (s == 'present' || s == 'attended' || s == 'p' || s == '1' || s == 'yes') {
      return AttendanceStatus.attended;
    }
    if (s == 'absent' || s == 'bunk' || s == 'bunked' || s == 'a' || s == '0' || s == 'no') {
      return AttendanceStatus.absent;
    }
    if (s == 'cancelled' || s == 'canceled' || s == 'holiday' || s == 'c' || s == 'h') {
      return AttendanceStatus.cancelled;
    }
    return null;
  }

  /// Parse various date string representations into DateTime
  static DateTime? parseDate(String rawDate) {
    final s = rawDate.trim();
    if (s.isEmpty) return null;

    // Try ISO format (yyyy-MM-dd)
    final iso = DateTime.tryParse(s);
    if (iso != null) {
      return DateTime(iso.year, iso.month, iso.day);
    }

    // Try slash formats (dd/MM/yyyy or MM/dd/yyyy)
    final slashParts = s.split(RegExp(r'[/.-]'));
    if (slashParts.length == 3) {
      final p0 = int.tryParse(slashParts[0]);
      final p1 = int.tryParse(slashParts[1]);
      final p2 = int.tryParse(slashParts[2]);

      if (p0 != null && p1 != null && p2 != null) {
        if (p2 > 1000) {
          // dd/MM/yyyy or MM/dd/yyyy
          final day = p0 <= 31 ? p0 : p1;
          final month = p0 <= 31 && p1 <= 12 ? p1 : p0;
          return DateTime(p2, month, day);
        } else if (p0 > 1000) {
          // yyyy/MM/dd
          return DateTime(p0, p1, p2);
        }
      }
    }

    return null;
  }

  /// Parse CSV string content
  static AttendanceImportResult parseCsv(String content, List<Subject> subjects) {
    final lines = content.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      return AttendanceImportResult(
        items: [],
        unmatchedSubjectNames: {},
        errors: ['The selected CSV file is empty.'],
        totalRows: 0,
      );
    }

    // Identify header column indices
    final headerTokens = _splitCsvLine(lines.first).map((t) => t.trim().toLowerCase()).toList();
    int dateCol = -1;
    int subjectCol = -1;
    int statusCol = -1;
    int slotCol = -1;
    int heldCol = -1;
    int attendedCol = -1;

    for (int i = 0; i < headerTokens.length; i++) {
      final h = headerTokens[i];
      if (h.contains('date') || h == 'day') dateCol = i;
      if (h.contains('sub') || h == 'course' || h == 'name') subjectCol = i;
      if (h.contains('stat') || (h.contains('attendance') && !h.contains('percent'))) statusCol = i;
      if (h.contains('slot') || h.contains('time')) slotCol = i;
      if (h.contains('held') || h.contains('total') || h.contains('conducted')) heldCol = i;
      if (h.contains('attend') || h.contains('present')) attendedCol = i;
    }

    // Check if summary mode (subject, held, attended)
    final isSummary = subjectCol != -1 && heldCol != -1 && attendedCol != -1 && statusCol == -1;

    if (isSummary) {
      final directBaselines = <ParsedSubjectAttendanceBaseline>[];
      final unmatched = <String>{};
      final errors = <String>[];

      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final cols = _splitCsvLine(line);
        if (cols.length <= subjectCol || cols.length <= heldCol || cols.length <= attendedCol) {
          errors.add('Row ${i + 1}: Insufficient columns.');
          continue;
        }

        final subjectStr = cols[subjectCol];
        final held = int.tryParse(cols[heldCol]);
        final attended = int.tryParse(cols[attendedCol]);

        if (held == null || attended == null || held < 0 || attended < 0 || attended > held) {
          errors.add('Row ${i + 1}: Invalid held/attended counts for "$subjectStr".');
          continue;
        }

        final matched = matchSubject(subjectStr, subjects);
        if (matched == null) {
          unmatched.add(subjectStr.trim());
        } else {
          directBaselines.add(ParsedSubjectAttendanceBaseline(
            subject: matched,
            classesHeld: held,
            classesAttended: attended,
          ));
        }
      }

      return AttendanceImportResult(
        items: [],
        directBaselines: directBaselines,
        unmatchedSubjectNames: unmatched,
        errors: errors,
        totalRows: lines.length - 1,
      );
    }

    // Default fallback indices if headers not recognized
    if (dateCol == -1) dateCol = 0;
    if (subjectCol == -1) subjectCol = 1;
    if (statusCol == -1) statusCol = 2;
    if (slotCol == -1 && headerTokens.length > 3) slotCol = 3;

    final items = <ParsedAttendanceItem>[];
    final unmatched = <String>{};
    final errors = <String>[];

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cols = _splitCsvLine(line);
      if (cols.length <= dateCol || cols.length <= subjectCol || cols.length <= statusCol) {
        errors.add('Row ${i + 1}: Insufficient columns.');
        continue;
      }

      final dateStr = cols[dateCol];
      final subjectStr = cols[subjectCol];
      final statusStr = cols[statusCol];
      final slotStr = slotCol >= 0 && cols.length > slotCol ? cols[slotCol] : null;

      final parsedDate = parseDate(dateStr);
      if (parsedDate == null) {
        errors.add('Row ${i + 1}: Invalid date format "$dateStr".');
        continue;
      }

      final parsedStatus = parseStatus(statusStr);
      if (parsedStatus == null) {
        errors.add('Row ${i + 1}: Unrecognized status "$statusStr".');
        continue;
      }

      final matched = matchSubject(subjectStr, subjects);
      if (matched == null) {
        unmatched.add(subjectStr.trim());
      }

      items.add(ParsedAttendanceItem(
        date: parsedDate,
        rawSubjectName: subjectStr.trim(),
        matchedSubject: matched,
        status: parsedStatus,
        slot: slotStr?.trim(),
      ));
    }

    return AttendanceImportResult(
      items: items,
      unmatchedSubjectNames: unmatched,
      errors: errors,
      totalRows: lines.length - 1,
    );
  }

  /// Parse JSON string content
  static AttendanceImportResult parseJson(String content, List<Subject> subjects) {
    try {
      var trimmed = content.trim();
      if (trimmed.startsWith('```')) {
        final lines = trimmed.split('\n');
        if (lines.isNotEmpty && lines.first.startsWith('```')) {
          lines.removeAt(0);
        }
        if (lines.isNotEmpty && lines.last.trim().startsWith('```')) {
          lines.removeLast();
        }
        trimmed = lines.join('\n').trim();
      }

      final dynamic decoded = jsonDecode(trimmed);
      List<dynamic> list;

      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map<String, dynamic>) {
        if (decoded['attendance'] is List) {
          list = decoded['attendance'] as List;
        } else if (decoded['records'] is List) {
          list = decoded['records'] as List;
        } else if (decoded['data'] is List) {
          list = decoded['data'] as List;
        } else if (decoded['items'] is List) {
          list = decoded['items'] as List;
        } else {
          return AttendanceImportResult(
            items: [],
            unmatchedSubjectNames: {},
            errors: ['JSON format must be an array of attendance records or an object with an "attendance" or "records" array.'],
            totalRows: 0,
          );
        }
      } else {
        return AttendanceImportResult(
          items: [],
          unmatchedSubjectNames: {},
          errors: ['JSON format must be an array of attendance records or an object with an "attendance" array.'],
          totalRows: 0,
        );
      }

      // Check if list items are summary baseline format (has held/total and attended/present)
      bool isSummary = false;
      if (list.isNotEmpty && list.first is Map) {
        final first = list.first as Map;
        isSummary = (first.containsKey('held') || first.containsKey('total') || first.containsKey('classes_held')) &&
            (first.containsKey('attended') || first.containsKey('present') || first.containsKey('classes_attended'));
      }

      if (isSummary) {
        final directBaselines = <ParsedSubjectAttendanceBaseline>[];
        final unmatched = <String>{};
        final errors = <String>[];

        for (int i = 0; i < list.length; i++) {
          final item = list[i];
          if (item is! Map) {
            errors.add('Entry ${i + 1} is not a valid JSON object.');
            continue;
          }

          final subjectStr = (item['subject'] ?? item['subject_name'] ?? item['course'] ?? item['name'])?.toString();
          final heldVal = item['held'] ?? item['total'] ?? item['classes_held'];
          final attendedVal = item['attended'] ?? item['present'] ?? item['classes_attended'];

          final held = heldVal is num ? heldVal.toInt() : int.tryParse(heldVal?.toString() ?? '');
          final attended = attendedVal is num ? attendedVal.toInt() : int.tryParse(attendedVal?.toString() ?? '');

          if (subjectStr == null || held == null || attended == null || held < 0 || attended < 0 || attended > held) {
            errors.add('Entry ${i + 1}: Invalid or missing fields for subject "$subjectStr".');
            continue;
          }

          final matched = matchSubject(subjectStr, subjects);
          if (matched == null) {
            unmatched.add(subjectStr.trim());
          } else {
            directBaselines.add(ParsedSubjectAttendanceBaseline(
              subject: matched,
              classesHeld: held,
              classesAttended: attended,
            ));
          }
        }

        return AttendanceImportResult(
          items: [],
          directBaselines: directBaselines,
          unmatchedSubjectNames: unmatched,
          errors: errors,
          totalRows: list.length,
        );
      }

      final items = <ParsedAttendanceItem>[];
      final unmatched = <String>{};
      final errors = <String>[];

      for (int i = 0; i < list.length; i++) {
        final item = list[i];
        if (item is! Map) {
          errors.add('Entry ${i + 1} is not a valid JSON object.');
          continue;
        }

        final dateStr = (item['date'] ?? item['class_date'] ?? item['day'])?.toString();
        final subjectStr = (item['subject'] ?? item['subject_name'] ?? item['course'] ?? item['name'])?.toString();
        final statusStr = (item['status'] ?? item['attendance_status'])?.toString();
        final slotStr = (item['slot'] ?? item['time'] ?? item['slot_key'])?.toString();

        if (dateStr == null || subjectStr == null || statusStr == null) {
          errors.add('Entry ${i + 1} is missing required fields (date, subject, or status).');
          continue;
        }

        final parsedDate = parseDate(dateStr);
        if (parsedDate == null) {
          errors.add('Entry ${i + 1}: Invalid date "$dateStr".');
          continue;
        }

        final parsedStatus = parseStatus(statusStr);
        if (parsedStatus == null) {
          errors.add('Entry ${i + 1}: Unrecognized status "$statusStr".');
          continue;
        }

        final matched = matchSubject(subjectStr, subjects);
        if (matched == null) {
          unmatched.add(subjectStr.trim());
        }

        items.add(ParsedAttendanceItem(
          date: parsedDate,
          rawSubjectName: subjectStr.trim(),
          matchedSubject: matched,
          status: parsedStatus,
          slot: slotStr?.trim(),
        ));
      }

      return AttendanceImportResult(
        items: items,
        unmatchedSubjectNames: unmatched,
        errors: errors,
        totalRows: list.length,
      );
    } catch (e) {
      debugPrint('AttendanceImportUtils parseJson error: $e');
      return AttendanceImportResult(
        items: [],
        unmatchedSubjectNames: {},
        errors: ['Invalid JSON format: $e'],
        totalRows: 0,
      );
    }
  }

  /// Automatically detects format (CSV vs JSON) and parses
  static AttendanceImportResult parseContent(String content, List<Subject> subjects, {String? fileName}) {
    final trimmed = content.trim();
    if (fileName?.toLowerCase().endsWith('.json') == true ||
        trimmed.startsWith('[') ||
        trimmed.startsWith('{')) {
      return parseJson(trimmed, subjects);
    }
    return parseCsv(trimmed, subjects);
  }

  /// Splits CSV line while respecting quoted values
  static List<String> _splitCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    result.add(buffer.toString().trim());
    return result;
  }
}
