import 'package:flutter/material.dart';
import '../attendance/attendance_model.dart';
import '../subject/subject_model.dart';

/// Enum to represent the state of each day in the calendar
enum DayState {
  noClasses,
  classesNotMarked,
  classesMarked,
  holiday,
  attendedFullDay,
  bunkedFullDay,
  futureClasses,
}

/// Class to represent the state and information of a calendar day
class CalendarDayInfo {
  final DateTime date;
  final DayState state;
  final int classesCount;
  final int markedClasses;
  final List<Subject> subjectsWithClassesToday;
  final List<Attendance> attendanceRecordsToday;

  CalendarDayInfo({
    required this.date,
    required this.state,
    required this.classesCount,
    required this.markedClasses,
    required this.subjectsWithClassesToday,
    required this.attendanceRecordsToday,
  });
}

/// Utility class for calendar-related calculations
class CalendarUtils {
  /// Get the state of a specific day
  static CalendarDayInfo getDayState({
    required DateTime date,
    required List<Subject> subjects,
    required List<Attendance> attendanceRecords,
  }) {
    // Check if the date is in the future
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final isFuture = date.isAfter(todayDate);

    // Get all subjects with classes on this day
    final dayOfWeek = DayOfWeek.values[date.weekday - 1];
    var subjectsWithClassesToday = subjects
        .where((subject) => subject.schedule.any((slot) => slot.day == dayOfWeek))
        .toList();

    final totalClassesCount = subjectsWithClassesToday.fold<int>(
      0,
      (sum, subject) =>
        sum + subject.schedule.where((slot) => slot.day == dayOfWeek).length,
    );
    
    // Sort subjects by their start time
    subjectsWithClassesToday.sort((a, b) {
      final timeSlotA = getTimeSlotForDate(a, date);
      final timeSlotB = getTimeSlotForDate(b, date);
      if (timeSlotA == null || timeSlotB == null) return 0;
      return timeSlotA.startTime.hour.compareTo(timeSlotB.startTime.hour) == 0
          ? timeSlotA.startTime.minute.compareTo(timeSlotB.startTime.minute)
          : timeSlotA.startTime.hour.compareTo(timeSlotB.startTime.hour);
    });

    // If it's a future date with classes, mark as futureClasses
    if (isFuture && subjectsWithClassesToday.isNotEmpty) {
      return CalendarDayInfo(
        date: date,
        state: DayState.futureClasses,
        classesCount: totalClassesCount,
        markedClasses: 0,
        subjectsWithClassesToday: subjectsWithClassesToday,
        attendanceRecordsToday: [],
      );
    }

    // Get all attendance records for this day
    final attendanceRecordsToday = attendanceRecords
        .where((record) => isSameDay(record.date, date))
        .toList();

    final markedRecordsToday = attendanceRecordsToday.where((record) {
      final subject = subjectsWithClassesToday
          .where((s) => s.id == record.subjectId)
          .cast<Subject?>()
          .firstWhere((s) => s != null, orElse: () => null);
      if (subject == null) return false;

      final slotKey = record.slotKey ?? '';
      if (slotKey.isEmpty) {
        return true;
      }

      return subject.schedule.any(
        (slot) => slot.day == dayOfWeek && slot.slotKey == slotKey,
      );
    }).toList();

    final markedCount = markedRecordsToday.length;

    // Check if it's a holiday (all scheduled classes are cancelled)
    final isHoliday = totalClassesCount > 0 &&
        markedCount == totalClassesCount &&
        markedRecordsToday.every((record) => record.status == AttendanceStatus.cancelled);

    if (isHoliday) {
      return CalendarDayInfo(
        date: date,
        state: DayState.holiday,
        classesCount: totalClassesCount,
        markedClasses: markedCount,
        subjectsWithClassesToday: subjectsWithClassesToday,
        attendanceRecordsToday: attendanceRecordsToday,
      );
    }

    // If no classes scheduled for this day
    if (subjectsWithClassesToday.isEmpty) {
      return CalendarDayInfo(
        date: date,
        state: DayState.noClasses,
        classesCount: 0,
        markedClasses: 0,
        subjectsWithClassesToday: [],
        attendanceRecordsToday: attendanceRecordsToday,
      );
    }

    // Calculate how many classes are marked and what status they have
    final attendedCount = markedRecordsToday
        .where((record) => record.status == AttendanceStatus.attended)
        .length;
    final absentCount = markedRecordsToday
        .where((record) => record.status == AttendanceStatus.absent)
        .length;

    // Check if all classes are marked
    final allMarked = markedCount == totalClassesCount;

    if (!allMarked) {
      return CalendarDayInfo(
        date: date,
        state: DayState.classesNotMarked,
        classesCount: totalClassesCount,
        markedClasses: markedCount,
        subjectsWithClassesToday: subjectsWithClassesToday,
        attendanceRecordsToday: attendanceRecordsToday,
      );
    }

    // All classes are marked
    if (attendedCount == totalClassesCount) {
      return CalendarDayInfo(
        date: date,
        state: DayState.attendedFullDay,
        classesCount: totalClassesCount,
        markedClasses: markedCount,
        subjectsWithClassesToday: subjectsWithClassesToday,
        attendanceRecordsToday: attendanceRecordsToday,
      );
    }

    if (absentCount == totalClassesCount) {
      return CalendarDayInfo(
        date: date,
        state: DayState.bunkedFullDay,
        classesCount: totalClassesCount,
        markedClasses: markedCount,
        subjectsWithClassesToday: subjectsWithClassesToday,
        attendanceRecordsToday: attendanceRecordsToday,
      );
    }

    // Mixed attendance (some attended, some absent)
    if (markedCount > 0) {
      return CalendarDayInfo(
        date: date,
        state: DayState.classesMarked,
        classesCount: totalClassesCount,
        markedClasses: markedCount,
        subjectsWithClassesToday: subjectsWithClassesToday,
        attendanceRecordsToday: attendanceRecordsToday,
      );
    }

    return CalendarDayInfo(
      date: date,
      state: DayState.classesNotMarked,
      classesCount: totalClassesCount,
      markedClasses: 0,
      subjectsWithClassesToday: subjectsWithClassesToday,
      attendanceRecordsToday: attendanceRecordsToday,
    );
  }

