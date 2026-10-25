import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/features/attendance/attendance_model.dart';
import 'package:attendmate/features/attendance/attendance_provider.dart';
import 'package:attendmate/features/calendar/calendar_utils.dart';
import 'package:attendmate/features/planner/planned_leave_model.dart';
import 'package:attendmate/features/subject/subject_model.dart';

class TestAttendanceProvider extends AttendanceProvider {
  final List<Attendance> _records = [];

  @override
  List<Attendance> get attendanceRecords => _records;

  @override
  bool get isLoading => false;

  @override
  Future<void> markMultipleAttendance(List<Attendance> records) async {
    for (final record in records) {
      _records.removeWhere(
        (r) =>
            r.subjectId == record.subjectId &&
            CalendarUtils.isSameDay(r.date, record.date) &&
            (r.slotKey ?? '') == (record.slotKey ?? ''),
      );
      _records.add(record);
    }
    notifyListeners();
  }

  @override
  Attendance? getAttendanceForSubjectOnDate(
    String subjectId,
    DateTime date, {
    String? slotKey,
  }) {
    try {
      if (slotKey != null) {
        return _records.firstWhere(
          (r) =>
              r.subjectId == subjectId &&
              CalendarUtils.isSameDay(r.date, date) &&
              (r.slotKey ?? '') == slotKey,
        );
      }
      return _records.firstWhere(
        (r) =>
            r.subjectId == subjectId &&
            CalendarUtils.isSameDay(r.date, date) &&
            ((r.slotKey ?? '').isEmpty),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteRecordForSubjectOnDate(
    String subjectId,
    DateTime date, {
    String? slotKey,
  }) async {
    _records.removeWhere(
      (r) =>
          r.subjectId == subjectId &&
          CalendarUtils.isSameDay(r.date, date) &&
          (slotKey == null || (r.slotKey ?? '') == slotKey),
    );
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Planned Leave Absent Sync Tests', () {
    final sub1 = Subject(
      id: 'sub-1',
      name: 'Computer Networks',
      color: Colors.indigo,
      schedule: [
        TimeSlot(
          day: DayOfWeek.monday,
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 10, minute: 0),
        ),
        TimeSlot(
          day: DayOfWeek.wednesday,
          startTime: const TimeOfDay(hour: 14, minute: 0),
          endTime: const TimeOfDay(hour: 15, minute: 0),
        ),
      ],
      targetAttendance: 75,
    );

    final sub2 = Subject(
      id: 'sub-2',
      name: 'Operating Systems',
      color: Colors.teal,
      schedule: [
        TimeSlot(
          day: DayOfWeek.monday,
          startTime: const TimeOfDay(hour: 11, minute: 0),
          endTime: const TimeOfDay(hour: 12, minute: 0),
        ),
      ],
      targetAttendance: 75,
    );

    test('syncPlannedLeavesWithAttendance marks future dates as absent immediately', () async {
      final attendanceProvider = TestAttendanceProvider();

      // Next Monday in the future
      final now = DateTime.now();
      int daysUntilNextMonday = (DateTime.monday - now.weekday) % 7;
      if (daysUntilNextMonday <= 0) daysUntilNextMonday += 7;
      final futureMonday = DateTime(now.year, now.month, now.day + daysUntilNextMonday);

      final leave = PlannedLeave(
        id: 'leave-1',
        name: 'Fest Leave',
        startDate: DateTime(futureMonday.year, futureMonday.month, futureMonday.day, 0, 0),
        endDate: DateTime(futureMonday.year, futureMonday.month, futureMonday.day, 23, 59),
        affectedSubjectIds: [],
      );

      await attendanceProvider.syncPlannedLeavesWithAttendance(
        plannedLeaves: [leave],
        subjects: [sub1, sub2],
      );

      // Check sub1
      final sub1Record = attendanceProvider.getAttendanceForSubjectOnDate(
        sub1.id,
        futureMonday,
        slotKey: sub1.schedule.first.slotKey,
      );
      expect(sub1Record, isNotNull);
      expect(sub1Record!.status, equals(AttendanceStatus.absent));

      // Check sub2
      final sub2Record = attendanceProvider.getAttendanceForSubjectOnDate(
        sub2.id,
        futureMonday,
        slotKey: sub2.schedule.first.slotKey,
      );
      expect(sub2Record, isNotNull);
      expect(sub2Record!.status, equals(AttendanceStatus.absent));
    });

    test('cleanupPlannedLeaveAttendance removes absent records when leave is deleted', () async {
      final attendanceProvider = TestAttendanceProvider();

      final now = DateTime.now();
      int daysUntilNextMonday = (DateTime.monday - now.weekday) % 7;
      if (daysUntilNextMonday <= 0) daysUntilNextMonday += 7;
      final futureMonday = DateTime(now.year, now.month, now.day + daysUntilNextMonday);

      final leave = PlannedLeave(
        id: 'leave-to-delete',
        name: 'Delete Me Leave',
        startDate: DateTime(futureMonday.year, futureMonday.month, futureMonday.day, 0, 0),
        endDate: DateTime(futureMonday.year, futureMonday.month, futureMonday.day, 23, 59),
        affectedSubjectIds: [sub1.id],
      );

      await attendanceProvider.syncPlannedLeavesWithAttendance(
        plannedLeaves: [leave],
        subjects: [sub1],
      );

      expect(
        attendanceProvider.getAttendanceForSubjectOnDate(
          sub1.id,
          futureMonday,
          slotKey: sub1.schedule.first.slotKey,
        )?.status,
        equals(AttendanceStatus.absent),
      );

      // Delete leave
      await attendanceProvider.cleanupPlannedLeaveAttendance(
        deletedLeave: leave,
        remainingLeaves: [],
        subjects: [sub1],
      );

      expect(
        attendanceProvider.getAttendanceForSubjectOnDate(
          sub1.id,
          futureMonday,
          slotKey: sub1.schedule.first.slotKey,
        ),
        isNull,
      );
    });
  });
}
