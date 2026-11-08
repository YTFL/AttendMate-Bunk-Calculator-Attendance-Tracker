import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/features/subject/subject_model.dart';
import 'package:attendmate/utils/timetable_import_utils.dart';

void main() {
  group('Special One-Off Classes JSON Import Tests', () {
    test('Parses specialClasses array with date, inferring weekday and isExtra', () {
      final jsonInput = '''
{
  "specialClasses": [
    {
      "subject": "Mathematics",
      "acronym": "MTH",
      "date": "2026-11-20",
      "startTime": "14:00",
      "endTime": "15:30",
      "room": "Room 302",
      "block": "Block B",
      "isExtra": true
    },
    {
      "name": "Robotics Seminar",
      "acronym": "ROBO",
      "date": "2026-11-22",
      "startTime": "10:00",
      "endTime": "13:00",
      "isSpecialClass": true
    }
  ]
}
''';

      final pkg = TimetableImportUtils.parseInputToImportPackage(jsonInput, {});
      expect(pkg.hasSpecialClasses, isTrue);
      expect(pkg.specialClasses.length, equals(2));

      // 2026-11-20 is a Friday
      final item1 = pkg.specialClasses[0];
      expect(item1.subjectName, equals('Mathematics'));
      expect(item1.subjectAcronym, equals('MTH'));
      expect(item1.slot.specificDate, equals(DateTime(2026, 11, 20)));
      expect(item1.slot.day, equals(DayOfWeek.friday));
      expect(item1.slot.startTime.hour, equals(14));
      expect(item1.slot.startTime.minute, equals(0));
      expect(item1.slot.endTime.hour, equals(15));
      expect(item1.slot.endTime.minute, equals(30));
      expect(item1.slot.isExtra, isTrue);
      expect(item1.slot.room, equals('Room 302'));
      expect(item1.slot.block, equals('Block B'));

      // 2026-11-22 is a Sunday
      final item2 = pkg.specialClasses[1];
      expect(item2.subjectName, equals('Robotics Seminar'));
      expect(item2.slot.specificDate, equals(DateTime(2026, 11, 22)));
      expect(item2.slot.day, equals(DayOfWeek.sunday));
      expect(item2.isStandaloneSpecialSubject, isTrue);
    });

    test('Parses raw list of special one-off class objects', () {
      final rawListJson = '''
[
  {
    "subject": "Physics Lab",
    "date": "2026-11-25",
    "startTime": "09:00",
    "endTime": "12:00"
  }
]
''';

      final pkg = TimetableImportUtils.parseInputToImportPackage(rawListJson, {});
      expect(pkg.hasSpecialClasses, isTrue);
      expect(pkg.specialClasses.length, equals(1));

      final item = pkg.specialClasses.first;
      expect(item.subjectName, equals('Physics Lab'));
      // 2026-11-25 is a Wednesday
      expect(item.slot.day, equals(DayOfWeek.wednesday));
      expect(item.slot.isSpecialClass, isTrue);
    });
  });
}
