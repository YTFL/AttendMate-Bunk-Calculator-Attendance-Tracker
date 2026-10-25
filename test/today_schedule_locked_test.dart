import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:attendmate/features/attendance/attendance_model.dart';
import 'package:attendmate/features/attendance/attendance_provider.dart';
import 'package:attendmate/features/calendar/calendar_utils.dart';
import 'package:attendmate/features/home/todays_schedule.dart';
import 'package:attendmate/features/semester/semester_model.dart';
import 'package:attendmate/features/semester/semester_provider.dart';
import 'package:attendmate/features/settings/swipe_action_provider.dart';
import 'package:attendmate/features/settings/swipeable_card.dart';
import 'package:attendmate/features/settings/time_format_provider.dart';
import 'package:attendmate/features/subject/subject_model.dart';
import 'package:attendmate/features/subject/subject_provider.dart';

// In-memory test mock for AttendanceProvider
class TestAttendanceProvider extends AttendanceProvider {
  final List<Attendance> _records = [];

  @override
  List<Attendance> get attendanceRecords => _records;

  @override
  bool get isLoading => false;

  @override
  Future<void> markAttendance(
    String subjectId,
    DateTime date,
    AttendanceStatus status, {
    String? slotKey,
  }) async {
    _records.removeWhere(
      (r) =>
          r.subjectId == subjectId &&
          CalendarUtils.isSameDay(r.date, date) &&
          (r.slotKey ?? '') == (slotKey ?? ''),
    );
    _records.add(Attendance(
      subjectId: subjectId,
      date: date,
      status: status,
      slotKey: slotKey,
    ));
    notifyListeners();
  }

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

  @override
  Future<void> deleteRecordsForDate(DateTime date) async {
    _records.removeWhere((r) => CalendarUtils.isSameDay(r.date, date));
    notifyListeners();
  }
}

// Test SubjectProvider that avoids sqflite calls
class TestSubjectProvider extends SubjectProvider {
  final List<Subject> _testSubjects;

  TestSubjectProvider(super.attendanceProvider, this._testSubjects);

  @override
  List<Subject> get subjects => _testSubjects;

  @override
  bool get isLoading => false;

  @override
  List<Subject> getClassesForDate(DateTime date) {
    return _testSubjects
        .where((subject) => subject.schedule.any((slot) => slot.occursOnDate(date)))
        .toList();
  }
}

// Test SemesterProvider
class TestSemesterProvider extends SemesterProvider {
  final Semester? _testSemester;

  TestSemesterProvider(this._testSemester);

  @override
  Semester? get semester => _testSemester;

  @override
  bool get hasSemesterStarted => true;

  @override
  bool get hasSemesterEnded => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SubjectProvider Locked State Protection Tests', () {
    late TestAttendanceProvider attendanceProvider;
    late Subject subjectWithOverride;
    late Subject subjectWithoutOverride;
    late TestSubjectProvider subjectProvider;

    // Fixed test dates
    final overrideEffectiveDate = DateTime(2026, 8, 15);
    final pastDateLocked = DateTime(2026, 8, 10); // Monday, before Aug 15 -> locked for subjectWithOverride
    final pastDateUnlocked = DateTime(2026, 8, 17); // Monday, after Aug 15 -> unlocked

    setUp(() {
      attendanceProvider = TestAttendanceProvider();

      subjectWithOverride = Subject(
        id: 'sub-locked',
        name: 'Mathematics',
        acronym: 'MATH',
        color: Colors.blue,
        schedule: [
          TimeSlot(
            day: DayOfWeek.monday,
            startTime: const TimeOfDay(hour: 9, minute: 0),
            endTime: const TimeOfDay(hour: 10, minute: 0),
          ),
        ],
        targetAttendance: 75,
      ).copyWithManualAttendanceOverride(
        effectiveFrom: overrideEffectiveDate,
        classesHeld: 10,
        classesAttended: 8,
      );

      subjectWithoutOverride = Subject(
        id: 'sub-open',
        name: 'Physics',
        acronym: 'PHYS',
        color: Colors.green,
        schedule: [
          TimeSlot(
            day: DayOfWeek.monday,
            startTime: const TimeOfDay(hour: 11, minute: 0),
            endTime: const TimeOfDay(hour: 12, minute: 0),
          ),
        ],
        targetAttendance: 75,
      );

      subjectProvider = TestSubjectProvider(
        attendanceProvider,
        [subjectWithOverride, subjectWithoutOverride],
      );
    });

    test('markAttendance does nothing if subject is locked on that date', () async {
      await subjectProvider.markAttendance(
        subjectWithOverride.id,
        pastDateLocked,
        AttendanceStatus.attended,
        slotKey: 'math_mon_9',
      );

      expect(attendanceProvider.attendanceRecords, isEmpty);

      // But unlocked date succeeds
      await subjectProvider.markAttendance(
        subjectWithOverride.id,
        pastDateUnlocked,
        AttendanceStatus.attended,
        slotKey: 'math_mon_9',
      );

      expect(attendanceProvider.attendanceRecords.length, equals(1));
    });

