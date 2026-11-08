import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/features/subject/subject_model.dart';
import 'package:attendmate/utils/timetable_import_utils.dart';

void main() {
  group('Elective Timetable Support Tests', () {
    test('Subject model stores and serializes isElective and electiveGroupName', () {
      final subject = Subject(
        name: 'Machine Learning',
        acronym: 'ML',
        color: Colors.blue,
        isElective: true,
        electiveGroupName: 'Elective 1',
        schedule: [
          TimeSlot(
            day: DayOfWeek.wednesday,
            startTime: const TimeOfDay(hour: 11, minute: 0),
            endTime: const TimeOfDay(hour: 12, minute: 30),
          ),
        ],
      );

      expect(subject.isElective, isTrue);
      expect(subject.electiveGroupName, equals('Elective 1'));

      final json = subject.toJson();
      expect(json['isElective'], isTrue);
      expect(json['electiveGroupName'], equals('Elective 1'));

      final reconstructed = Subject.fromJson(json);
      expect(reconstructed.isElective, isTrue);
      expect(reconstructed.electiveGroupName, equals('Elective 1'));
    });

    test('ElectiveSlot model serializes and deserializes correctly', () {
      final slot = ElectiveSlot(
        name: 'Professional Elective I',
        subjects: [
          Subject(
            name: 'Cloud Computing',
            acronym: 'CC',
            color: Colors.cyan,
            schedule: [
              TimeSlot(
                day: DayOfWeek.thursday,
                startTime: const TimeOfDay(hour: 14, minute: 0),
                endTime: const TimeOfDay(hour: 15, minute: 30),
              ),
            ],
          ),
          Subject(
            name: 'Information Security',
            acronym: 'IS',
            color: Colors.indigo,
            schedule: [
              TimeSlot(
                day: DayOfWeek.thursday,
                startTime: const TimeOfDay(hour: 14, minute: 0),
                endTime: const TimeOfDay(hour: 15, minute: 30),
              ),
            ],
          ),
        ],
      );

      final json = slot.toJson();
      expect(json['name'], equals('Professional Elective I'));
      expect(json['subjects'], isA<List>());
      expect((json['subjects'] as List).length, equals(2));

      final deserialized = ElectiveSlot.fromJson(json);
      expect(deserialized.name, equals('Professional Elective I'));
      expect(deserialized.subjects.length, equals(2));
      expect(deserialized.subjects.first.isElective, isTrue);
      expect(deserialized.subjects.first.electiveGroupName, equals('Professional Elective I'));
    });

    test('TimetableImportUtils parses electives array with 1 subject and multiple subjects', () {
      final jsonInput = '''
{
  "subjects": [
    {
      "name": "Mathematics",
      "acronym": "MTH",
      "schedule": [
        {"day": "monday", "startTime": "09:00", "endTime": "10:30"}
      ]
    }
  ],
  "electives": [
    {
      "name": "Elective 1",
      "subjects": [
        {
          "name": "Machine Learning",
          "acronym": "ML",
          "schedule": [
            {"day": "wednesday", "startTime": "11:00", "endTime": "12:30"}
          ]
        },
        {
          "name": "Cloud Computing",
          "acronym": "CC",
          "schedule": [
            {"day": "wednesday", "startTime": "11:00", "endTime": "12:30"}
          ]
        }
      ]
    },
    {
      "name": "Single Subject Elective",
      "subjects": [
        {
          "name": "Cyber Ethics",
          "acronym": "CE",
          "schedule": [
            {"day": "friday", "startTime": "14:00", "endTime": "15:30"}
          ]
        }
      ]
    }
  ]
}
''';

      final pkg = TimetableImportUtils.parseInputToImportPackage(jsonInput, {});
      expect(pkg.hasElectives, isTrue);
      expect(pkg.electiveSlots.length, equals(2));

      expect(pkg.standardSubjects.length, equals(1));
      expect(pkg.standardSubjects.first.name, equals('Mathematics'));

      // Elective 1 has 2 choices
      final slot1 = pkg.electiveSlots[0];
      expect(slot1.name, equals('Elective 1'));
      expect(slot1.subjects.length, equals(2));
      expect(slot1.subjects.map((s) => s.name).toSet(), equals({'Machine Learning', 'Cloud Computing'}));

      // Slot 2 has 1 choice
      final slot2 = pkg.electiveSlots[1];
      expect(slot2.name, equals('Single Subject Elective'));
      expect(slot2.subjects.length, equals(1));
      expect(slot2.subjects.first.name, equals('Cyber Ethics'));
    });

    test('TimetableImportUtils parses standalone Electives JSON', () {
      final electivesJson = TimetableImportUtils.generateTemplateJsonElectives();
      final pkg = TimetableImportUtils.parseInputToImportPackage(electivesJson, {});
      expect(pkg.hasElectives, isTrue);
      expect(pkg.electiveSlots.length, equals(1));
      expect(pkg.electiveSlots.first.subjects.length, equals(2));
    });
  });
}
