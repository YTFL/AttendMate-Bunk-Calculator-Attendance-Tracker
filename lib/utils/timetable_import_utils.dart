import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';

import '../features/subject/subject_model.dart';

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

  /// Parse JSON string and return list of subjects
  static List<Subject> parseJsonToSubjects(String jsonString, Set<Color> usedColors) {
    try {
      final jsonData = jsonDecode(jsonString);
      final List<Subject> subjects = [];
      Set<Color> currentUsedColors = Set.from(usedColors);

      // Check if it's a subjects array or an object with subjects key
      List<dynamic> subjectsList = [];
      
      if (jsonData is List) {
        subjectsList = jsonData;
      } else if (jsonData is Map && jsonData.containsKey('subjects')) {
        subjectsList = jsonData['subjects'] as List<dynamic>;
      } else {
        throw Exception('Invalid JSON format. Expected an array of subjects or an object with a "subjects" key.');
      }

      for (var subjectData in subjectsList) {
        try {
          final subject = _parseSubjectFromJson(subjectData, currentUsedColors);
          subjects.add(subject);
          currentUsedColors.add(subject.color);
        } catch (e) {
          // Continue parsing other subjects even if one fails
          continue;
        }
      }

      if (subjects.isEmpty) {
        throw Exception('No valid subjects found in the JSON.');
      }

      return subjects;
    } catch (e) {
      throw Exception('Error parsing JSON: ${e.toString()}');
    }
  }

  /// Parse individual subject from JSON
  static Subject _parseSubjectFromJson(dynamic subjectData, Set<Color> usedColors) {
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
        // Parse hex color string like "0xFFFF0000"
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

    // Parse schedule
    final scheduleData = subjectData['schedule'];
    if (scheduleData == null || scheduleData is! List) {
      throw Exception('Schedule is required and must be an array for subject "$name"');
    }

    final List<TimeSlot> schedule = [];
    for (var slotData in scheduleData) {
      try {
        final slot = _parseTimeSlot(slotData);
        schedule.add(slot);
      } catch (e) {
        // Continue parsing other slots
        continue;
      }
    }

    if (schedule.isEmpty) {
      throw Exception('Subject "$name" must have at least one time slot');
    }

    final targetAttendance = subjectData['targetAttendance'] as int? ?? 75;

    return Subject(
      name: name.trim(),
      acronym: (acronym?.trim().isEmpty ?? true) ? null : acronym?.trim(),
      color: color,
      schedule: schedule,
      targetAttendance: targetAttendance,
    );
  }

  /// Parse individual time slot from JSON
  static TimeSlot _parseTimeSlot(dynamic slotData) {
    if (slotData is! Map) {
      throw Exception('Time slot must be an object');
    }

    final dayString = slotData['day'] as String?;
    if (dayString == null || dayString.isEmpty) {
      throw Exception('Day is required for time slot');
    }

    final day = _parseDayOfWeek(dayString);
    if (day == null) {
      throw Exception('Invalid day: "$dayString". Use: monday, tuesday, wednesday, thursday, friday, saturday, sunday');
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

    return TimeSlot(
      day: day,
      startTime: startTime,
      endTime: endTime,
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

  /// Generate template JSON format
  static String generateTemplateJson() {
    final template = {
      "subjects": [
        {
          "name": "Mathematics",
          "acronym": "MTH",
          "schedule": [
            {
              "day": "monday",
              "startTime": "09:00",
              "endTime": "10:30"
            },
            {
              "day": "wednesday",
              "startTime": "14:00",
              "endTime": "15:30"
            },
            {
              "day": "friday",
              "startTime": "10:00",
              "endTime": "11:30"
            }
          ]
        },
        {
          "name": "Physics",
          "acronym": "PHY",
          "schedule": [
            {
              "day": "tuesday",
              "startTime": "09:00",
              "endTime": "10:30"
            },
            {
              "day": "thursday",
              "startTime": "14:00",
              "endTime": "15:30"
            }
          ]
        }
      ]
    };

    return jsonEncode(template);
  }

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
