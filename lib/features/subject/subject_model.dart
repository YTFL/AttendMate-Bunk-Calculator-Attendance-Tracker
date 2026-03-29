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

  bool get isSpecialClass =>
      schedule.isNotEmpty && schedule.every((slot) => slot.isSpecialClass);

  DateTime? get specialClassDate {
    if (!isSpecialClass) {
      return null;
    }
    return schedule.first.specificDate;
  }

  int getTotalScheduledClasses(DateTime startDate, DateTime endDate) {
    int total = 0;
    for (DateTime date = startDate;
        date.isBefore(endDate.add(const Duration(days: 1)));
        date = date.add(const Duration(days: 1))) {
      for (var slot in schedule) {
        if (slot.occursOnDate(date)) {
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

class ManualAttendanceOverride {
  final DateTime effectiveFrom;
  final int classesHeld;
  final int classesAttended;

  const ManualAttendanceOverride({
    required this.effectiveFrom,
    required this.classesHeld,
    required this.classesAttended,
  });

  int get classesAbsent => (classesHeld - classesAttended).clamp(0, classesHeld);
}

const String _manualOverrideSlotKeyPrefix = '__manual_override_v1__';

extension SubjectManualOverrideExtension on Subject {
  ManualAttendanceOverride? get manualAttendanceOverride {
    for (final record in attendanceRecords) {
      final slotKey = record.slotKey ?? '';
      if (!slotKey.startsWith(_manualOverrideSlotKeyPrefix)) {
        continue;
      }

      final heldMatch = RegExp(r'held=(\d+)').firstMatch(slotKey);
      final attendedMatch = RegExp(r'attended=(\d+)').firstMatch(slotKey);
      if (heldMatch == null || attendedMatch == null) {
        continue;
      }

      final held = int.tryParse(heldMatch.group(1) ?? '');
      final attended = int.tryParse(attendedMatch.group(1) ?? '');
      if (held == null || attended == null || held < 0 || attended < 0 || attended > held) {
        continue;
      }

      final normalizedDate = normalizeDate(record.date) ?? record.date;
      return ManualAttendanceOverride(
        effectiveFrom: normalizedDate,
        classesHeld: held,
        classesAttended: attended,
      );
    }

    return null;
  }

  Subject copyWithManualAttendanceOverride({
    required DateTime effectiveFrom,
    required int classesHeld,
    required int classesAttended,
  }) {
    final normalizedDate = normalizeDate(effectiveFrom) ?? effectiveFrom;
    final filtered = attendanceRecords.where((record) {
      final slotKey = record.slotKey ?? '';
      return !slotKey.startsWith(_manualOverrideSlotKeyPrefix);
    }).toList();

    filtered.add(
      Attendance(
        subjectId: id,
        date: normalizedDate,
        status: AttendanceStatus.cancelled,
        slotKey:
            '$_manualOverrideSlotKeyPrefix|held=$classesHeld|attended=$classesAttended',
      ),
    );

    return copyWith(attendanceRecords: filtered);
  }
}

class TimeSlot {
  final DayOfWeek day;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final DateTime? specificDate;
  final DateTime? effectiveFrom;
  final DateTime? effectiveUntil;

  TimeSlot({
    required this.day,
    required this.startTime,
    required this.endTime,
    this.specificDate,
    this.effectiveFrom,
    this.effectiveUntil,
  });

  factory TimeSlot.fromJson(Map<String, dynamic> json) {
    final parsedSpecificDate = json['specificDate'] != null
        ? DateTime.parse(json['specificDate'] as String)
        : null;
    final normalizedDate = normalizeDate(parsedSpecificDate);
    final parsedEffectiveFrom = json['effectiveFrom'] != null
        ? DateTime.parse(json['effectiveFrom'] as String)
        : null;
    final parsedEffectiveUntil = json['effectiveUntil'] != null
        ? DateTime.parse(json['effectiveUntil'] as String)
        : null;

    return TimeSlot(
      day: DayOfWeek.values[json['day'] as int],
      startTime: TimeOfDay(hour: json['startTime']['hour'], minute: json['startTime']['minute']),
      endTime: TimeOfDay(hour: json['endTime']['hour'], minute: json['endTime']['minute']),
      specificDate: normalizedDate,
      effectiveFrom: normalizeDate(parsedEffectiveFrom),
      effectiveUntil: normalizeDate(parsedEffectiveUntil),
    );
  }

  Map<String, dynamic> toJson() => {
        'day': day.index,
        'startTime': {'hour': startTime.hour, 'minute': startTime.minute},
        'endTime': {'hour': endTime.hour, 'minute': endTime.minute},
        if (specificDate != null) 'specificDate': specificDate!.toIso8601String(),
        if (effectiveFrom != null) 'effectiveFrom': effectiveFrom!.toIso8601String(),
        if (effectiveUntil != null) 'effectiveUntil': effectiveUntil!.toIso8601String(),
      };

  TimeSlot copyWith({
    DayOfWeek? day,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    DateTime? specificDate,
    DateTime? effectiveFrom,
    DateTime? effectiveUntil,
    bool clearSpecificDate = false,
    bool clearEffectiveFrom = false,
    bool clearEffectiveUntil = false,
  }) {
    return TimeSlot(
      day: day ?? this.day,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      specificDate: clearSpecificDate
          ? null
          : normalizeDate(specificDate ?? this.specificDate),
      effectiveFrom: clearEffectiveFrom
          ? null
          : normalizeDate(effectiveFrom ?? this.effectiveFrom),
      effectiveUntil: clearEffectiveUntil
          ? null
          : normalizeDate(effectiveUntil ?? this.effectiveUntil),
    );
  }

  String get slotKey {
    final datePrefix = specificDate == null
        ? ''
        : '${specificDate!.year.toString().padLeft(4, '0')}-${specificDate!.month.toString().padLeft(2, '0')}-${specificDate!.day.toString().padLeft(2, '0')}-';
    return '$datePrefix${day.index}-${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}-${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
  }

  bool get isSpecialClass => specificDate != null;

  bool occursOnDate(DateTime date) {
    final normalizedDate = normalizeDate(date) ?? date;
    if (specificDate != null) {
      return isSameDay(specificDate!, normalizedDate);
    }
    if (!_isWithinEffectiveRange(normalizedDate)) {
      return false;
    }
    return normalizedDate.weekday == day.index + 1;
  }

  bool _isWithinEffectiveRange(DateTime date) {
    final from = effectiveFrom;
    final until = effectiveUntil;

    if (from != null && date.isBefore(from)) {
      return false;
    }
    if (until != null && date.isAfter(until)) {
      return false;
    }
    return true;
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

DateTime? normalizeDate(DateTime? date) {
  if (date == null) {
    return null;
  }
  return DateTime(date.year, date.month, date.day);
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