    test('unmarkAttendance does nothing if subject is locked on that date', () async {
      // Pre-populate a record
      await attendanceProvider.markAttendance(
        subjectWithOverride.id,
        pastDateLocked,
        AttendanceStatus.attended,
        slotKey: 'math_mon_9',
      );
      expect(attendanceProvider.attendanceRecords.length, equals(1));

      // Attempt to unmark via SubjectProvider
      await subjectProvider.unmarkAttendance(
        subjectWithOverride.id,
        pastDateLocked,
        slotKey: 'math_mon_9',
      );

      // Record should still remain because subject is locked
      expect(attendanceProvider.attendanceRecords.length, equals(1));
    });

    test('markDayAsHoliday only marks unlocked subjects on that date', () async {
      await subjectProvider.markDayAsHoliday(pastDateLocked);

      // Only Physics should be marked, Mathematics is locked
      expect(attendanceProvider.attendanceRecords.length, equals(1));
      expect(attendanceProvider.attendanceRecords.first.subjectId, equals(subjectWithoutOverride.id));
      expect(attendanceProvider.attendanceRecords.first.status, equals(AttendanceStatus.cancelled));
    });

    test('markDayAsAbsent only marks unlocked subjects on that date', () async {
      await subjectProvider.markDayAsAbsent(pastDateLocked);

      // Only Physics should be marked, Mathematics is locked
      expect(attendanceProvider.attendanceRecords.length, equals(1));
      expect(attendanceProvider.attendanceRecords.first.subjectId, equals(subjectWithoutOverride.id));
      expect(attendanceProvider.attendanceRecords.first.status, equals(AttendanceStatus.absent));
    });

