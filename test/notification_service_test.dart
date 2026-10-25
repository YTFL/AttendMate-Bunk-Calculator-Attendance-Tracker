import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/features/attendance/attendance_model.dart';
import 'package:attendmate/features/subject/subject_model.dart';
import 'package:attendmate/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationService ID Generation & Collision Prevention', () {
    final notificationService = NotificationService();

    test('generates distinct IDs for pre-class vs end-of-class notifications', () {
      const subjectId = 'sub-101';
      final slot = TimeSlot(
        day: DayOfWeek.monday,
        startTime: const TimeOfDay(hour: 10, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 0),
      );

      final preClassId = notificationService.getPreClassNotificationId(subjectId, slot);
      final endOfClassId = notificationService.getEndOfClassNotificationId(subjectId, slot);

      expect(preClassId, isNot(equals(endOfClassId)));
    });

    test('generates distinct IDs for different slots of same subject', () {
      const subjectId = 'sub-101';
      final slot1 = TimeSlot(
        day: DayOfWeek.monday,
        startTime: const TimeOfDay(hour: 10, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 0),
      );
      final slot2 = TimeSlot(
        day: DayOfWeek.wednesday,
        startTime: const TimeOfDay(hour: 10, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 0),
      );

      final id1 = notificationService.getEndOfClassNotificationId(subjectId, slot1);
      final id2 = notificationService.getEndOfClassNotificationId(subjectId, slot2);

      expect(id1, isNot(equals(id2)));
    });

    test('prevents collision between regular weekly slot and extra class on specific date', () {
      const subjectId = 'sub-101';
      final regularSlot = TimeSlot(
        day: DayOfWeek.monday,
        startTime: const TimeOfDay(hour: 10, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 0),
      );
      final extraClassSlot = TimeSlot(
        day: DayOfWeek.monday,
        startTime: const TimeOfDay(hour: 10, minute: 0),
        endTime: const TimeOfDay(hour: 11, minute: 0),
        specificDate: DateTime(2026, 11, 2),
        isExtra: true,
      );

      final regularId = notificationService.getEndOfClassNotificationId(subjectId, regularSlot);
      final extraClassId = notificationService.getEndOfClassNotificationId(subjectId, extraClassSlot);

      expect(regularSlot.slotKey, isNot(equals(extraClassSlot.slotKey)));
      expect(regularId, isNot(equals(extraClassId)));
    });

    test('generates valid geofence task key format', () {
      const subjectId = 'sub-abc';
      const slotKey = '0-09:00-10:00';
      final date = DateTime(2026, 10, 25, 14, 30);
      final dateOnly = DateTime(2026, 10, 25);

      final taskKey = notificationService.getGeofenceTaskKey(subjectId, slotKey, date);
      expect(
        taskKey,
        equals('geofence_${subjectId}_${slotKey}_${dateOnly.millisecondsSinceEpoch}'),
      );
    });
  });

  group('NotificationService isClassAlreadyMarked', () {
    final notificationService = NotificationService();
    final today = DateTime(2026, 10, 26); // Monday
    const subjectId = 'sub-math';
    const slotKey = '0-10:00-11:00';

    test('returns false when no attendance records exist for the day', () {
      final isMarked = notificationService.isClassAlreadyMarked(
        existingAttendance: [],
        subjectId: subjectId,
        date: today,
        slotKey: slotKey,
      );
      expect(isMarked, isFalse);
    });

    test('returns true when slot is marked as attended', () {
      final records = [
        Attendance(
          subjectId: subjectId,
          date: today,
          status: AttendanceStatus.attended,
          slotKey: slotKey,
        ),
      ];

      final isMarked = notificationService.isClassAlreadyMarked(
        existingAttendance: records,
        subjectId: subjectId,
        date: today,
        slotKey: slotKey,
      );
      expect(isMarked, isTrue);
    });

    test('returns true when slot is marked as absent', () {
      final records = [
        Attendance(
          subjectId: subjectId,
          date: today,
          status: AttendanceStatus.absent,
          slotKey: slotKey,
        ),
      ];

      final isMarked = notificationService.isClassAlreadyMarked(
        existingAttendance: records,
        subjectId: subjectId,
        date: today,
        slotKey: slotKey,
      );
      expect(isMarked, isTrue);
    });

    test('returns true when slot is marked as cancelled (holiday)', () {
      final records = [
        Attendance(
          subjectId: subjectId,
          date: today,
          status: AttendanceStatus.cancelled,
          slotKey: slotKey,
        ),
      ];

      final isMarked = notificationService.isClassAlreadyMarked(
        existingAttendance: records,
        subjectId: subjectId,
        date: today,
        slotKey: slotKey,
      );
      expect(isMarked, isTrue);
    });

    test('returns true when slot is marked as plannedAbsent', () {
      final records = [
        Attendance(
          subjectId: subjectId,
          date: today,
          status: AttendanceStatus.plannedAbsent,
          slotKey: slotKey,
        ),
      ];

      final isMarked = notificationService.isClassAlreadyMarked(
        existingAttendance: records,
        subjectId: subjectId,
        date: today,
        slotKey: slotKey,
      );
      expect(isMarked, isTrue);
    });

    test('distinguishes different slots on the same day', () {
      const otherSlotKey = '0-14:00-15:00';
      final records = [
        Attendance(
          subjectId: subjectId,
          date: today,
          status: AttendanceStatus.attended,
          slotKey: otherSlotKey,
        ),
      ];

      final isMarked = notificationService.isClassAlreadyMarked(
        existingAttendance: records,
        subjectId: subjectId,
        date: today,
        slotKey: slotKey,
      );
      expect(isMarked, isFalse);
    });

    test('returns true when the entire day is marked as a holiday', () {
      final records = [
        Attendance(
          subjectId: 'sub-physics',
          date: today,
          status: AttendanceStatus.cancelled,
          slotKey: '0-09:00-10:00',
        ),
        Attendance(
          subjectId: 'sub-chemistry',
          date: today,
          status: AttendanceStatus.cancelled,
          slotKey: '0-11:00-12:00',
        ),
      ];

      final isMarked = notificationService.isClassAlreadyMarked(
        existingAttendance: records,
        subjectId: subjectId,
        date: today,
        slotKey: slotKey,
      );
      expect(isMarked, isTrue);
    });
  });
}
