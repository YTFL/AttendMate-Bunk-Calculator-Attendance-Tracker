import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/features/attendance/attendance_model.dart';
import 'package:attendmate/features/subject/subject_model.dart';
import 'package:attendmate/utils/attendance_import_utils.dart';

void main() {
  final sampleSubjects = [
    Subject(
      id: 'sub-math',
      name: 'Mathematics',
      acronym: 'MTH',
      color: Colors.blue,
      schedule: [],
    ),
    Subject(
      id: 'sub-phy',
      name: 'Physics Lab',
      acronym: 'PHY',
      color: Colors.red,
      schedule: [],
    ),
    Subject(
      id: 'sub-cs',
      name: 'Computer Science',
      acronym: 'CS',
      color: Colors.green,
      schedule: [],
    ),
  ];

  group('AttendanceImportUtils - CSV Parsing', () {
    test('parses valid CSV with standard headers', () {
      const csv = '''date,subject,status,slot
2026-08-10,Mathematics,Present,09:00 - 10:00
2026-08-10,Physics Lab,Absent,10:00 - 11:00
2026-08-11,Computer Science,Present,11:00 - 12:00
2026-08-12,Mathematics,Holiday,''';

      final result = AttendanceImportUtils.parseCsv(csv, sampleSubjects);

      expect(result.totalRows, equals(4));
      expect(result.matchedCount, equals(4));
      expect(result.unmatchedCount, equals(0));
      expect(result.attendedCount, equals(2));
      expect(result.absentCount, equals(1));
      expect(result.cancelledCount, equals(1));
      expect(result.errors, isEmpty);
    });

    test('parses CSV with alternative status values (P, A, H, 1, 0)', () {
      const csv = '''Date,Subject,Status
2026-08-10,Mathematics,P
2026-08-11,Mathematics,1
2026-08-12,Mathematics,A
2026-08-13,Mathematics,0
2026-08-14,Mathematics,H''';

      final result = AttendanceImportUtils.parseCsv(csv, sampleSubjects);

      expect(result.matchedCount, equals(5));
      expect(result.items[0].status, equals(AttendanceStatus.attended));
      expect(result.items[1].status, equals(AttendanceStatus.attended));
      expect(result.items[2].status, equals(AttendanceStatus.absent));
      expect(result.items[3].status, equals(AttendanceStatus.absent));
      expect(result.items[4].status, equals(AttendanceStatus.cancelled));
    });

    test('handles unmatched subjects and collects errors', () {
      const csv = '''date,subject,status
2026-08-10,Unknown Subject,Present
2026-08-11,Mathematics,Present
invalid-date,Mathematics,Present
2026-08-12,Mathematics,UnknownStatus''';

      final result = AttendanceImportUtils.parseCsv(csv, sampleSubjects);

      expect(result.unmatchedSubjectNames, contains('Unknown Subject'));
      expect(result.errors.length, equals(2));
      expect(result.matchedCount, equals(1));
    });

    test('handles quotes and commas in CSV cells', () {
      const csv = '''"date","subject","status","slot"
"2026-08-10","Mathematics","Present","09:00, Room 101"''';

      final result = AttendanceImportUtils.parseCsv(csv, sampleSubjects);

      expect(result.matchedCount, equals(1));
      expect(result.items.first.slot, equals('09:00, Room 101'));
    });
  });

  group('AttendanceImportUtils - JSON Parsing', () {
    test('parses JSON list of attendance records', () {
      const json = '''[
        {"date": "2026-08-10", "subject": "Mathematics", "status": "Present", "slot": "09:00"},
        {"date": "2026-08-10", "subject": "PHY", "status": "Absent"},
        {"date": "2026-08-11", "subject": "CS", "status": "Holiday"}
      ]''';

      final result = AttendanceImportUtils.parseJson(json, sampleSubjects);

      expect(result.matchedCount, equals(3));
      expect(result.attendedCount, equals(1));
      expect(result.absentCount, equals(1));
      expect(result.cancelledCount, equals(1));
    });

    test('parses JSON with wrapper object containing "attendance"', () {
      const json = '''{
        "attendance": [
          {"date": "2026-08-10", "subject": "Mathematics", "status": "Present"}
        ]
      }''';

      final result = AttendanceImportUtils.parseJson(json, sampleSubjects);

      expect(result.matchedCount, equals(1));
      expect(result.items.first.matchedSubject?.name, equals('Mathematics'));
    });

    test('parses JSON with wrapper object containing "records" or "data"', () {
      const json = '''{
        "records": [
          {"date": "2026-08-10", "subject": "Mathematics", "status": "Present"},
          {"date": "2026-08-11", "subject": "CS", "status": "Absent"}
        ]
      }''';

      final result = AttendanceImportUtils.parseJson(json, sampleSubjects);

      expect(result.matchedCount, equals(2));
      expect(result.attendedCount, equals(1));
      expect(result.absentCount, equals(1));
    });

    test('parses JSON wrapped in markdown code fence (```json ... ```)', () {
      const jsonWithFences = '''```json
[
  {"date": "2026-08-10", "subject": "Mathematics", "status": "Present"},
  {"date": "2026-08-11", "subject": "CS", "status": "Absent"}
]
```''';

      final result = AttendanceImportUtils.parseJson(jsonWithFences, sampleSubjects);

      expect(result.matchedCount, equals(2));
      expect(result.attendedCount, equals(1));
      expect(result.absentCount, equals(1));
    });
  });

  group('AttendanceImportUtils - Subject Matching', () {
    test('matches by acronym', () {
      final matched = AttendanceImportUtils.matchSubject('MTH', sampleSubjects);
      expect(matched?.id, equals('sub-math'));
    });

    test('matches by partial/case-insensitive name', () {
      final matched = AttendanceImportUtils.matchSubject('physics', sampleSubjects);
      expect(matched?.id, equals('sub-phy'));
    });

    test('returns null for nonexistent subject', () {
      final matched = AttendanceImportUtils.matchSubject('Astronomy', sampleSubjects);
      expect(matched, isNull);
    });
  });

  group('AttendanceImportUtils - toAttendance Conversion', () {
    test('converts ParsedAttendanceItem to Attendance record', () {
      final item = ParsedAttendanceItem(
        date: DateTime(2026, 8, 10),
        rawSubjectName: 'Mathematics',
        matchedSubject: sampleSubjects[0],
        status: AttendanceStatus.attended,
        slot: '09:00 - 10:00',
      );

      final attendance = item.toAttendance();
      expect(attendance.subjectId, equals('sub-math'));
      expect(attendance.status, equals(AttendanceStatus.attended));
      expect(attendance.date, equals(DateTime(2026, 8, 10)));
      expect(attendance.slotKey, equals('09:00 - 10:00'));
    });

    test('throws StateError when converting unmatched item', () {
      final item = ParsedAttendanceItem(
        date: DateTime(2026, 8, 10),
        rawSubjectName: 'Unknown',
        matchedSubject: null,
        status: AttendanceStatus.attended,
      );

      expect(() => item.toAttendance(), throwsStateError);
    });
  });

  group('AttendanceImportUtils - Baseline Summary Parsing', () {
    test('parses summary baseline CSV correctly', () {
      const csvData = '''Subject,Classes Held,Classes Attended
Mathematics,20,16
Computer Science,15,12''';

      final result = AttendanceImportUtils.parseCsv(csvData, sampleSubjects);

      expect(result.directBaselines.length, equals(2));
      expect(result.directBaselines[0].subject.id, equals('sub-math'));
      expect(result.directBaselines[0].classesHeld, equals(20));
      expect(result.directBaselines[0].classesAttended, equals(16));
      expect(result.directBaselines[1].subject.id, equals('sub-cs'));
      expect(result.directBaselines[1].classesHeld, equals(15));
      expect(result.directBaselines[1].classesAttended, equals(12));
    });

    test('computes baselines per subject from granular class logs', () {
      final items = [
        ParsedAttendanceItem(
          date: DateTime(2026, 8, 10),
          rawSubjectName: 'Mathematics',
          matchedSubject: sampleSubjects[0],
          status: AttendanceStatus.attended,
        ),
        ParsedAttendanceItem(
          date: DateTime(2026, 8, 11),
          rawSubjectName: 'Mathematics',
          matchedSubject: sampleSubjects[0],
          status: AttendanceStatus.absent,
        ),
        ParsedAttendanceItem(
          date: DateTime(2026, 8, 12),
          rawSubjectName: 'Computer Science',
          matchedSubject: sampleSubjects[2],
          status: AttendanceStatus.attended,
        ),
      ];

      final result = AttendanceImportResult(
        items: items,
        unmatchedSubjectNames: {},
        errors: [],
        totalRows: 3,
      );

      final baselines = result.computeBaselinesPerSubject();
      expect(baselines.length, equals(2));
      final mathBaseline = baselines['sub-math'];
      expect(mathBaseline, isNotNull);
      expect(mathBaseline!.classesHeld, equals(2));
      expect(mathBaseline.classesAttended, equals(1));

      final csBaseline = baselines['sub-cs'];
      expect(csBaseline, isNotNull);
      expect(csBaseline!.classesHeld, equals(1));
      expect(csBaseline.classesAttended, equals(1));
    });
  });
}