    test('markDayAsPresent only marks unlocked subjects on that date', () async {
      await subjectProvider.markDayAsPresent(pastDateLocked);

      // Only Physics should be marked, Mathematics is locked
      expect(attendanceProvider.attendanceRecords.length, equals(1));
      expect(attendanceProvider.attendanceRecords.first.subjectId, equals(subjectWithoutOverride.id));
      expect(attendanceProvider.attendanceRecords.first.status, equals(AttendanceStatus.attended));
    });
  });

  group('TodaySchedule Widget Locked Display & Swiping Tests', () {
    late TestAttendanceProvider attendanceProvider;
    late Subject subjectLocked;
    late Subject subjectUnlocked;
    late Semester semester;
    late TimeFormatProvider timeFormatProvider;
    late SwipeActionProvider swipeActionProvider;

    final overrideDate = DateTime.now().add(const Duration(days: 1)); // Tomorrow, so previous dates are locked

    setUp(() {
      attendanceProvider = TestAttendanceProvider();

      final now = DateTime.now();
      final nowWeekday = DayOfWeek.values[now.weekday - 1];

      subjectLocked = Subject(
        id: 'sub-locked',
        name: 'Database Systems',
        acronym: 'DBS',
        color: Colors.indigo,
        schedule: [
          TimeSlot(
            day: nowWeekday,
            startTime: const TimeOfDay(hour: 9, minute: 0),
            endTime: const TimeOfDay(hour: 10, minute: 0),
          ),
        ],
        targetAttendance: 75,
      ).copyWithManualAttendanceOverride(
        effectiveFrom: overrideDate,
        classesHeld: 12,
        classesAttended: 10,
      );

      subjectUnlocked = Subject(
        id: 'sub-unlocked',
        name: 'Operating Systems',
        acronym: 'OS',
        color: Colors.teal,
        schedule: [
          TimeSlot(
            day: nowWeekday,
            startTime: const TimeOfDay(hour: 11, minute: 0),
            endTime: const TimeOfDay(hour: 12, minute: 0),
          ),
        ],
        targetAttendance: 75,
      );

      semester = Semester(
        startDate: now.subtract(const Duration(days: 30)),
        endDate: now.add(const Duration(days: 60)),
        targetPercentage: 75.0,
      );

      timeFormatProvider = TimeFormatProvider();
      swipeActionProvider = SwipeActionProvider();
    });

    Widget createWidgetUnderTest(List<Subject> subjects) {
      final subjectProvider = TestSubjectProvider(attendanceProvider, subjects);
      final semesterProvider = TestSemesterProvider(semester);

      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SubjectProvider>.value(value: subjectProvider),
          ChangeNotifierProvider<AttendanceProvider>.value(value: attendanceProvider),
          ChangeNotifierProvider<SemesterProvider>.value(value: semesterProvider),
          ChangeNotifierProvider<TimeFormatProvider>.value(value: timeFormatProvider),
          ChangeNotifierProvider<SwipeActionProvider>.value(value: swipeActionProvider),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TodaySchedule(),
          ),
        ),
      );
    }

    testWidgets('Displays locked banner and locked status for locked classes', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest([subjectLocked]));
      await tester.pumpAndSettle();

      // Should show banner because all classes today are locked before tomorrow
      expect(
        find.text('Classes on this date are locked due to manual count update.'),
        findsOneWidget,
      );

      // Should show Locked status text
      expect(find.text('Locked'), findsOneWidget);

      // Should show subtitle "Locked before DD/MM/YYYY"
      final formattedDay = overrideDate.day.toString().padLeft(2, '0');
      final formattedMonth = overrideDate.month.toString().padLeft(2, '0');
      final expectedDateStr = 'Locked before $formattedDay/$formattedMonth/${overrideDate.year}';
      expect(find.text(expectedDateStr), findsOneWidget);

      // Locked class must NOT have SwipeableCard
      expect(find.byType(SwipeableCard), findsNothing);

      // Locked class must NOT have holiday action IconButton
      expect(find.byIcon(Icons.celebration_outlined), findsNothing);
    });

    testWidgets('Shows SwipeableCard only for unlocked classes when mixed', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest([subjectLocked, subjectUnlocked]));
      await tester.pumpAndSettle();

      // Mixed classes: allLocked is false, so bulk buttons are visible
      expect(find.text('Holiday'), findsOneWidget);
      expect(find.text('Skip Day'), findsOneWidget);
      expect(find.text('Present'), findsOneWidget);

      // Exactly ONE SwipeableCard for the unlocked subject (Operating Systems)
      expect(find.byType(SwipeableCard), findsOneWidget);

      // Locked status shown for DBS
      expect(find.text('Locked'), findsOneWidget);
      expect(find.text('Database Systems'), findsOneWidget);
      expect(find.text('Operating Systems'), findsOneWidget);
    });

    testWidgets('Marking attendance immediately updates the UI from Awaiting Status to Attended without tab switch', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest([subjectUnlocked]));
      await tester.pumpAndSettle();

      final today = DateTime.now();

      // Before marking: status is Awaiting Status
      expect(find.text('Awaiting Status'), findsOneWidget);
      expect(find.text('Attended'), findsNothing);

      // Mark attendance
      final subjectProvider = Provider.of<SubjectProvider>(
        tester.element(find.byType(TodaySchedule)),
        listen: false,
      );
      await subjectProvider.markAttendance(
        subjectUnlocked.id,
        today,
        AttendanceStatus.attended,
        slotKey: subjectUnlocked.schedule.first.slotKey,
      );

      await tester.pumpAndSettle();

      // UI immediately reflects 'Attended'
      expect(find.text('Attended'), findsOneWidget);
      expect(find.text('Awaiting Status'), findsNothing);

      // Unmarking attendance also immediately reflects 'Awaiting Status'
      await subjectProvider.unmarkAttendance(
        subjectUnlocked.id,
        today,
        slotKey: subjectUnlocked.schedule.first.slotKey,
      );

      await tester.pumpAndSettle();
      expect(find.text('Awaiting Status'), findsOneWidget);
      expect(find.text('Attended'), findsNothing);

      // Drain the 1.5s debounce auto-sync timer
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Subject card trailing button shows Mark Holiday by default, when attended, and when absent, and X only when cancelled', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest([subjectUnlocked]));
      await tester.pumpAndSettle();

      final today = DateTime.now();
      final subjectProvider = Provider.of<SubjectProvider>(
        tester.element(find.byType(TodaySchedule)),
        listen: false,
      );

      // 1. Initial State (Awaiting Status) -> Shows Mark Holiday (celebration icon)
      expect(find.byTooltip('Mark Holiday'), findsOneWidget);
      expect(find.byTooltip('Unmark Holiday'), findsNothing);

      // 2. Mark as Attended -> Button continues to show Mark Holiday
      await subjectProvider.markAttendance(
        subjectUnlocked.id,
        today,
        AttendanceStatus.attended,
        slotKey: subjectUnlocked.schedule.first.slotKey,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Mark Holiday'), findsOneWidget);
      expect(find.byTooltip('Unmark Holiday'), findsNothing);

      // 3. Mark as Absent -> Button continues to show Mark Holiday
      await subjectProvider.markAttendance(
        subjectUnlocked.id,
        today,
        AttendanceStatus.absent,
        slotKey: subjectUnlocked.schedule.first.slotKey,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Mark Holiday'), findsOneWidget);
      expect(find.byTooltip('Unmark Holiday'), findsNothing);

      // 4. Tap the Mark Holiday button -> Status becomes Holiday (cancelled) and button switches to Unmark Holiday (X)
      await tester.tap(find.byTooltip('Mark Holiday'));
      await tester.pumpAndSettle();
      expect(find.text('Holiday'), findsWidgets);
      expect(find.byTooltip('Unmark Holiday'), findsOneWidget);
      expect(find.byTooltip('Mark Holiday'), findsNothing);

      // 5. Tap Unmark Holiday -> Status is unmarked, button returns to Mark Holiday
      await tester.tap(find.byTooltip('Unmark Holiday'));
      await tester.pumpAndSettle();
      expect(find.text('Awaiting Status'), findsOneWidget);
      expect(find.byTooltip('Mark Holiday'), findsOneWidget);
      expect(find.byTooltip('Unmark Holiday'), findsNothing);

      // Drain auto-sync debounce timer
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
