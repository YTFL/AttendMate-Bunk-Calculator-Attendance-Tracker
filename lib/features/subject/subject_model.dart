import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../attendance/attendance_model.dart';
import '../../utils/string_extension.dart';
import '../../utils/time_format_utils.dart';

const Uuid uuid = Uuid();

class Subject {
  final String id;
  final String name;
  final String? acronym;
  final Color color;
  final List<TimeSlot> schedule;
  final int targetAttendance;
  final List<Attendance> attendanceRecords;

  Subject({
    String? id,
    required this.name,
    this.acronym,
    required this.color,
    required this.schedule,
    this.targetAttendance = 75,
    this.attendanceRecords = const [],
  }) : id = id ?? uuid.v4();

  factory Subject.fromJson(Map<String, dynamic> json) {
    return Subject(
      id: json['id'] as String? ?? uuid.v4(),
      name: json['name'] as String,
      acronym: json['acronym'] as String?,
      color: Color(json['color'] as int),
      schedule: (json['schedule'] as List<dynamic>)
          .map((e) => TimeSlot.fromJson(e as Map<String, dynamic>))
          .toList(),
      targetAttendance: json['targetAttendance'] as int? ?? 75,
      attendanceRecords: (json['attendanceRecords'] as List<dynamic>? ?? [])
          .map((e) => Attendance.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'acronym': acronym,
        'color': color.toARGB32(),
        'schedule': schedule.map((e) => e.toJson()).toList(),
        'targetAttendance': targetAttendance,
        'attendanceRecords': attendanceRecords.map((e) => e.toJson()).toList(),
      };

  Subject copyWith({
    String? id,
    String? name,
    String? acronym,
    Color? color,
    List<TimeSlot>? schedule,
    int? targetAttendance,
    List<Attendance>? attendanceRecords,
  }) {
    return Subject(
      id: id ?? this.id,
      name: name ?? this.name,
      acronym: acronym ?? this.acronym,
      color: color ?? this.color,
      schedule: schedule ?? this.schedule,
      targetAttendance: targetAttendance ?? this.targetAttendance,
      attendanceRecords: attendanceRecords ?? this.attendanceRecords,
    );
  }

  int getTotalScheduledClasses(DateTime startDate, DateTime endDate) {
    int total = 0;
    for (DateTime date = startDate;
        date.isBefore(endDate.add(const Duration(days: 1)));
        date = date.add(const Duration(days: 1))) {
      for (var slot in schedule) {
        if (date.weekday == slot.day.index + 1) {
          total++;
        }
      }
    }
    return total;
  }

  Map<String, int> getMarkedAttendanceCounts() {
    int attended = 0;
    int absent = 0;
    for (var record in attendanceRecords) {
      if (record.status == AttendanceStatus.attended) {
        attended++;
      } else if (record.status == AttendanceStatus.absent) {
        absent++;
      }
    }
    return {
      'attended': attended,
      'absent': absent,
    };
  }
}

class TimeSlot {
  final DayOfWeek day;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  TimeSlot({
    required this.day,
    required this.startTime,
    required this.endTime,
  });

  factory TimeSlot.fromJson(Map<String, dynamic> json) {
    return TimeSlot(
      day: DayOfWeek.values[json['day'] as int],
      startTime: TimeOfDay(hour: json['startTime']['hour'], minute: json['startTime']['minute']),
      endTime: TimeOfDay(hour: json['endTime']['hour'], minute: json['endTime']['minute']),
    );
  }

  Map<String, dynamic> toJson() => {
        'day': day.index,
        'startTime': {'hour': startTime.hour, 'minute': startTime.minute},
        'endTime': {'hour': endTime.hour, 'minute': endTime.minute},
      };

  String get slotKey {
    return '${day.index}-${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}-${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
  }

  /// Format the time slot as a time range string based on the specified format
  /// 
  /// [timeFormat] - The desired time format (12hr or 24hr)
  /// Returns a formatted string like "14:30 - 15:30" or "02:30 PM - 03:30 PM"
  String formatTimeRange(TimeFormat timeFormat) {
    return TimeFormatUtils.formatTimeRange(startTime, endTime, timeFormat);
  }

  /// Format only the start time
  String formatStartTime(TimeFormat timeFormat) {
    return TimeFormatUtils.formatTime(startTime, timeFormat);
  }

  /// Format only the end time
  String formatEndTime(TimeFormat timeFormat) {
    return TimeFormatUtils.formatTime(endTime, timeFormat);
  }
}

// Using an enum for days of the week for type safety
enum DayOfWeek {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday,
}

extension DayOfWeekExtension on DayOfWeek {
  String get name => toString().split('.').last;
}

// Helper to check if two DateTime objects are the same day
bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

extension SubjectSearchExtension on Subject {
  bool matchesSearchQuery(String query) {
    final normalizedQuery = _normalizeSearchToken(query);
    if (normalizedQuery.isEmpty) {
      return true;
    }

    final lowerQuery = query.trim().toLowerCase();
    final normalizedName = _normalizeSearchToken(name);

    if (name.toLowerCase().contains(lowerQuery) || normalizedName.contains(normalizedQuery)) {
      return true;
    }

    final explicitAcronym = acronym?.trim() ?? '';
    if (explicitAcronym.isNotEmpty) {
      final normalizedExplicitAcronym = _normalizeSearchToken(explicitAcronym);
      if (explicitAcronym.toLowerCase().contains(lowerQuery) ||
          normalizedExplicitAcronym.contains(normalizedQuery)) {
        return true;
      }
    }

    final generatedAcronym = name.acronymFromName();
    return _normalizeSearchToken(generatedAcronym).contains(normalizedQuery);
  }
}

String _normalizeSearchToken(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
