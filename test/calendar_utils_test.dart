import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/features/attendance/attendance_model.dart';
import 'package:attendmate/features/calendar/calendar_utils.dart';
import 'package:attendmate/features/planner/planned_leave_model.dart';
import 'package:attendmate/features/subject/subject_model.dart';

void main() {
  group('CalendarUtils Tests', () {
    // Subject 1: Mon, Wed
    final subject1 = Subject(
      id: 'sub-1',
      name: 'Mathematics',
      color: Colors.blue,
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
      ],
      targetAttendance: 75,
    );

    // Subject 2: Mon, Wed
    final subject2 = Subject(
      id: 'sub-2',
      name: 'Physics',
      color: Colors.green,
      schedule: [
        TimeSlot(
          day: DayOfWeek.monday,
          startTime: const TimeOfDay(hour: 11, minute: 0),
          endTime: const TimeOfDay(hour: 12, minute: 0),
        ),
        TimeSlot(
          day: DayOfWeek.wednesday,
          startTime: const TimeOfDay(hour: 11, minute: 0),
          endTime: const TimeOfDay(hour: 12, minute: 0),
        ),
      ],
      targetAttendance: 75,
    );

    test('Returns noClasses when no classes are scheduled for the day', () {
      // Sunday Aug 9, 2026
      final date = DateTime(2026, 8, 9);
      final dayInfo = CalendarUtils.getDayState(
        date: date,
        subjects: [subject1, subject2],
        attendanceRecords: [],
      );

      expect(dayInfo.state, equals(DayState.noClasses));
      expect(dayInfo.classesCount, equals(0));
    });

    test('Helper isLockedByManualOverride returns true only before effectiveFrom', () {
      final subjectWithOverride = subject1.copyWithManualAttendanceOverride(
        effectiveFrom: DateTime(2026, 8, 15),
        classesHeld: 10,
        classesAttended: 8,
      );

      expect(
        CalendarUtils.isLockedByManualOverride(subjectWithOverride, DateTime(2026, 8, 10)),
        isTrue,
      );
      expect(
        CalendarUtils.isLockedByManualOverride(subjectWithOverride, DateTime(2026, 8, 14)),
        isTrue,
      );
      expect(
        CalendarUtils.isLockedByManualOverride(subjectWithOverride, DateTime(2026, 8, 15)),
        isFalse,
      );
      expect(
        CalendarUtils.isLockedByManualOverride(subjectWithOverride, DateTime(2026, 8, 16)),
        isFalse,
      );
      expect(
        CalendarUtils.isLockedByManualOverride(subject1, DateTime(2026, 8, 10)),
        isFalse,
      );
    });

    test('Returns locked when all scheduled classes on a day are before manual baseline override', () {
      // Monday Aug 10, 2026 (past date)
      final date = DateTime(2026, 8, 10);
      final sub1Override = subject1.copyWithManualAttendanceOverride(
        effectiveFrom: DateTime(2026, 8, 15),
        classesHeld: 10,
        classesAttended: 8,
      );
      final sub2Override = subject2.copyWithManualAttendanceOverride(
        effectiveFrom: DateTime(2026, 8, 15),
        classesHeld: 8,
        classesAttended: 6,
      );

      final dayInfo = CalendarUtils.getDayState(
        date: date,
        subjects: [sub1Override, sub2Override],
        attendanceRecords: [],
      );

      expect(dayInfo.state, equals(DayState.locked));
      expect(dayInfo.classesCount, equals(2));
      expect(CalendarUtils.getStateLabel(dayInfo.state), equals('Locked'));
      expect(CalendarUtils.getStateIcon(dayInfo.state), equals(Icons.lock_outline));
      expect(CalendarUtils.getStateColor(dayInfo.state), equals(const Color(0xFF607D8B)));
    });

    test('Returns single subject locked when its class is before manual baseline override', () {
      final date = DateTime(2026, 8, 10);
      final sub1Override = subject1.copyWithManualAttendanceOverride(
        effectiveFrom: DateTime(2026, 8, 15),
        classesHeld: 10,
        classesAttended: 8,
      );

      final dayInfo = CalendarUtils.getDayState(
        date: date,
        subjects: [sub1Override],
        attendanceRecords: [],
      );

      expect(dayInfo.state, equals(DayState.locked));
      expect(dayInfo.classesCount, equals(1));
    });

    test('Returns Mixed (classesMarked) when one subject is locked and another is attended', () {
      final date = DateTime(2026, 8, 10);
      final sub1Override = subject1.copyWithManualAttendanceOverride(
        effectiveFrom: DateTime(2026, 8, 15),
        classesHeld: 10,
        classesAttended: 8,
      );
      // sub2 has no override, but is marked attended
      final records = [
        Attendance(
          subjectId: subject2.id,
          date: date,
          status: AttendanceStatus.attended,
          slotKey: subject2.schedule.first.slotKey,
        ),
      ];

      final dayInfo = CalendarUtils.getDayState(
        date: date,
        subjects: [sub1Override, subject2],
        attendanceRecords: records,
      );

      expect(dayInfo.state, equals(DayState.classesMarked));
      expect(CalendarUtils.getStateLabel(dayInfo.state), equals('Mixed'));
    });

    test('Returns Mixed (classesMarked) when one subject is locked and another is absent', () {
      final date = DateTime(2026, 8, 10);
      final sub1Override = subject1.copyWithManualAttendanceOverride(
        effectiveFrom: DateTime(2026, 8, 15),
        classesHeld: 10,
        classesAttended: 8,
      );
      // sub2 has no override, but is marked absent
      final records = [
        Attendance(
          subjectId: subject2.id,
          date: date,
          status: AttendanceStatus.absent,
          slotKey: subject2.schedule.first.slotKey,
        ),
      ];

      final dayInfo = CalendarUtils.getDayState(
        date: date,
        subjects: [sub1Override, subject2],
        attendanceRecords: records,
      );

      expect(dayInfo.state, equals(DayState.classesMarked));
    });

    test('Returns Mixed (classesMarked) when one subject is locked and another is cancelled (holiday)', () {
      final date = DateTime(2026, 8, 10);
      final sub1Override = subject1.copyWithManualAttendanceOverride(
        effectiveFrom: DateTime(2026, 8, 15),
        classesHeld: 10,
        classesAttended: 8,
      );
      // sub2 is marked cancelled
      final records = [
        Attendance(
          subjectId: subject2.id,
          date: date,
          status: AttendanceStatus.cancelled,
          slotKey: subject2.schedule.first.slotKey,
        ),
      ];

      final dayInfo = CalendarUtils.getDayState(
        date: date,
        subjects: [sub1Override, subject2],
        attendanceRecords: records,
      );

      expect(dayInfo.state, equals(DayState.classesMarked));
    });

    test('Returns classesNotMarked when one subject is locked but another is truly unmarked on past date', () {
      final date = DateTime(2026, 8, 10);
      final sub1Override = subject1.copyWithManualAttendanceOverride(
        effectiveFrom: DateTime(2026, 8, 15),
        classesHeld: 10,
        classesAttended: 8,
      );
      // sub2 has no record and no override

      final dayInfo = CalendarUtils.getDayState(
        date: date,
        subjects: [sub1Override, subject2],
        attendanceRecords: [],
      );

      expect(dayInfo.state, equals(DayState.classesNotMarked));
      expect(CalendarUtils.getStateLabel(dayInfo.state), equals('Not Marked'));
    });

    test('Returns attendedFullDay when all classes are marked attended', () {
      final date = DateTime(2026, 8, 10);
      final records = [
        Attendance(subjectId: subject1.id, date: date, status: AttendanceStatus.attended, slotKey: subject1.schedule.first.slotKey),
        Attendance(subjectId: subject2.id, date: date, status: AttendanceStatus.attended, slotKey: subject2.schedule.first.slotKey),
      ];

      final dayInfo = CalendarUtils.getDayState(
        date: date,
        subjects: [subject1, subject2],
        attendanceRecords: records,
      );

      expect(dayInfo.state, equals(DayState.attendedFullDay));
      expect(CalendarUtils.getStateLabel(dayInfo.state), equals('Full Day'));
    });

    test('Returns bunkedFullDay when all classes are marked absent', () {
      final date = DateTime(2026, 8, 10);
      final records = [
        Attendance(subjectId: subject1.id, date: date, status: AttendanceStatus.absent, slotKey: subject1.schedule.first.slotKey),
        Attendance(subjectId: subject2.id, date: date, status: AttendanceStatus.absent, slotKey: subject2.schedule.first.slotKey),
      ];

      final dayInfo = CalendarUtils.getDayState(
        date: date,
        subjects: [subject1, subject2],
        attendanceRecords: records,
      );

      expect(dayInfo.state, equals(DayState.bunkedFullDay));
      expect(CalendarUtils.getStateLabel(dayInfo.state), equals('Bunked'));
    });

    test('Returns plannedLeave when all classes are covered by planned leave', () {
      final date = DateTime(2026, 8, 10);
      final leave = PlannedLeave(
        id: 'leave-1',
        name: 'Sick Leave',
        startDate: DateTime(2026, 8, 10, 0, 0),
        endDate: DateTime(2026, 8, 10, 23, 59),
        affectedSubjectIds: [],
      );

      final dayInfo = CalendarUtils.getDayState(
        date: date,
        subjects: [subject1, subject2],
        attendanceRecords: [],
        plannedLeaves: [leave],
      );

      expect(dayInfo.state, equals(DayState.plannedLeave));
      expect(CalendarUtils.getStateLabel(dayInfo.state), equals('Planned Leave'));
    });

    test('Returns holiday when all classes are cancelled', () {
      final date = DateTime(2026, 8, 10);
      final records = [
        Attendance(subjectId: subject1.id, date: date, status: AttendanceStatus.cancelled, slotKey: subject1.schedule.first.slotKey),
        Attendance(subjectId: subject2.id, date: date, status: AttendanceStatus.cancelled, slotKey: subject2.schedule.first.slotKey),
      ];

      final dayInfo = CalendarUtils.getDayState(
        date: date,
        subjects: [subject1, subject2],
        attendanceRecords: records,
      );

      expect(dayInfo.state, equals(DayState.holiday));
      expect(CalendarUtils.getStateLabel(dayInfo.state), equals('Holiday'));
    });

    test('Returns futureClasses when date is in the future and classes are not marked', () {
      final futureDate = DateTime.now().add(const Duration(days: 30));
      // Create a subject for this weekday
      final weekdayEnum = DayOfWeek.values[futureDate.weekday - 1];
      final futureSubject = Subject(
        id: 'future-sub',
        name: 'Future Sub',
        color: Colors.purple,
        schedule: [
          TimeSlot(
            day: weekdayEnum,
            startTime: const TimeOfDay(hour: 10, minute: 0),
            endTime: const TimeOfDay(hour: 11, minute: 0),
          ),
        ],
        targetAttendance: 75,
      );

      final dayInfo = CalendarUtils.getDayState(
        date: futureDate,
        subjects: [futureSubject],
        attendanceRecords: [],
      );

      expect(dayInfo.state, equals(DayState.futureClasses));
      expect(CalendarUtils.getStateLabel(dayInfo.state), equals('Upcoming'));
    });

    test('Returns plannedLeave for future date when all classes are marked absent and covered by planned leave', () {
      final futureDate = DateTime.now().add(const Duration(days: 10));
      final weekdayEnum = DayOfWeek.values[futureDate.weekday - 1];
      final futureSubject = Subject(
        id: 'future-sub',
        name: 'Future Sub',
        color: Colors.purple,
        schedule: [
          TimeSlot(
            day: weekdayEnum,
            startTime: const TimeOfDay(hour: 10, minute: 0),
            endTime: const TimeOfDay(hour: 11, minute: 0),
          ),
        ],
        targetAttendance: 75,
      );

      final leave = PlannedLeave(
        id: 'leave-future',
        name: 'Future Trip',
        startDate: DateTime(futureDate.year, futureDate.month, futureDate.day, 0, 0),
        endDate: DateTime(futureDate.year, futureDate.month, futureDate.day, 23, 59),
        affectedSubjectIds: [],
      );

      final records = [
        Attendance(
          subjectId: futureSubject.id,
          date: futureDate,
          status: AttendanceStatus.absent,
          slotKey: futureSubject.schedule.first.slotKey,
        ),
      ];

      final dayInfo = CalendarUtils.getDayState(
        date: futureDate,
        subjects: [futureSubject],
        attendanceRecords: records,
        plannedLeaves: [leave],
      );

      expect(dayInfo.state, equals(DayState.plannedLeave));
      expect(CalendarUtils.getStateLabel(dayInfo.state), equals('Planned Leave'));
    });

    test('Returns bunkedFullDay for future date when all classes are marked absent without planned leave', () {
      final futureDate = DateTime.now().add(const Duration(days: 10));
      final weekdayEnum = DayOfWeek.values[futureDate.weekday - 1];
      final futureSubject = Subject(
        id: 'future-sub',
        name: 'Future Sub',
        color: Colors.purple,
        schedule: [
          TimeSlot(
            day: weekdayEnum,
            startTime: const TimeOfDay(hour: 10, minute: 0),
            endTime: const TimeOfDay(hour: 11, minute: 0),
          ),
        ],
        targetAttendance: 75,
      );

      final records = [
        Attendance(
          subjectId: futureSubject.id,
          date: futureDate,
          status: AttendanceStatus.absent,
          slotKey: futureSubject.schedule.first.slotKey,
        ),
      ];

      final dayInfo = CalendarUtils.getDayState(
        date: futureDate,
        subjects: [futureSubject],
        attendanceRecords: records,
      );

      expect(dayInfo.state, equals(DayState.bunkedFullDay));
      expect(CalendarUtils.getStateLabel(dayInfo.state), equals('Bunked'));
    });

    test('Returns attendedFullDay for future date when all classes are marked attended', () {
      final futureDate = DateTime.now().add(const Duration(days: 10));
      final weekdayEnum = DayOfWeek.values[futureDate.weekday - 1];
      final futureSubject = Subject(
        id: 'future-sub',
        name: 'Future Sub',
        color: Colors.purple,
        schedule: [
          TimeSlot(
            day: weekdayEnum,
            startTime: const TimeOfDay(hour: 10, minute: 0),
            endTime: const TimeOfDay(hour: 11, minute: 0),
          ),
        ],
        targetAttendance: 75,
      );

      final records = [
        Attendance(
          subjectId: futureSubject.id,
          date: futureDate,
          status: AttendanceStatus.attended,
          slotKey: futureSubject.schedule.first.slotKey,
        ),
      ];

      final dayInfo = CalendarUtils.getDayState(
        date: futureDate,
        subjects: [futureSubject],
        attendanceRecords: records,
      );

      expect(dayInfo.state, equals(DayState.attendedFullDay));
      expect(CalendarUtils.getStateLabel(dayInfo.state), equals('Full Day'));
    });

    test('DayState labels, icons, and colors are defined for all states', () {
      for (final state in DayState.values) {
        expect(CalendarUtils.getStateLabel(state), isNotEmpty);
        expect(CalendarUtils.getStateIcon(state), isNotNull);
        expect(CalendarUtils.getStateColor(state), isNotNull);
      }
    });
  });
}
