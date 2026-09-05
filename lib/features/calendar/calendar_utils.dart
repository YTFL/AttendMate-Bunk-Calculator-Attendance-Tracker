import 'package:flutter/material.dart';
import '../attendance/attendance_model.dart';
import '../planner/planned_leave_model.dart';
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
  plannedLeave,
  locked,
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
  /// Helper to check if a subject's attendance on a given date is locked by manual baseline override
  static bool isLockedByManualOverride(Subject subject, DateTime date) {
    final manualOverride = subject.manualAttendanceOverride;
    if (manualOverride == null) {
      return false;
    }

    final normalizedDate = DateTime(date.year, date.month, date.day);
    final effectiveFrom = manualOverride.effectiveFrom;
    final normalizedEffectiveFrom =
        DateTime(effectiveFrom.year, effectiveFrom.month, effectiveFrom.day);

    return normalizedDate.isBefore(normalizedEffectiveFrom);
  }

  /// Get the state of a specific day
  static CalendarDayInfo getDayState({
    required DateTime date,
    required List<Subject> subjects,
    required List<Attendance> attendanceRecords,
    Map<DateTime, List<Attendance>>? indexedRecords,
    List<PlannedLeave> plannedLeaves = const [],
  }) {
    // Check if the date is in the future
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final isFuture = normalizedDate.isAfter(todayDate);

    // Get all subjects with classes on this day
    var subjectsWithClassesToday = subjects
      .where((subject) => subject.schedule.any((slot) => slot.occursOnDate(date)))
        .toList();

    final totalClassesCount = subjectsWithClassesToday.fold<int>(
      0,
      (sum, subject) =>
      sum + subject.schedule.where((slot) => slot.occursOnDate(date)).length,
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

    // If no classes scheduled for this day
    if (subjectsWithClassesToday.isEmpty || totalClassesCount == 0) {
      return CalendarDayInfo(
        date: date,
        state: DayState.noClasses,
        classesCount: 0,
        markedClasses: 0,
        subjectsWithClassesToday: [],
        attendanceRecordsToday: [],
      );
    }

    // Get all attendance records for this day
    final rawAttendanceToday = indexedRecords != null
        ? (indexedRecords[normalizedDate] ?? [])
        : attendanceRecords.where((record) => isSameDay(record.date, date)).toList();

    final attendanceRecordsToday = List<Attendance>.from(rawAttendanceToday);

    // Check for planned leave auto-marking for unrecorded slots
    for (final subject in subjectsWithClassesToday) {
      for (final slot in subject.schedule.where((s) => s.occursOnDate(date))) {
        final slotStart = DateTime(date.year, date.month, date.day, slot.startTime.hour, slot.startTime.minute);
        final slotEnd = DateTime(date.year, date.month, date.day, slot.endTime.hour, slot.endTime.minute);

        final isCoveredByLeave = plannedLeaves.any((leave) =>
            (leave.affectedSubjectIds.isEmpty || leave.affectedSubjectIds.contains(subject.id)) &&
            slotStart.isBefore(leave.endDate) &&
            slotEnd.isAfter(leave.startDate));

        if (isCoveredByLeave) {
          final hasExplicitRecord = attendanceRecordsToday.any((r) =>
              r.subjectId == subject.id &&
              (r.slotKey == null || r.slotKey == slot.slotKey || r.slotKey!.isEmpty));

          if (!hasExplicitRecord) {
            attendanceRecordsToday.add(Attendance(
              subjectId: subject.id,
              date: date,
              status: AttendanceStatus.absent,
              slotKey: slot.slotKey,
            ));
          }
        }
      }
    }

    int lockedCount = 0;
    int attendedCount = 0;
    int absentCount = 0;
    int cancelledCount = 0;
    int unmarkedCount = 0;
    int leaveAbsentCount = 0;

    for (final subject in subjectsWithClassesToday) {
      final isLocked = isLockedByManualOverride(subject, date);
      for (final slot in subject.schedule.where((s) => s.occursOnDate(date))) {
        if (isLocked) {
          lockedCount++;
        } else {
          final record = attendanceRecordsToday
              .where((r) =>
                  r.subjectId == subject.id &&
                  (r.slotKey == null ||
                      r.slotKey == slot.slotKey ||
                      (r.slotKey?.isEmpty ?? true)))
              .cast<Attendance?>()
              .firstWhere((r) => r != null, orElse: () => null);

          if (record != null) {
            if (record.status == AttendanceStatus.attended) {
              attendedCount++;
            } else if (record.status == AttendanceStatus.absent) {
              absentCount++;
              final slotStart = DateTime(date.year, date.month, date.day, slot.startTime.hour, slot.startTime.minute);
              final slotEnd = DateTime(date.year, date.month, date.day, slot.endTime.hour, slot.endTime.minute);
              final isCoveredByLeave = plannedLeaves.any((leave) =>
                  (leave.affectedSubjectIds.isEmpty || leave.affectedSubjectIds.contains(subject.id)) &&
                  slotStart.isBefore(leave.endDate) &&
                  slotEnd.isAfter(leave.startDate));
              if (isCoveredByLeave) {
                leaveAbsentCount++;
              }
            } else if (record.status == AttendanceStatus.cancelled) {
              cancelledCount++;
            }
          } else {
            unmarkedCount++;
          }
        }
      }
    }

    final accountedCount = lockedCount + attendedCount + absentCount + cancelledCount;

    DayState dayState;

    if (isFuture) {
      if (cancelledCount == totalClassesCount) {
        dayState = DayState.holiday;
      } else if (lockedCount == totalClassesCount) {
        dayState = DayState.locked;
      } else if (unmarkedCount == 0) {
        if (attendedCount == totalClassesCount) {
          dayState = DayState.attendedFullDay;
        } else if (absentCount == totalClassesCount) {
          dayState = (leaveAbsentCount == totalClassesCount)
              ? DayState.plannedLeave
              : DayState.bunkedFullDay;
        } else {
          dayState = DayState.classesMarked;
        }
      } else if (attendedCount > 0 || absentCount > 0 || cancelledCount > 0) {
        dayState = DayState.classesMarked;
      } else {
        dayState = DayState.futureClasses;
      }
    } else {
      if (unmarkedCount > 0) {
        dayState = DayState.classesNotMarked;
      } else if (lockedCount == totalClassesCount) {
        dayState = DayState.locked;
      } else if (cancelledCount == totalClassesCount) {
        dayState = DayState.holiday;
      } else if (attendedCount == totalClassesCount) {
        dayState = DayState.attendedFullDay;
      } else if (absentCount == totalClassesCount) {
        dayState = (leaveAbsentCount == totalClassesCount)
            ? DayState.plannedLeave
            : DayState.bunkedFullDay;
      } else {
        dayState = DayState.classesMarked;
      }
    }

    return CalendarDayInfo(
      date: date,
      state: dayState,
      classesCount: totalClassesCount,
      markedClasses: accountedCount,
      subjectsWithClassesToday: subjectsWithClassesToday,
      attendanceRecordsToday: attendanceRecordsToday,
    );
  }

  /// Get the color for a specific day state
  static Color getStateColor(DayState state) {
    switch (state) {
      case DayState.noClasses:
        return const Color(0xFF9E9E9E);
      case DayState.classesNotMarked:
        return const Color(0xFFFFA726);
      case DayState.classesMarked:
        return const Color(0xFF42A5F5);
      case DayState.holiday:
        return const Color(0xFFAB47BC);
      case DayState.attendedFullDay:
        return const Color(0xFF4CAF50);
      case DayState.bunkedFullDay:
        return const Color(0xFFEF5350);
      case DayState.futureClasses:
        return const Color(0xFF7E57C2);
      case DayState.plannedLeave:
        return const Color(0xFFFF7043);
      case DayState.locked:
        return const Color(0xFF607D8B);
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
      case DayState.plannedLeave:
        return Icons.event_busy_rounded;
      case DayState.locked:
        return Icons.lock_outline;
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
      case DayState.plannedLeave:
        return 'Planned Leave';
      case DayState.locked:
        return 'Locked';
    }
  }

  /// Get the TimeSlot for a subject on a given date
  static TimeSlot? getTimeSlotForDate(Subject subject, DateTime date) {
    return subject.schedule.firstWhere(
      (slot) => slot.occursOnDate(date),
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
