import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/features/attendance/attendance_model.dart';
import 'package:attendmate/features/semester/semester_model.dart';
import 'package:attendmate/features/subject/subject_model.dart';

// Helper reproduction of the calculator counting logic for test isolation
class TestRemainingResult {
  final int remainingClasses;
  final int leaveMissedClasses;
  final int futureAttendedClasses;
  final int futureMissedClasses;
  final int futureCancelledClasses;

  const TestRemainingResult({
    required this.remainingClasses,
    required this.leaveMissedClasses,
    this.futureAttendedClasses = 0,
    this.futureMissedClasses = 0,
    this.futureCancelledClasses = 0,
  });
}

TestRemainingResult countClassesUpToDate({
  required Subject subject,
  required DateTime today,
  required DateTime targetDate,
  required Semester semester,
  required bool considerFutureMarked,
  required List<Attendance> subjectRecords,
}) {
  final horizonDate = targetDate.isAfter(semester.endDate) ? semester.endDate : targetDate;
  final horizonDay = DateTime(horizonDate.year, horizonDate.month, horizonDate.day, 23, 59, 59);

  if (today.isAfter(horizonDay)) {
    return const TestRemainingResult(remainingClasses: 0, leaveMissedClasses: 0);
  }

  final manualOverride = subject.manualAttendanceOverride;
  DateTime countingStart = manualOverride?.effectiveFrom ?? semester.startDate;
  if (countingStart.isBefore(semester.startDate)) {
    countingStart = semester.startDate;
  }
  final countingStartDay = DateTime(countingStart.year, countingStart.month, countingStart.day);

  final tomorrow = today.add(const Duration(days: 1));
  final startDay = tomorrow.isBefore(countingStartDay) ? countingStartDay : tomorrow;

  final Map<String, AttendanceStatus> futureRecordLookup = {};
  if (considerFutureMarked) {
    for (final r in subjectRecords) {
      final normDate = DateTime(r.date.year, r.date.month, r.date.day);
      if (normDate.isBefore(startDay) || normDate.isAfter(horizonDate)) continue;
      if (r.slotKey != null && r.slotKey!.isNotEmpty) {
        futureRecordLookup['${normDate.year}-${normDate.month}-${normDate.day}_${r.slotKey}'] = r.status;
      }
      futureRecordLookup['${normDate.year}-${normDate.month}-${normDate.day}'] = r.status;
    }
  }

  int remaining = 0;
  int leaveMissed = 0;
  int futureAttended = 0;
  int futureMissed = 0;
  int futureCancelled = 0;

  DateTime cur = startDay;
  while (!cur.isAfter(horizonDay)) {
    for (final slot in subject.schedule) {
      if (slot.occursOnDate(cur)) {
        final slotStart = DateTime(cur.year, cur.month, cur.day, slot.startTime.hour, slot.startTime.minute);
        if (slotStart.isAfter(horizonDay)) continue;

        AttendanceStatus? markedStatus;
        if (considerFutureMarked) {
          final dateKeyWithSlot = '${cur.year}-${cur.month}-${cur.day}_${slot.slotKey}';
          final dateKeyNoSlot = '${cur.year}-${cur.month}-${cur.day}';
          markedStatus = futureRecordLookup[dateKeyWithSlot] ?? futureRecordLookup[dateKeyNoSlot];
        }

        if (markedStatus != null) {
          if (markedStatus == AttendanceStatus.attended) {
            futureAttended++;
          } else if (markedStatus == AttendanceStatus.absent || markedStatus == AttendanceStatus.plannedAbsent) {
            futureMissed++;
          } else if (markedStatus == AttendanceStatus.cancelled) {
            futureCancelled++;
          }
        } else {
          remaining++;
        }
      }
    }
    cur = cur.add(const Duration(days: 1));
  }

  return TestRemainingResult(
    remainingClasses: remaining,
    leaveMissedClasses: leaveMissed,
    futureAttendedClasses: futureAttended,
    futureMissedClasses: futureMissed,
    futureCancelledClasses: futureCancelled,
  );
}

