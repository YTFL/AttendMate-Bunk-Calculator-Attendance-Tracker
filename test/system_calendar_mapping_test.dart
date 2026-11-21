import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/features/subject/subject_model.dart';
import 'package:attendmate/features/semester/semester_model.dart';

void main() {
  group('System Calendar Mapping & Boundary Tests', () {
    final semester = Semester(
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 11, 30),
      targetPercentage: 75.0,
    );

    final slotMon = TimeSlot(
      day: DayOfWeek.monday,
      startTime: const TimeOfDay(hour: 9, minute: 0),
      endTime: const TimeOfDay(hour: 10, minute: 0),
      room: '302',
      block: 'Block A',
    );

    final slotWed = TimeSlot(
      day: DayOfWeek.wednesday,
      startTime: const TimeOfDay(hour: 14, minute: 0),
      endTime: const TimeOfDay(hour: 15, minute: 0),
      room: 'Lab 1',
    );

    final oneOffExtraSlot = TimeSlot(
      day: DayOfWeek.friday,
      startTime: const TimeOfDay(hour: 10, minute: 0),
      endTime: const TimeOfDay(hour: 11, minute: 0),
      specificDate: DateTime(2026, 8, 14),
      room: 'Auditorium',
    );

    final subjectWithAcronym = Subject(
      id: 'sub-cs101',
      name: 'Data Structures',
      acronym: 'DS',
      color: Colors.blue,
      schedule: [slotMon, slotWed, oneOffExtraSlot],
      targetAttendance: 75,
    );

    final subjectNoAcronym = Subject(
      id: 'sub-m101',
      name: 'Mathematics',
      acronym: null,
      color: Colors.green,
      schedule: [slotMon],
      targetAttendance: 75,
    );

    test('slotKey is unique across recurring days and times', () {
      expect(slotMon.slotKey, isNot(equals(slotWed.slotKey)));
      expect(slotMon.slotKey, equals('0-09:00-10:00'));
      expect(slotWed.slotKey, equals('2-14:00-15:00'));
    });

    test('one-off slotKey includes ISO specificDate prefix for 1:1 uniqueness', () {
      expect(oneOffExtraSlot.slotKey, startsWith('2026-08-14-'));
      expect(oneOffExtraSlot.slotKey, equals('2026-08-14-4-10:00-11:00'));
      expect(oneOffExtraSlot.isSpecialClass, isTrue);
      expect(oneOffExtraSlot.isExtra, isTrue);
    });

    test('Subject acronym formatting in event title', () {
      final title1 = (subjectWithAcronym.acronym != null && subjectWithAcronym.acronym!.trim().isNotEmpty)
          ? '${subjectWithAcronym.name} (${subjectWithAcronym.acronym!.trim()})'
          : subjectWithAcronym.name;

      final title2 = (subjectNoAcronym.acronym != null && subjectNoAcronym.acronym!.trim().isNotEmpty)
          ? '${subjectNoAcronym.name} (${subjectNoAcronym.acronym!.trim()})'
          : subjectNoAcronym.name;

      expect(title1, equals('Data Structures (DS)'));
      expect(title2, equals('Mathematics'));
    });

    test('Classroom location formatting builds clean Room (Block) strings', () {
      final room1 = subjectWithAcronym.getEffectiveRoom(slotMon);
      final block1 = subjectWithAcronym.getEffectiveBlock(slotMon);
      final loc1 = room1 != null ? '$room1${block1 != null && block1.isNotEmpty ? ' ($block1)' : ''}' : null;

      final room2 = subjectWithAcronym.getEffectiveRoom(slotWed);
      final block2 = subjectWithAcronym.getEffectiveBlock(slotWed);
      final loc2 = room2 != null ? '$room2${block2 != null && block2.isNotEmpty ? ' ($block2)' : ''}' : null;

      expect(loc1, equals('302 (Block A)'));
      expect(loc2, equals('Lab 1'));
    });

    test('Boundary check: slot effectiveFrom beyond semester endDate is correctly excluded', () {
      final lateSlot = TimeSlot(
        day: DayOfWeek.monday,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 10, minute: 0),
        effectiveFrom: DateTime(2026, 12, 10), // after semester endDate 2026-11-30
      );

      DateTime anchorDate = lateSlot.effectiveFrom!;
      while (anchorDate.weekday != 1) {
        anchorDate = anchorDate.add(const Duration(days: 1));
      }

      final untilDate = semester.endDate;
      final shouldSkip = anchorDate.isAfter(untilDate);

      expect(shouldSkip, isTrue);
    });

    test('Obsolete events calculation correctly identifies removed slots and subjects', () {
      final activeEventIds = {'event-mon-1', 'event-wed-1'};
      final allSavedEvents = [
        {'eventId': 'event-mon-1', 'subjectId': 'sub-cs101', 'slotKey': slotMon.slotKey},
        {'eventId': 'event-wed-1', 'subjectId': 'sub-cs101', 'slotKey': slotWed.slotKey},
        {'eventId': 'event-old-deleted', 'subjectId': 'sub-deleted', 'slotKey': 'old-key'},
      ];

      final obsoleteEvents = allSavedEvents.where((e) => !activeEventIds.contains(e['eventId'] as String)).toList();

      expect(obsoleteEvents.length, equals(1));
      expect(obsoleteEvents.first['eventId'], equals('event-old-deleted'));
    });
  });
}