  /// Get the color for a specific day state
  static Color getStateColor(DayState state) {
    switch (state) {
      case DayState.noClasses:
        return Colors.grey[400]!;
      case DayState.classesNotMarked:
        return Colors.orange[300]!;
      case DayState.classesMarked:
        return Colors.blue[300]!;
      case DayState.holiday:
        return Colors.purple[300]!;
      case DayState.attendedFullDay:
        return Colors.green[400]!;
      case DayState.bunkedFullDay:
        return Colors.red[400]!;
      case DayState.futureClasses:
        return Colors.indigo[300]!;
    }
  }

  /// Get the icon for a specific day state
  static IconData getStateIcon(DayState state) {
    switch (state) {
      case DayState.noClasses:
        return Icons.block;
      case DayState.classesNotMarked:
        return Icons.help_outline;
      case DayState.classesMarked:
        return Icons.check_circle_outline;
      case DayState.holiday:
        return Icons.celebration;
      case DayState.attendedFullDay:
        return Icons.done_all;
      case DayState.bunkedFullDay:
        return Icons.close;
      case DayState.futureClasses:
        return Icons.schedule;
    }
  }

  /// Get the label for a specific day state
  static String getStateLabel(DayState state) {
    switch (state) {
      case DayState.noClasses:
        return 'No Classes';
      case DayState.classesNotMarked:
        return 'Not Marked';
      case DayState.classesMarked:
        return 'Mixed';
      case DayState.holiday:
        return 'Holiday';
      case DayState.attendedFullDay:
        return 'Full Day';
      case DayState.bunkedFullDay:
        return 'Bunked';
      case DayState.futureClasses:
        return 'Upcoming';
    }
  }

  /// Get the TimeSlot for a subject on a given date
  static TimeSlot? getTimeSlotForDate(Subject subject, DateTime date) {
    final dayOfWeek = DayOfWeek.values[date.weekday - 1];
    return subject.schedule.firstWhere(
      (slot) => slot.day == dayOfWeek,
      orElse: () => null as dynamic,
    ) as TimeSlot?;
  }

  /// Helper to check if two DateTime objects are the same day
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
