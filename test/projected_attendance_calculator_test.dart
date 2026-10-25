import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/features/attendance/attendance_model.dart';
import 'package:attendmate/features/planner/planned_leave_model.dart';
import 'package:attendmate/features/planner/projected_attendance_calculator.dart';
import 'package:attendmate/features/semester/semester_model.dart';
import 'package:attendmate/features/subject/subject_model.dart';

void main() {
  group('ProjectedAttendanceCalculator Tests', () {
    final semester = Semester(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 31),
      targetPercentage: 75.0,
    );

    // Subject on Mon, Wed, Fri at 10:00 AM
    final subject = Subject(
      id: 'sub-1',
      name: 'Mathematics',
      color: Colors.blue,
      schedule: [
        TimeSlot(
          day: DayOfWeek.monday,
          startTime: const TimeOfDay(hour: 10, minute: 0),
          endTime: const TimeOfDay(hour: 11, minute: 0),
        ),
        TimeSlot(
          day: DayOfWeek.wednesday,
          startTime: const TimeOfDay(hour: 10, minute: 0),
          endTime: const TimeOfDay(hour: 11, minute: 0),
        ),
        TimeSlot(
          day: DayOfWeek.friday,
          startTime: const TimeOfDay(hour: 10, minute: 0),
          endTime: const TimeOfDay(hour: 11, minute: 0),
        ),
      ],
      targetAttendance: 75,
    );


    test('Returns default when no active planned leaves exist', () {
      final projection = ProjectedAttendanceCalculator.calculateForSubject(
        subject: subject,
        attendanceRecords: [],
        semester: semester,
        plannedLeaves: [],
        now: DateTime(2026, 8, 10),
      );

      expect(projection.hasActivePlannedLeave, isFalse);
    });

    test('Assumes upcoming classes until planned holiday as present, and holiday classes as missed', () {
      // Reference time: Mon Aug 10, 2026
      // Planned leave: Mon Aug 17, 2026 to Wed Aug 19, 2026
      final leave = PlannedLeave(
        id: 'leave-1',
        name: 'Trip',
        startDate: DateTime(2026, 8, 17, 0, 0),
        endDate: DateTime(2026, 8, 19, 23, 59),
        affectedSubjectIds: ['sub-1'],
      );

      // Marked classes in past (Aug 1 to Aug 10):
      // Aug 3 (Mon): attended
      // Aug 5 (Wed): attended
      // Aug 7 (Fri): absent
      // Aug 10 (Mon): attended
      final records = [
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 3), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 5), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 7), status: AttendanceStatus.absent),
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 10), status: AttendanceStatus.attended),
      ];

      final projection = ProjectedAttendanceCalculator.calculateForSubject(
        subject: subject,
        attendanceRecords: records,
        semester: semester,
        plannedLeaves: [leave],
        now: DateTime(2026, 8, 10),
      );

      expect(projection.hasActivePlannedLeave, isTrue);

      // Classes between Aug 1 and Aug 19 (leave end):
      // Marked: Aug 3 (attended), Aug 5 (attended), Aug 7 (absent), Aug 10 (attended) -> 3 attended, 4 held
      // Upcoming before leave: Aug 12 (Wed), Aug 14 (Fri) -> 2 classes assumed present (+2 attended, +2 held)
      // During leave: Aug 17 (Mon), Aug 19 (Wed) -> 2 classes assumed missed (+0 attended, +2 held)
      // Total attended: 3 + 2 = 5
      // Total held/marked: 4 + 2 + 2 = 8
      // Expected percentage: 5 / 8 = 62.5%

      expect(projection.totalAttended, equals(5));
      expect(projection.totalMarked, equals(8));
      expect(projection.plannedMissedCount, equals(2));
      expect(projection.assumedPresentCount, equals(2));
      expect(projection.projectedPercentage, equals(62.5));
    });

    test('Respects explicitly marked classes when user actually marks them', () {
      final leave = PlannedLeave(
        id: 'leave-1',
        name: 'Trip',
        startDate: DateTime(2026, 8, 17, 0, 0),
        endDate: DateTime(2026, 8, 19, 23, 59),
        affectedSubjectIds: ['sub-1'],
      );

      // Marked classes including Aug 12 explicitly marked as ABSENT:
      final records = [
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 3), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 5), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 7), status: AttendanceStatus.absent),
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 10), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 12), status: AttendanceStatus.absent), // Explicitly marked!
      ];

      final projection = ProjectedAttendanceCalculator.calculateForSubject(
        subject: subject,
        attendanceRecords: records,
        semester: semester,
        plannedLeaves: [leave],
        now: DateTime(2026, 8, 10),
      );

      // Aug 12 is now marked absent -> 0 attended, 1 held.
      // Total attended: 3 + 1 (Aug 14 assumed present) = 4
      // Total held: 5 (marked) + 1 (Aug 14 assumed present) + 2 (leave missed) = 8
      // Expected percentage: 4 / 8 = 50.0%

      expect(projection.totalAttended, equals(4));
      expect(projection.totalMarked, equals(8));
      expect(projection.projectedPercentage, equals(50.0));
    });

    test('Calculates post-leave continuous attendance recovery correctly', () {
      final leaveEnd = DateTime(2026, 8, 19, 23, 59);

      // Projected after leave: 5 attended / 8 held (62.5%), target = 75%
      final recovery = ProjectedAttendanceCalculator.calculateClassesNeededAfterLeave(
        subjects: [subject],
        semester: semester,
        projectedAttended: 5,
        projectedMarked: 8,
        leaveEndDate: leaveEnd,
        targetPercentage: 75.0,
      );

      // Solve (5 + N)/(8 + N) >= 0.75:
      // N = 1 -> 6/9 = 66.7%
      // N = 2 -> 7/10 = 70.0%
      // N = 3 -> 8/11 = 72.7%
      // N = 4 -> 9/12 = 75.0% -> Needed = 4!
      expect(recovery.classesNeeded, equals(4));

      // Remaining classes after Aug 19 in August 2026 (Mon/Wed/Fri):
      // Aug 21 (Fri), Aug 24 (Mon), Aug 26 (Wed), Aug 28 (Fri), Aug 31 (Mon) -> 5 classes!
      // Since 4 <= 5, isAchievable is true.
      expect(recovery.remainingAfterLeave, equals(5));
      expect(recovery.isAchievable, isTrue);
      expect(recovery.targetRecoveryDate, equals(DateTime(2026, 8, 28)));
    });

    test('Scopes projection strictly to the next immediate planned leave when multiple leaves exist', () {
      final leaveImmediate = PlannedLeave(
        id: 'leave-1',
        name: 'Trip 1',
        startDate: DateTime(2026, 8, 17, 0, 0),
        endDate: DateTime(2026, 8, 19, 23, 59),
        affectedSubjectIds: ['sub-1'],
      );

      final leaveFuture = PlannedLeave(
        id: 'leave-2',
        name: 'Trip 2',
        startDate: DateTime(2026, 8, 26, 0, 0),
        endDate: DateTime(2026, 8, 28, 23, 59),
        affectedSubjectIds: ['sub-1'],
      );

      final records = [
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 3), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 5), status: AttendanceStatus.attended),
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 7), status: AttendanceStatus.absent),
        Attendance(subjectId: 'sub-1', date: DateTime(2026, 8, 10), status: AttendanceStatus.attended),
      ];

      final projection = ProjectedAttendanceCalculator.calculateForSubject(
        subject: subject,
        attendanceRecords: records,
        semester: semester,
        plannedLeaves: [leaveImmediate, leaveFuture],
        now: DateTime(2026, 8, 10),
      );

      // Should scope ONLY to Trip 1 (ending Aug 19), ignoring Trip 2!
      expect(projection.latestLeaveEndDate, equals(leaveImmediate.endDate));
      expect(projection.leaveStartDate, equals(leaveImmediate.startDate));
      expect(projection.leaveName, equals(leaveImmediate.name));
      expect(projection.totalAttended, equals(5));
      expect(projection.totalMarked, equals(8));
      expect(projection.plannedMissedCount, equals(2));
    });
  });
}
