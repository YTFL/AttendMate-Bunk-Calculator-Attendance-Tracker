import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';

import '../features/subject/subject_model.dart';

class SpecialClassImportItem {
  final String? subjectName;
  final String? subjectAcronym;
  final TimeSlot slot;
  final bool isStandaloneSpecialSubject;

  SpecialClassImportItem({
    this.subjectName,
    this.subjectAcronym,
    required this.slot,
    this.isStandaloneSpecialSubject = false,
  });

  String get displayName => subjectName ?? subjectAcronym ?? 'Special Class';
}

class ParsedTimetableImportPackage {
  final List<Subject> standardSubjects;
  final List<ElectiveSlot> electiveSlots;
  final List<SpecialClassImportItem> specialClasses;
  final DateTime? effectiveFrom;

  ParsedTimetableImportPackage({
    required this.standardSubjects,
    required this.electiveSlots,
    required this.specialClasses,
    this.effectiveFrom,
  });

  bool get hasElectives => electiveSlots.isNotEmpty;
  bool get hasSpecialClasses => specialClasses.isNotEmpty;
  bool get hasStandardSubjects => standardSubjects.isNotEmpty;
  int get totalSubjectsCount => standardSubjects.length + electiveSlots.fold<int>(0, (sum, e) => sum + e.subjects.length);

  /// Flatten all standard subjects + all subjects in all elective slots
  List<Subject> get allSubjects {
    final list = <Subject>[...standardSubjects];
    for (final slot in electiveSlots) {
      list.addAll(slot.subjects);
    }
    return list;
  }
}

class TimetableImportUtils {
  // Available colors for subjects
  static const List<Color> availableColors = [
    Color(0xFFE53935),
    Color(0xFFD81B60),
    Color(0xFFEC407A),
    Color(0xFFAB47BC),
    Color(0xFF8E24AA),
    Color(0xFF5E35B1),
    Color(0xFF3949AB),
    Color(0xFF1E88E5),
    Color(0xFF42A5F5),
    Color(0xFF039BE5),
    Color(0xFF26C6DA),
    Color(0xFF00ACC1),
    Color(0xFF26A69A),
    Color(0xFF00897B),
    Color(0xFF43A047),
    Color(0xFF66BB6A),
    Color(0xFF7CB342),
    Color(0xFFC0CA33),
    Color(0xFFFDD835),
    Color(0xFFFFCA28),
    Color(0xFFFFB300),
    Color(0xFFFB8C00),
    Color(0xFFFF7043),
    Color(0xFFF4511E),
    Color(0xFF6D4C41),
    Color(0xFF8D6E63),
    Color(0xFF546E7A),
    Color(0xFF757575),
  ];

  /// Get a random unused color from the available colors
  static Color getRandomUnusedColor(Set<Color> usedColors) {
    final availableColorsSet = availableColors.where((color) => !usedColors.contains(color)).toList();
    
    if (availableColorsSet.isEmpty) {
      // If all colors are used, return a random color from all available
      return availableColors[Random().nextInt(availableColors.length)];
    }
    
    return availableColorsSet[Random().nextInt(availableColorsSet.length)];
  }

  /// Parse JSON string and return flat list of subjects (backward compatibility)
  static List<Subject> parseJsonToSubjects(String jsonString, Set<Color> usedColors) {
    final pkg = parseJsonToImportPackage(jsonString, usedColors);
    final subjects = <Subject>[...pkg.standardSubjects];
    for (final elective in pkg.electiveSlots) {
      subjects.addAll(elective.subjects);
    }
    return subjects;
  }

  /// Parse pasted input (JSON or CSV) and return a rich package with standard subjects,
  /// elective slots, special one-off classes, and effectiveFrom dates.
  static ParsedTimetableImportPackage parseInputToImportPackage(String input, Set<Color> usedColors) {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      throw Exception('Please paste JSON or CSV data.');
    }

