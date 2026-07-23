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
  final String? locationId;
  final String? room;
  final String? block;

  Subject({
    String? id,
    required this.name,
    this.acronym,
    required this.color,
    required this.schedule,
    this.targetAttendance = 75,
    this.attendanceRecords = const [],
    this.locationId,
    this.room,
    this.block,
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
      locationId: json['locationId'] as String?,
      room: json['room'] as String?,
      block: json['block'] as String?,
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
        'locationId': locationId,
        'room': room,
        'block': block,
      };

  Subject copyWith({
    String? id,
    String? name,
    String? acronym,
    Color? color,
    List<TimeSlot>? schedule,
    int? targetAttendance,
    List<Attendance>? attendanceRecords,
    String? Function()? locationId,
    String? Function()? room,
    String? Function()? block,
  }) {
    return Subject(
      id: id ?? this.id,
      name: name ?? this.name,
      acronym: acronym ?? this.acronym,
      color: color ?? this.color,
      schedule: schedule ?? this.schedule,
      targetAttendance: targetAttendance ?? this.targetAttendance,
      attendanceRecords: attendanceRecords ?? this.attendanceRecords,
      locationId: locationId != null ? locationId() : this.locationId,
      room: room != null ? room() : this.room,
      block: block != null ? block() : this.block,
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
    for (final slot in schedule) {
      total += slot.getOccurrences(startDate, endDate);
    }
    return total;
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
  final String? locationId;
  final String? room;
  final String? block;

  TimeSlot({
    required this.day,
    required this.startTime,
    required this.endTime,
    this.specificDate,
    this.effectiveFrom,
    this.effectiveUntil,
    this.locationId,
    this.room,
    this.block,
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
      locationId: json['locationId'] as String?,
      room: json['room'] as String?,
      block: json['block'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'day': day.index,
        'startTime': {'hour': startTime.hour, 'minute': startTime.minute},
        'endTime': {'hour': endTime.hour, 'minute': endTime.minute},
        if (specificDate != null) 'specificDate': specificDate!.toIso8601String(),
        if (effectiveFrom != null) 'effectiveFrom': effectiveFrom!.toIso8601String(),
        if (effectiveUntil != null) 'effectiveUntil': effectiveUntil!.toIso8601String(),
        if (locationId != null) 'locationId': locationId,
        if (room != null) 'room': room,
        if (block != null) 'block': block,
      };

  TimeSlot copyWith({
    DayOfWeek? day,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    DateTime? specificDate,
    DateTime? effectiveFrom,
    DateTime? effectiveUntil,
    String? locationId,
    String? room,
    String? block,
    bool clearSpecificDate = false,
    bool clearEffectiveFrom = false,
    bool clearEffectiveUntil = false,
    bool clearLocation = false,
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
      locationId: clearLocation ? null : (locationId ?? this.locationId),
      room: clearLocation ? null : (room ?? this.room),
      block: clearLocation ? null : (block ?? this.block),
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

  int getOccurrences(DateTime startDate, DateTime endDate) {
    final s = normalizeDate(startDate) ?? startDate;
    final e = normalizeDate(endDate) ?? endDate;
    if (s.isAfter(e)) {
      return 0;
    }

    if (specificDate != null) {
      final spec = specificDate!;
      if ((spec.isAfter(s) || isSameDay(spec, s)) && (spec.isBefore(e) || isSameDay(spec, e))) {
        return 1;
      }
      return 0;
    }

    // Determine the effective range overlap
    var calcStart = s;
    if (effectiveFrom != null && effectiveFrom!.isAfter(calcStart)) {
      calcStart = effectiveFrom!;
    }

    var calcEnd = e;
    if (effectiveUntil != null && effectiveUntil!.isBefore(calcEnd)) {
      calcEnd = effectiveUntil!;
    }

    if (calcStart.isAfter(calcEnd)) {
      return 0;
    }

    // Use UTC for difference calculation to avoid DST transitions
    final calcStartUtc = DateTime.utc(calcStart.year, calcStart.month, calcStart.day);
    final calcEndUtc = DateTime.utc(calcEnd.year, calcEnd.month, calcEnd.day);

    final targetWeekday = day.index + 1;
    final days = calcEndUtc.difference(calcStartUtc).inDays + 1;
    int count = days ~/ 7;
    final rem = days % 7;

    if (rem > 0) {
      int current = calcStartUtc.weekday;
      for (int i = 0; i < rem; i++) {
        if (current == targetWeekday) {
          count++;
          break;
        }
        current = current == 7 ? 1 : current + 1;
      }
    }
    return count;
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