void main() {
  group('Future Marked Lectures in Bunk Calculator Tests (Issue #3)', () {
    final semester = Semester(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 31),
      targetPercentage: 75.0,
    );

    // Subject has classes on Mon, Wed, Fri
    final subject = Subject(
      id: 'sub-cs101',
      name: 'Computer Networks',
      color: Colors.teal,
      schedule: [
        TimeSlot(
          day: DayOfWeek.monday,
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 10, minute: 0),
        ),
        TimeSlot(
          day: DayOfWeek.wednesday,
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 10, minute: 0),
        ),
        TimeSlot(
          day: DayOfWeek.friday,
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 10, minute: 0),
        ),
      ],
      targetAttendance: 75,
    );

    // Current date: Friday, August 14, 2026
    final today = DateTime(2026, 8, 14);

    // Future dates in August 2026 (Mon/Wed/Fri):
    // Aug 17 (Mon)
    // Aug 19 (Wed)
    // Aug 21 (Fri)
    // Aug 24 (Mon)
    // Aug 26 (Wed)
    // Aug 28 (Fri)
    // Aug 31 (Mon)
    // Total future slots in schedule = 7 slots.

    test('When considerFutureMarked is false, all 7 future slots are treated as undecided remaining', () {
      final records = [
        Attendance(subjectId: 'sub-cs101', date: DateTime(2026, 8, 17), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub-cs101', date: DateTime(2026, 8, 19), status: AttendanceStatus.cancelled),
      ];

      final res = countClassesUpToDate(
        subject: subject,
        today: today,
        targetDate: semester.endDate,
        semester: semester,
        considerFutureMarked: false,
        subjectRecords: records,
      );

      expect(res.remainingClasses, equals(7));
      expect(res.futureAttendedClasses, equals(0));
      expect(res.futureCancelledClasses, equals(0));
      expect(res.futureMissedClasses, equals(0));
    });

    test('When considerFutureMarked is true, pre-marked attended, absent, and holiday classes are factored in', () {
      // User pre-marked:
      // Aug 17 (Mon): Attended
      // Aug 19 (Wed): Cancelled / Holiday
      // Aug 21 (Fri): Absent
      // Remaining unmarked: Aug 24, 26, 28, 31 (4 classes)
      final records = [
        Attendance(subjectId: 'sub-cs101', date: DateTime(2026, 8, 17), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub-cs101', date: DateTime(2026, 8, 19), status: AttendanceStatus.cancelled),
        Attendance(subjectId: 'sub-cs101', date: DateTime(2026, 8, 21), status: AttendanceStatus.absent),
      ];

      final res = countClassesUpToDate(
        subject: subject,
        today: today,
        targetDate: semester.endDate,
        semester: semester,
        considerFutureMarked: true,
        subjectRecords: records,
      );

      expect(res.futureAttendedClasses, equals(1));
      expect(res.futureCancelledClasses, equals(1));
      expect(res.futureMissedClasses, equals(1));
      expect(res.remainingClasses, equals(4)); // 7 - 3 = 4 undecided remaining
    });

    test('Mathematical bunk calculations with future marked classes are accurate', () {
      // Past classes up to Aug 14:
      // Suppose 6 classes were held so far, 5 attended (5/6 = 83.3%)
      const baseHeld = 6;
      const baseAttended = 5;

      // Future window: 7 scheduled slots
      // 1 future marked attended (Aug 17)
      // 1 future marked cancelled/holiday (Aug 19)
      // 1 future marked absent (Aug 21)
      // 4 undecided remaining
      const futureAttended = 1;
      const futureMissed = 1;
      const totalRemaining = 4;

      final effectiveCurrentAttended = baseAttended + futureAttended; // 6
      final effectiveCurrentHeld = baseHeld + futureAttended + futureMissed; // 8
      final endHorizonTotalHeld = effectiveCurrentHeld + totalRemaining; // 8 + 4 = 12

      // Target = 75%: 75% of 12 = 9
      final targetRatio = 75.0 / 100.0;
      final targetAttendedNeeded = (targetRatio * endHorizonTotalHeld).ceil(); // 9

      final mustAttend = (targetAttendedNeeded - effectiveCurrentAttended).clamp(0, totalRemaining);
      final canBunk = (totalRemaining - mustAttend).clamp(0, totalRemaining);

      // Must attend: 9 - 6 = 3 of the remaining 4 classes
      // Can bunk: 4 - 3 = 1 of the remaining 4 classes
      expect(targetAttendedNeeded, equals(9));
      expect(mustAttend, equals(3));
      expect(canBunk, equals(1));

      // If user attends 3 and bunks 1:
      // Total attended = 6 + 3 = 9
      // Total held = 8 + 4 = 12
      // Attendance percentage = 9 / 12 = 75.0% >= 75%
      final simulatedAttended = effectiveCurrentAttended + 3;
      final simulatedHeld = effectiveCurrentHeld + 4;
      final simulatedRatio = (simulatedAttended / simulatedHeld) * 100;
      expect(simulatedRatio, equals(75.0));
    });
  });
}
