import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/features/attendance/attendance_model.dart';
import 'package:attendmate/features/subject/subject_model.dart';
import 'package:attendmate/features/semester/semester_model.dart';
import 'package:attendmate/features/planner/planned_leave_model.dart';

// Deterministic 64-bit FNV-1a hash implementation matching CalendarService
String computeSlotHash(String rawContent) {
  BigInt hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final BigInt fnvPrime = BigInt.parse('100000001b3', radix: 16);
  final BigInt mask = BigInt.parse('ffffffffffffffff', radix: 16);
  for (int i = 0; i < rawContent.length; i++) {
    hash = (hash ^ BigInt.from(rawContent.codeUnitAt(i))) * fnvPrime & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String buildSlotSignature({
  required Subject subject,
  required TimeSlot slot,
  required Semester semester,
  required List<Attendance> attendanceRecords,
  required List<PlannedLeave> plannedLeaves,
  required bool Function(DateTime) isHoliday,
}) {
  DateTime startDateTime;
  DateTime endDateTime;
  DateTime untilDate = semester.endDate;

  if (slot.isSpecialClass) {
    final date = slot.specificDate!;
    startDateTime = DateTime(date.year, date.month, date.day, slot.startTime.hour, slot.startTime.minute);
    endDateTime = DateTime(date.year, date.month, date.day, slot.endTime.hour, slot.endTime.minute);
    untilDate = date;
  } else {
    DateTime calcStart = semester.startDate;
    if (slot.effectiveFrom != null && slot.effectiveFrom!.isAfter(calcStart)) {
      calcStart = slot.effectiveFrom!;
    }
    int daysToAdd = (slot.day.index + 1 - calcStart.weekday + 7) % 7;
    DateTime firstDate = calcStart.add(Duration(days: daysToAdd));

    startDateTime = DateTime(firstDate.year, firstDate.month, firstDate.day, slot.startTime.hour, slot.startTime.minute);
    endDateTime = DateTime(firstDate.year, firstDate.month, firstDate.day, slot.endTime.hour, slot.endTime.minute);

    if (slot.effectiveUntil != null && slot.effectiveUntil!.isBefore(untilDate)) {
      untilDate = slot.effectiveUntil!;
    }
  }

  List<String>? recurrenceRule;
  if (!slot.isSpecialClass) {
    final untilInclusive = DateTime(untilDate.year, untilDate.month, untilDate.day, 23, 59, 59);
    final String untilFormatted = "${untilInclusive.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z";
    recurrenceRule = ["RRULE:FREQ=WEEKLY;UNTIL=$untilFormatted"];

    DateTime currentDate = DateTime(startDateTime.year, startDateTime.month, startDateTime.day);
    final DateTime checkUntil = DateTime(untilDate.year, untilDate.month, untilDate.day);

    while (currentDate.isBefore(checkUntil) || currentDate.isAtSameMomentAs(checkUntil)) {
      final occStart = DateTime(currentDate.year, currentDate.month, currentDate.day, slot.startTime.hour, slot.startTime.minute);
      final occEnd = DateTime(currentDate.year, currentDate.month, currentDate.day, slot.endTime.hour, slot.endTime.minute);

      bool isExcluded = isHoliday(currentDate);
      if (!isExcluded) {
        for (final leave in plannedLeaves) {
          if (leave.affectedSubjectIds.isEmpty || leave.affectedSubjectIds.contains(subject.id)) {
            if (occStart.isBefore(leave.endDate) && occEnd.isAfter(leave.startDate)) {
              isExcluded = true;
              break;
            }
          }
        }
      }
      for (final record in attendanceRecords) {
        if (record.date.year == currentDate.year &&
            record.date.month == currentDate.month &&
            record.date.day == currentDate.day &&
            (record.slotKey == null || record.slotKey == slot.slotKey || record.slotKey!.isEmpty)) {
          if (record.status == AttendanceStatus.cancelled || record.status == AttendanceStatus.absent) {
            isExcluded = true;
          } else if (record.status == AttendanceStatus.attended) {
            isExcluded = false;
          }
          break;
        }
      }

      if (isExcluded) {
        final occurrenceUtcStart = occStart.toUtc();
        final exdateStr = "${occurrenceUtcStart.toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.').first}Z";
        recurrenceRule.add("EXDATE:$exdateStr");
      }

      currentDate = currentDate.add(const Duration(days: 7));
    }
  }

  final room = subject.getEffectiveRoom(slot);
  final block = subject.getEffectiveBlock(slot);
  final locationStr = room != null ? '$room${block != null && block.isNotEmpty ? ' ($block)' : ''}' : null;
  final summaryStr = "${subject.name} ${subject.acronym != null ? '(${subject.acronym})' : ''}".trim();

  return [
    summaryStr,
    '1', // colorId
    startDateTime.toUtc().toIso8601String(),
    endDateTime.toUtc().toIso8601String(),
    locationStr ?? '',
    subject.targetAttendance.toString(),
    ...?recurrenceRule,
  ].join('||');
}

void main() {
  group('Calendar Sync Differential Hash Tests', () {
    final semester = Semester(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 11, 30),
      targetPercentage: 75.0,
    );

    final slotMon = TimeSlot(
      day: DayOfWeek.monday,
      startTime: const TimeOfDay(hour: 9, minute: 0),
      endTime: const TimeOfDay(hour: 10, minute: 0),
    );

    final slotWed = TimeSlot(
      day: DayOfWeek.wednesday,
      startTime: const TimeOfDay(hour: 14, minute: 0),
      endTime: const TimeOfDay(hour: 15, minute: 0),
    );

    final subject = Subject(
      id: 'sub-cs101',
      name: 'Data Structures',
      acronym: 'DS',
      color: Colors.blue,
      schedule: [slotMon, slotWed],
      targetAttendance: 75,
    );

    test('Identical slot content produces identical deterministic hash', () {
      final sig1 = buildSlotSignature(
        subject: subject,
        slot: slotMon,
        semester: semester,
        attendanceRecords: [],
        plannedLeaves: [],
        isHoliday: (_) => false,
      );

      final sig2 = buildSlotSignature(
        subject: subject,
        slot: slotMon,
        semester: semester,
        attendanceRecords: [],
        plannedLeaves: [],
        isHoliday: (_) => false,
      );

      final hash1 = computeSlotHash(sig1);
      final hash2 = computeSlotHash(sig2);

      expect(hash1, equals(hash2));
      expect(hash1.length, equals(16));
    });

    test('Marking absent on Monday changes Monday hash but leaves Wednesday hash unchanged', () {
      final monSigBefore = buildSlotSignature(
        subject: subject,
        slot: slotMon,
        semester: semester,
        attendanceRecords: [],
        plannedLeaves: [],
        isHoliday: (_) => false,
      );

      final wedSigBefore = buildSlotSignature(
        subject: subject,
        slot: slotWed,
        semester: semester,
        attendanceRecords: [],
        plannedLeaves: [],
        isHoliday: (_) => false,
      );

      // Student marks absent on Monday Aug 3, 2026
      final absentRecord = Attendance(
        subjectId: subject.id,
        date: DateTime(2026, 8, 3),
        status: AttendanceStatus.absent,
        slotKey: slotMon.slotKey,
      );

      final monSigAfter = buildSlotSignature(
        subject: subject,
        slot: slotMon,
        semester: semester,
        attendanceRecords: [absentRecord],
        plannedLeaves: [],
        isHoliday: (_) => false,
      );

      final wedSigAfter = buildSlotSignature(
        subject: subject,
        slot: slotWed,
        semester: semester,
        attendanceRecords: [absentRecord],
        plannedLeaves: [],
        isHoliday: (_) => false,
      );

      final monHashBefore = computeSlotHash(monSigBefore);
      final monHashAfter = computeSlotHash(monSigAfter);
      final wedHashBefore = computeSlotHash(wedSigBefore);
      final wedHashAfter = computeSlotHash(wedSigAfter);

      // Monday changed due to new EXDATE
      expect(monHashBefore, isNot(equals(monHashAfter)));
      // Wednesday is completely unaffected (0 API calls needed)
      expect(wedHashBefore, equals(wedHashAfter));
    });

    test('Holiday adds EXDATE and modifies hash', () {
      final sigNoHoliday = buildSlotSignature(
        subject: subject,
        slot: slotMon,
        semester: semester,
        attendanceRecords: [],
        plannedLeaves: [],
        isHoliday: (_) => false,
      );

      final sigWithHoliday = buildSlotSignature(
        subject: subject,
        slot: slotMon,
        semester: semester,
        attendanceRecords: [],
        plannedLeaves: [],
        isHoliday: (date) => date.year == 2026 && date.month == 8 && date.day == 10,
      );

      expect(computeSlotHash(sigNoHoliday), isNot(equals(computeSlotHash(sigWithHoliday))));
    });

    test('Planned leave adds EXDATE and modifies hash', () {
      final sigNoLeave = buildSlotSignature(
        subject: subject,
        slot: slotMon,
        semester: semester,
        attendanceRecords: [],
        plannedLeaves: [],
        isHoliday: (_) => false,
      );

      final leave = PlannedLeave(
        id: 'leave-1',
        name: 'Fest',
        startDate: DateTime(2026, 8, 17, 0, 0),
        endDate: DateTime(2026, 8, 18, 0, 0),
        affectedSubjectIds: [subject.id],
      );

      final sigWithLeave = buildSlotSignature(
        subject: subject,
        slot: slotMon,
        semester: semester,
        attendanceRecords: [],
        plannedLeaves: [leave],
        isHoliday: (_) => false,
      );

      expect(computeSlotHash(sigNoLeave), isNot(equals(computeSlotHash(sigWithLeave))));
    });

    test('RFC 5545 UID format conforms to AttendMate schema', () {
      final slotKeyId = slotMon.slotKey.replaceAll(':', '_').replaceAll('-', '_');
      final uniqueICalId = "sched_${subject.id}_slot_$slotKeyId@attendmate.app".toLowerCase();

      expect(uniqueICalId.startsWith('sched_'), isTrue);
      expect(uniqueICalId.endsWith('@attendmate.app'), isTrue);
      expect(uniqueICalId, contains('sub_cs101'));
      expect(uniqueICalId, contains('0_09_00_10_00'));
    });
  });
}
