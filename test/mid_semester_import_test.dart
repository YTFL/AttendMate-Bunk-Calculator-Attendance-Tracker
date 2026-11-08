import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/utils/timetable_import_utils.dart';

void main() {
  group('Mid-Semester JSON Import Tests', () {
    test('Parses mid-semester JSON with top-level effectiveFrom date', () {
      final jsonInput = '''
{
  "effectiveFrom": "2026-11-15",
  "subjects": [
    {
      "name": "Cloud Computing",
      "acronym": "CC",
      "schedule": [
        {"day": "tuesday", "startTime": "10:00", "endTime": "11:30"},
        {"day": "thursday", "startTime": "14:00", "endTime": "15:30"}
      ]
    }
  ]
}
''';

      final pkg = TimetableImportUtils.parseInputToImportPackage(jsonInput, {});
      expect(pkg.effectiveFrom, equals(DateTime(2026, 11, 15)));
      expect(pkg.standardSubjects.length, equals(1));

      final subject = pkg.standardSubjects.first;
      expect(subject.name, equals('Cloud Computing'));
      expect(subject.schedule.length, equals(2));
      expect(subject.schedule.every((slot) => slot.effectiveFrom == DateTime(2026, 11, 15)), isTrue);
    });

    test('Parses subject-level effectiveFrom override', () {
      final jsonInput = '''
{
  "effectiveFrom": "2026-10-01",
  "subjects": [
    {
      "name": "General Subject",
      "schedule": [
        {"day": "monday", "startTime": "09:00", "endTime": "10:00"}
      ]
    },
    {
      "name": "Late Addition Subject",
      "effectiveFrom": "2026-11-20",
      "schedule": [
        {"day": "friday", "startTime": "14:00", "endTime": "16:00"}
      ]
    }
  ]
}
''';

      final pkg = TimetableImportUtils.parseInputToImportPackage(jsonInput, {});
      expect(pkg.standardSubjects.length, equals(2));

      final sub1 = pkg.standardSubjects[0];
      expect(sub1.schedule.first.effectiveFrom, equals(DateTime(2026, 10, 1)));

      final sub2 = pkg.standardSubjects[1];
      expect(sub2.schedule.first.effectiveFrom, equals(DateTime(2026, 11, 20)));
    });
  });
}