    final startsLikeJson = normalized.startsWith('{') || normalized.startsWith('[');
    if (startsLikeJson) {
      return parseJsonToImportPackage(normalized, usedColors);
    }

    final csvSubjects = parseCsvToSubjects(normalized, usedColors);
    return ParsedTimetableImportPackage(
      standardSubjects: csvSubjects,
      electiveSlots: const [],
      specialClasses: const [],
    );
  }

  /// Parse pasted input and auto-detect JSON or CSV format (backward compatibility)
  static List<Subject> parseInputToSubjects(String input, Set<Color> usedColors) {
    final pkg = parseInputToImportPackage(input, usedColors);
    final subjects = <Subject>[...pkg.standardSubjects];
    for (final elective in pkg.electiveSlots) {
      subjects.addAll(elective.subjects);
    }
    return subjects;
  }

  /// Comprehensive JSON parser handling:
  /// - Full master timetable JSON
  /// - Electives-only JSON
  /// - Special one-off classes only JSON
  /// - Mid-semester new subjects JSON
  /// - Legacy subjects list/map
  static ParsedTimetableImportPackage parseJsonToImportPackage(String jsonString, Set<Color> usedColors) {
    try {
      final jsonData = jsonDecode(jsonString);
      final List<Subject> standardSubjects = [];
      final List<ElectiveSlot> electiveSlots = [];
      final List<SpecialClassImportItem> specialClasses = [];
      DateTime? effectiveFrom;
      Set<Color> currentUsedColors = Set.from(usedColors);

      // Handle raw array: could be array of subjects or array of special one-off classes
      if (jsonData is List) {
        final list = jsonData;
        for (var item in list) {
          if (item is Map) {
            final isOneOff = (item.containsKey('date') || item.containsKey('specificDate')) &&
                !item.containsKey('schedule');
            if (isOneOff) {
              final parsed = _parseSpecialClassItem(item);
              if (parsed != null) specialClasses.add(parsed);
            } else {
              try {
                final s = _parseSubjectFromJson(item, currentUsedColors);
                standardSubjects.add(s);
                currentUsedColors.add(s.color);
              } catch (_) {}
            }
          }
        }

        if (standardSubjects.isEmpty && specialClasses.isEmpty) {
          throw Exception('No valid subjects or special classes found in the JSON list.');
        }

        return ParsedTimetableImportPackage(
          standardSubjects: standardSubjects,
          electiveSlots: electiveSlots,
          specialClasses: specialClasses,
        );
      }

      if (jsonData is! Map<String, dynamic>) {
        throw Exception('Invalid JSON format. Expected an object or array.');
      }

      // 1. Parse effectiveFrom date if present (mid-semester support)
      if (jsonData.containsKey('effectiveFrom')) {
        final effStr = jsonData['effectiveFrom'] as String?;
        if (effStr != null && effStr.trim().isNotEmpty) {
          effectiveFrom = normalizeDate(DateTime.tryParse(effStr.trim()));
        }
      }

      // 2. Parse standard subjects if present
      if (jsonData.containsKey('subjects') && jsonData['subjects'] is List) {
        final subjectsList = jsonData['subjects'] as List<dynamic>;
        for (var subjectData in subjectsList) {
          try {
            final subject = _parseSubjectFromJson(subjectData, currentUsedColors, defaultEffectiveFrom: effectiveFrom);
            if (subject.isElective && subject.electiveGroupName != null && subject.electiveGroupName!.isNotEmpty) {
              // Group into elective slots if marked as elective
              final groupName = subject.electiveGroupName!;
              final existingSlotIdx = electiveSlots.indexWhere((e) => e.name.toLowerCase() == groupName.toLowerCase());
              if (existingSlotIdx != -1) {
                electiveSlots[existingSlotIdx].subjects.add(subject);
              } else {
                electiveSlots.add(ElectiveSlot(name: groupName, subjects: [subject]));
              }
            } else {
              standardSubjects.add(subject);
            }
            currentUsedColors.add(subject.color);
          } catch (_) {}
        }
      }

      // 3. Parse explicit electives array
      if (jsonData.containsKey('electives') && jsonData['electives'] is List) {
        final electivesList = jsonData['electives'] as List<dynamic>;
        for (var electiveData in electivesList) {
          if (electiveData is Map<String, dynamic>) {
            final slotName = electiveData['name'] as String? ?? 'Elective';
            final rawSubjects = electiveData['subjects'] as List<dynamic>? ?? [];
            final List<Subject> slotSubjects = [];

            for (var subData in rawSubjects) {
              try {
                final s = _parseSubjectFromJson(
                  subData,
                  currentUsedColors,
                  forceElective: true,
                  defaultElectiveGroup: slotName,
                  defaultEffectiveFrom: effectiveFrom,
                );
                slotSubjects.add(s);
                currentUsedColors.add(s.color);
              } catch (_) {}
            }

            if (slotSubjects.isNotEmpty) {
              // Check if already exists from subject list grouping
              final existingIdx = electiveSlots.indexWhere((e) => e.name.toLowerCase() == slotName.toLowerCase());
              if (existingIdx != -1) {
                electiveSlots[existingIdx].subjects.addAll(slotSubjects);
              } else {
                electiveSlots.add(ElectiveSlot(
                  id: electiveData['id'] as String?,
                  name: slotName,
                  subjects: slotSubjects,
                ));
              }
            }
          }
        }
      }

      // 4. Parse specialClasses / oneOffClasses array
      final specialListRaw = jsonData['specialClasses'] ?? jsonData['oneOffClasses'];
      if (specialListRaw is List) {
        for (var item in specialListRaw) {
          if (item is Map) {
            final parsed = _parseSpecialClassItem(item);
            if (parsed != null) specialClasses.add(parsed);
          }
        }
      }

      if (standardSubjects.isEmpty && electiveSlots.isEmpty && specialClasses.isEmpty) {
        throw Exception('No valid subjects, electives, or special one-off classes found in JSON.');
      }

      return ParsedTimetableImportPackage(
        standardSubjects: standardSubjects,
        electiveSlots: electiveSlots,
        specialClasses: specialClasses,
        effectiveFrom: effectiveFrom,
      );
    } catch (e) {
      throw Exception('Error parsing JSON: ${e.toString()}');
    }
  }

  static SpecialClassImportItem? _parseSpecialClassItem(Map item) {
    try {
      final dateStr = item['date'] ?? item['specificDate'];
      if (dateStr == null) return null;
      final parsedDate = normalizeDate(DateTime.tryParse(dateStr.toString()));
      if (parsedDate == null) return null;

      final startStr = item['startTime']?.toString();
      final endStr = item['endTime']?.toString();
      if (startStr == null || endStr == null) return null;

      final startTime = _parseTimeOfDay(startStr);
      final endTime = _parseTimeOfDay(endStr);
      if (startTime == null || endTime == null) return null;

      final day = DayOfWeek.values[parsedDate.weekday - 1];
      final slot = TimeSlot(
        day: day,
        startTime: startTime,
        endTime: endTime,
        specificDate: parsedDate,
        room: item['room']?.toString(),
        block: item['block']?.toString(),
        locationId: item['locationId']?.toString(),
        isExtra: item['isExtra'] as bool? ?? true,
      );

      final subjectName = (item['subject'] ?? item['name'] ?? item['subjectName'])?.toString().trim();
      final acronym = (item['acronym'] ?? item['code'])?.toString().trim();
      final isStandalone = item['isSpecialClass'] as bool? ?? false;

      return SpecialClassImportItem(
        subjectName: subjectName?.isNotEmpty == true ? subjectName : null,
        subjectAcronym: acronym?.isNotEmpty == true ? acronym : null,
        slot: slot,
        isStandaloneSpecialSubject: isStandalone,
      );
    } catch (_) {
      return null;
    }
  }

  /// Parse CSV grid exported by AttendMate and return list of subjects.
  static List<Subject> parseCsvToSubjects(String csvString, Set<Color> usedColors) {
    try {
      final cleaned = csvString
          .replaceFirst('\uFEFF', '')
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .trim();

      final lines = cleaned
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (lines.length < 2) {
        throw Exception('CSV must contain a header and at least one day row.');
      }

      final header = _parseCsvLine(lines.first);
      if (header.length < 2 || header.first.toLowerCase() != 'day') {
        throw Exception('Invalid CSV header. First column must be "Day".');
      }

      final slotDefs = <_CsvSlotDef>[];
      for (int i = 1; i < header.length; i++) {
        final parsedSlot = _parseCsvTimeSlot(header[i]);
        if (parsedSlot == null) {
          throw Exception('Invalid time slot in CSV header: "${header[i]}". Expected HH:MM-HH:MM');
        }
        slotDefs.add(parsedSlot);
      }

      final subjectSlots = <String, List<TimeSlot>>{};

      for (int rowIndex = 1; rowIndex < lines.length; rowIndex++) {
        final row = _parseCsvLine(lines[rowIndex]);
        if (row.isEmpty) {
          continue;
        }

        final day = _parseDayOfWeek(row.first);
        if (day == null) {
          throw Exception('Invalid day in CSV row ${rowIndex + 1}: "${row.first}".');
        }

        for (int col = 1; col < header.length && col < row.length; col++) {
          final rawValue = row[col].trim();
          final value = _normalizeCsvCell(rawValue);
          if (value == '-' || value.isEmpty) {
            continue;
          }

          final slot = slotDefs[col - 1];
          final timeSlot = TimeSlot(
            day: day,
            startTime: slot.startTime,
            endTime: slot.endTime,
          );

          subjectSlots.putIfAbsent(value, () => <TimeSlot>[]).add(timeSlot);
        }
      }

      if (subjectSlots.isEmpty) {
        throw Exception('No valid subjects found in CSV.');
      }

      final subjects = <Subject>[];
      var currentUsedColors = Set<Color>.from(usedColors);
      for (final entry in subjectSlots.entries) {
        final token = entry.key.trim();
        final schedule = entry.value;
        if (schedule.isEmpty) {
          continue;
        }

        final subject = Subject(
          name: token,
          acronym: token.length <= 12 ? token : null,
          color: getRandomUnusedColor(currentUsedColors),
          schedule: schedule,
        );
        subjects.add(subject);
        currentUsedColors.add(subject.color);
      }

      if (subjects.isEmpty) {
        throw Exception('No valid subjects found in CSV.');
      }

      return subjects;
    } catch (e) {
      throw Exception('Error parsing CSV: ${e.toString()}');
    }
  }

  static List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
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

  static _CsvSlotDef? _parseCsvTimeSlot(String value) {
    final normalized = value
        .trim()
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('−', '-');

    final parts = normalized.split('-');
    if (parts.length != 2) {
      return null;
    }

    final start = _parseTimeOfDay(parts[0]);
    final end = _parseTimeOfDay(parts[1]);
    if (start == null || end == null) {
      return null;
    }

    return _CsvSlotDef(startTime: start, endTime: end);
  }

  static String _normalizeCsvCell(String value) {
    final cleaned = value
        .trim()
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('−', '-')
        .replaceAll('\u00A0', ' ');
    return cleaned.isEmpty ? '-' : cleaned;
  }

  /// Parse individual subject from JSON
  static Subject _parseSubjectFromJson(
    dynamic subjectData,
    Set<Color> usedColors, {
    bool forceElective = false,
    String? defaultElectiveGroup,
    DateTime? defaultEffectiveFrom,
  }) {
    if (subjectData is! Map) {
      throw Exception('Subject must be an object');
    }

    final name = subjectData['name'] as String?;
    if (name == null || name.isEmpty) {
      throw Exception('Subject name is required');
    }

    final acronym = subjectData['acronym'] as String?;

    // Parse color if provided, otherwise assign a random unused color
    Color color;
    if (subjectData.containsKey('color')) {
      final colorValue = subjectData['color'];
      if (colorValue is int) {
        color = Color(colorValue);
      } else if (colorValue is String) {
        try {
          color = Color(int.parse(colorValue.replaceFirst('0x', ''), radix: 16));
        } catch (e) {
          color = getRandomUnusedColor(usedColors);
        }
      } else {
        color = getRandomUnusedColor(usedColors);
      }
    } else {
      color = getRandomUnusedColor(usedColors);
    }

    // Parse subject-level effectiveFrom if given
    DateTime? subEffFrom = defaultEffectiveFrom;
    if (subjectData.containsKey('effectiveFrom')) {
      final s = subjectData['effectiveFrom'] as String?;
      if (s != null && s.trim().isNotEmpty) {
        subEffFrom = normalizeDate(DateTime.tryParse(s.trim())) ?? subEffFrom;
      }
    }

    // Parse schedule
    final scheduleData = subjectData['schedule'];
    if (scheduleData == null || scheduleData is! List) {
      throw Exception('Schedule is required and must be an array for subject "$name"');
    }

    final List<TimeSlot> schedule = [];
    for (var slotData in scheduleData) {
      try {
        final slot = _parseTimeSlot(slotData, defaultEffectiveFrom: subEffFrom);
        schedule.add(slot);
      } catch (e) {
        continue;
      }
    }

    if (schedule.isEmpty) {
      throw Exception('Subject "$name" must have at least one time slot');
    }

    final targetAttendance = subjectData['targetAttendance'] as int? ?? 75;
    final isElective = forceElective || (subjectData['isElective'] as bool? ?? false);
    final electiveGroup = defaultElectiveGroup ??
        (subjectData['electiveGroupName'] as String? ?? subjectData['electiveGroup'] as String?);

    return Subject(
      name: name.trim(),
      acronym: (acronym?.trim().isEmpty ?? true) ? null : acronym?.trim(),
      color: color,
      schedule: schedule,
      targetAttendance: targetAttendance,
      locationId: subjectData['locationId'] as String?,
      room: subjectData['room'] as String?,
      block: subjectData['block'] as String?,
      isElective: isElective,
      electiveGroupName: electiveGroup?.trim().isNotEmpty == true ? electiveGroup!.trim() : null,
    );
  }

  /// Parse individual time slot from JSON
  static TimeSlot _parseTimeSlot(dynamic slotData, {DateTime? defaultEffectiveFrom}) {
    if (slotData is! Map) {
      throw Exception('Time slot must be an object');
    }

    // Date can be 'date' or 'specificDate'
    final dateStr = (slotData['date'] ?? slotData['specificDate']) as String?;
    DateTime? specificDate;
    if (dateStr != null && dateStr.trim().isNotEmpty) {
      specificDate = normalizeDate(DateTime.tryParse(dateStr.trim()));
    }

    final dayString = slotData['day'] as String?;
    DayOfWeek? day;
    if (dayString != null && dayString.trim().isNotEmpty) {
      day = _parseDayOfWeek(dayString);
    } else if (specificDate != null) {
      day = DayOfWeek.values[specificDate.weekday - 1];
    }

    if (day == null) {
      throw Exception('Day or specific date is required for time slot');
    }

    final startTimeStr = slotData['startTime'] as String?;
    final endTimeStr = slotData['endTime'] as String?;

    if (startTimeStr == null || endTimeStr == null) {
      throw Exception('startTime and endTime are required for time slots');
    }

    final startTime = _parseTimeOfDay(startTimeStr);
    final endTime = _parseTimeOfDay(endTimeStr);

    if (startTime == null || endTime == null) {
      throw Exception('Invalid time format. Use HH:MM format (e.g., "09:00", "14:30")');
    }

    // Effective range
    final effFromStr = slotData['effectiveFrom'] as String?;
    final effUntilStr = slotData['effectiveUntil'] as String?;
    final effFrom = effFromStr != null
        ? normalizeDate(DateTime.tryParse(effFromStr.trim()))
        : defaultEffectiveFrom;
    final effUntil = effUntilStr != null
        ? normalizeDate(DateTime.tryParse(effUntilStr.trim()))
        : null;

    final isExtra = slotData['isExtra'] as bool? ?? (specificDate != null);

    return TimeSlot(
      day: day,
      startTime: startTime,
      endTime: endTime,
      specificDate: specificDate,
      effectiveFrom: effFrom,
      effectiveUntil: effUntil,
      locationId: slotData['locationId'] as String?,
      room: slotData['room'] as String?,
      block: slotData['block'] as String?,
      isExtra: isExtra,
    );
  }

  /// Parse day of week from string
  static DayOfWeek? _parseDayOfWeek(String dayString) {
    final day = dayString.toLowerCase().trim();
    try {
      return DayOfWeek.values.firstWhere(
        (d) => d.name.toLowerCase() == day,
      );
    } catch (e) {
      return null;
    }
  }

  /// Parse time of day from string format HH:MM
  static TimeOfDay? _parseTimeOfDay(String timeString) {
    try {
      final parts = timeString.trim().split(':');
      if (parts.length != 2) return null;
      
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        return null;
      }
      
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      return null;
    }
  }

  // ==================== TEMPLATE JSON GENERATORS ====================

  /// Generate template Master Timetable JSON
  static String generateTemplateJsonMaster() {
    final template = {
      "subjects": [
        {
          "name": "Operating Systems",
          "acronym": "OS",
          "room": "Room 201",
          "block": "Block A",
          "schedule": [
            {"day": "monday", "startTime": "09:00", "endTime": "10:30", "room": "Room 201"},
            {"day": "wednesday", "startTime": "14:00", "endTime": "15:30", "room": "Room 201"}
          ]
        }
      ],
      "electives": [
        {
          "name": "Professional Elective I",
          "subjects": [
            {
              "name": "Machine Learning",
              "acronym": "ML",
              "schedule": [
                {"day": "tuesday", "startTime": "11:00", "endTime": "12:30", "room": "Lab 3"}
              ]
            },
            {
              "name": "Cloud Computing",
              "acronym": "CC",
              "schedule": [
                {"day": "tuesday", "startTime": "11:00", "endTime": "12:30", "room": "Room 105"}
              ]
            }
          ]
        }
      ],
      "specialClasses": [
        {
          "subject": "Operating Systems",
          "date": "2026-11-20",
          "startTime": "14:00",
          "endTime": "16:00",
          "room": "Lab 1",
          "isExtra": true
        }
      ]
    };
    return jsonEncode(template);
  }

  /// Legacy alias for template JSON
  static String generateTemplateJson() => generateTemplateJsonMaster();

  /// Generate template Special One-Off Classes JSON
  static String generateTemplateJsonSpecialClasses() {
    final template = {
      "specialClasses": [
        {
          "subject": "Mathematics",
          "acronym": "MTH",
          "date": "2026-11-20",
          "startTime": "14:00",
          "endTime": "15:30",
          "room": "Room 302",
          "block": "Block B",
          "isExtra": true
        },
        {
          "name": "AI & Robotics Workshop",
          "acronym": "ROBO",
          "date": "2026-11-22",
          "startTime": "10:00",
          "endTime": "13:00",
          "room": "Auditorium",
          "isSpecialClass": true
        }
      ]
    };
    return jsonEncode(template);
  }

  /// Generate template Mid-Semester New Subjects JSON
  static String generateTemplateJsonMidSemester() {
    final template = {
      "effectiveFrom": "2026-11-15",
      "subjects": [
        {
          "name": "Cloud Computing",
          "acronym": "CC",
          "targetAttendance": 75,
          "room": "Lab 4",
          "schedule": [
            {"day": "tuesday", "startTime": "10:00", "endTime": "11:30", "room": "Lab 4"},
            {"day": "thursday", "startTime": "14:00", "endTime": "15:30", "room": "Room 205"}
          ]
        }
      ]
    };
    return jsonEncode(template);
  }

  /// Generate template Electives Only JSON
  static String generateTemplateJsonElectives() {
    final template = {
      "electives": [
        {
          "name": "Professional Elective I",
          "subjects": [
            {
              "name": "Machine Learning",
              "acronym": "ML",
              "schedule": [
                {"day": "wednesday", "startTime": "11:00", "endTime": "12:30", "room": "Lab 3"}
              ]
            },
            {
              "name": "Information Security",
              "acronym": "IS",
              "schedule": [
                {"day": "wednesday", "startTime": "11:00", "endTime": "12:30", "room": "Room 105"}
              ]
            }
          ]
        }
      ]
    };
    return jsonEncode(template);
  }

  /// Generate template CSV format compatible with AttendMate export/import.
  static String generateTemplateCsv() {
    return '''Day,"09:00-10:30","10:00-11:30","11:00-12:30","14:00-15:30","16:00-18:00"
Monday,"MTH","-","CHE","ENG","-"
Tuesday,"PHY","-","CSE","-","-"
Wednesday,"CHE","-","MTH","ENG","-"
Thursday,"CSE","-","-","PHY","-"
Friday,"MTH","-","-","CHE","-"
Saturday,"-","PHY","-","CSE","-"
Sunday,"-","-","-","-","ENG"''';
  }

  // ==================== AI PROMPTS ====================

  /// Master prompt for full timetable with electives and one-off classes
  static const String timetableAiPromptMaster = '''I have provided an image, screenshot, or text of my college timetable/schedule. Convert all subjects, elective options, and any special classes into the following JSON format:

{
  "subjects": [
    {
      "name": "Operating Systems",
      "acronym": "OS",
      "room": "Room 201",
      "block": "Block A",
      "schedule": [
        {
          "day": "monday",
          "startTime": "09:00",
          "endTime": "10:30",
          "room": "Room 201"
        }
      ]
    }
  ],
  "electives": [
    {
      "name": "Professional Elective I",
      "subjects": [
        {
          "name": "Machine Learning",
          "acronym": "ML",
          "schedule": [
            {
              "day": "wednesday",
              "startTime": "11:00",
              "endTime": "12:30",
              "room": "Lab 3"
            }
          ]
        },
        {
          "name": "Cloud Computing",
          "acronym": "CC",
          "schedule": [
            {
              "day": "wednesday",
              "startTime": "11:00",
              "endTime": "12:30",
              "room": "Room 105"
            }
          ]
        }
      ]
    }
  ],
  "specialClasses": [
    {
      "subject": "Operating Systems",
      "date": "2026-11-20",
      "startTime": "14:00",
      "endTime": "16:00",
      "room": "Lab 1"
    }
  ]
}

Rules to follow:
- "day" must be lowercase day of week: "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", or "sunday".
- "startTime" and "endTime" must strictly be in 24-hour HH:mm format (e.g. "09:00", "14:30").
- "date" must be in YYYY-MM-DD format.
- Group any elective course choices sharing the same time slot under the "electives" list with an appropriate slot name (e.g. "Elective 1").
- Any single-date makeup classes, workshops, or one-off sessions belong under "specialClasses".
- Return ONLY the raw valid JSON object with no markdown code blocks, preamble, or explanation.''';

  /// Legacy alias
  static const String timetableAiPrompt = timetableAiPromptMaster;

  /// AI Prompt for Special One-Off / Extra Classes only
  static const String timetableAiPromptSpecialClasses = '''I have provided an announcement, circular, email, or message about upcoming makeup classes, extra sessions, seminars, or workshops. Convert these one-off events into the following JSON format:

{
  "specialClasses": [
    {
      "subject": "Mathematics",
      "acronym": "MTH",
      "date": "2026-11-20",
      "startTime": "14:00",
      "endTime": "15:30",
      "room": "Room 302",
      "block": "Block B",
      "isExtra": true
    },
    {
      "name": "Cybersecurity Workshop",
      "acronym": "CSW",
      "date": "2026-11-22",
      "startTime": "10:00",
      "endTime": "13:00",
      "room": "Auditorium",
      "isSpecialClass": true
    }
  ]
}

Rules to follow:
- "date" must strictly be in "YYYY-MM-DD" format.
- "startTime" and "endTime" must be in 24-hour HH:mm format (e.g. "09:30", "16:00").
- For extra classes on an existing course, specify "subject" or "acronym" and set "isExtra": true.
- For new standalone workshops/seminars, specify "name" and set "isSpecialClass": true.
- "room" and "block" are optional.
- Return ONLY the raw valid JSON object with no markdown code blocks, preamble, or explanation.''';

  /// AI Prompt for Mid-Semester New Subjects only
  static const String timetableAiPromptMidSemester = '''I am enrolling in new subjects mid-semester. Convert these new courses and their weekly schedule into the following JSON format:

{
  "effectiveFrom": "2026-11-15",
  "subjects": [
    {
      "name": "Cloud Computing",
      "acronym": "CC",
      "room": "Lab 4",
      "block": "CS Block",
      "schedule": [
        {
          "day": "tuesday",
          "startTime": "10:00",
          "endTime": "11:30"
        },
        {
          "day": "thursday",
          "startTime": "14:00",
          "endTime": "15:30"
        }
      ]
    }
  ]
}

Rules to follow:
- "effectiveFrom" must be the starting date in "YYYY-MM-DD" format (defaults to when the class begins).
- "day" must be lowercase: "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", or "sunday".
- "startTime" and "endTime" must strictly be in 24-hour HH:mm format (e.g. "10:00", "14:30").
- Return ONLY the raw valid JSON object with no markdown code blocks, preamble, or explanation.''';

  /// AI Prompt for Electives only
  static const String timetableAiPromptElectives = '''I have provided an elective bucket/options list with multiple course choices for elective slots. Convert them into the following JSON format:

{
  "electives": [
    {
      "name": "Professional Elective I",
      "subjects": [
        {
          "name": "Machine Learning",
          "acronym": "ML",
          "schedule": [
            {
              "day": "wednesday",
              "startTime": "11:00",
              "endTime": "12:30",
              "room": "Lab 3"
            }
          ]
        },
        {
          "name": "Information Security",
          "acronym": "IS",
          "schedule": [
            {
              "day": "wednesday",
              "startTime": "11:00",
              "endTime": "12:30",
              "room": "Room 105"
            }
          ]
        }
      ]
    }
  ]
}

Rules to follow:
- "name" of the elective slot can be "Elective 1", "Open Elective", "Track Elective A", etc.
- Each elective slot can contain one or multiple subjects.
- All subjects in the slot must have valid weekly schedules with 24-hour HH:mm times.
- Return ONLY the raw valid JSON object with no markdown code blocks, preamble, or explanation.''';

  /// Format JSON string with proper indentation
  static String formatJson(String jsonString) {
    try {
      final jsonData = jsonDecode(jsonString);
      return jsonEncode(jsonData);
    } catch (e) {
      return jsonString;
    }
  }
}

class _CsvSlotDef {
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  _CsvSlotDef({
    required this.startTime,
    required this.endTime,
  });
}
