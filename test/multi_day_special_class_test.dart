import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/features/subject/subject_model.dart';

void main() {
  group('Multi-Day Special Class Model Tests', () {
    test('TimeSlot isSpecialClass is true when specificDate is set', () {
      final slot = TimeSlot(
        day: DayOfWeek.monday,
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 10, minute: 0),
        specificDate: DateTime(2026, 9, 15),
      );

      expect(slot.isSpecialClass, isTrue);
      expect(slot.occursOnDate(DateTime(2026, 9, 15)), isTrue);
      expect(slot.occursOnDate(DateTime(2026, 9, 22)), isFalse); // Following Monday
    });

    test('Subject returns isSpecialClass true when containing specificDate slots', () {
      final subject = Subject(
        name: 'AI Workshop',
        color: Colors.purple,
        schedule: [
          TimeSlot(
            day: DayOfWeek.tuesday,
            startTime: const TimeOfDay(hour: 10, minute: 0),
            endTime: const TimeOfDay(hour: 12, minute: 0),
            specificDate: DateTime(2026, 9, 15),
          ),
          TimeSlot(
            day: DayOfWeek.thursday,
            startTime: const TimeOfDay(hour: 14, minute: 0),
            endTime: const TimeOfDay(hour: 16, minute: 0),
            specificDate: DateTime(2026, 9, 17),
          ),
          TimeSlot(
            day: DayOfWeek.saturday,
            startTime: const TimeOfDay(hour: 9, minute: 0),
            endTime: const TimeOfDay(hour: 11, minute: 0),
            specificDate: DateTime(2026, 9, 19),
          ),
        ],
      );

      expect(subject.isSpecialClass, isTrue);
      expect(subject.specialClassDates.length, equals(3));
      expect(
        subject.specialClassDates,
        equals([
          DateTime(2026, 9, 15),
          DateTime(2026, 9, 17),
          DateTime(2026, 9, 19),
        ]),
      );
      expect(subject.specialClassDate, equals(DateTime(2026, 9, 15)));
    });

    test('Regular weekly subject returns isSpecialClass false and empty specialClassDates', () {
      final subject = Subject(
        name: 'Regular Lecture',
        color: Colors.green,
        schedule: [
          TimeSlot(
            day: DayOfWeek.monday,
            startTime: const TimeOfDay(hour: 9, minute: 0),
            endTime: const TimeOfDay(hour: 10, minute: 0),
          ),
        ],
      );

      expect(subject.isSpecialClass, isFalse);
      expect(subject.specialClassDates, isEmpty);
      expect(subject.specialClassDate, isNull);
    });

    test('Multi-day special class calculates exact scheduled occurrences without weekly repetition', () {
      final subject = Subject(
        name: 'Bootcamp',
        color: Colors.orange,
        schedule: [
          TimeSlot(
            day: DayOfWeek.monday,
            startTime: const TimeOfDay(hour: 9, minute: 0),
            endTime: const TimeOfDay(hour: 10, minute: 0),
            specificDate: DateTime(2026, 9, 1),
          ),
          TimeSlot(
            day: DayOfWeek.wednesday,
            startTime: const TimeOfDay(hour: 9, minute: 0),
            endTime: const TimeOfDay(hour: 10, minute: 0),
            specificDate: DateTime(2026, 9, 10),
          ),
          TimeSlot(
            day: DayOfWeek.friday,
            startTime: const TimeOfDay(hour: 9, minute: 0),
            endTime: const TimeOfDay(hour: 10, minute: 0),
            specificDate: DateTime(2026, 9, 25),
          ),
        ],
      );

      // Entire month range: all 3 should occur
      expect(
        subject.getTotalScheduledClasses(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
        equals(3),
      );

      // Mid-month window containing only September 10
      expect(
        subject.getTotalScheduledClasses(DateTime(2026, 9, 5), DateTime(2026, 9, 15)),
        equals(1),
      );

      // Window after September 25: 0 occurrences
      expect(
        subject.getTotalScheduledClasses(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
        equals(0),
      );
    });
  });
}
