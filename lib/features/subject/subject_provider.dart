import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../../services/database_service.dart';
import '../../services/notification_service.dart';
import 'subject_model.dart';

class SubjectProvider with ChangeNotifier {
  List<Subject> _subjects = [];
  final DatabaseService _databaseService = DatabaseService();
  final AttendanceProvider _attendanceProvider;
  bool _isLoading = true;

  List<Subject> get subjects => _subjects;
  bool get isLoading => _isLoading;

  SubjectProvider(this._attendanceProvider) {
    _loadSubjects();
    _attendanceProvider.addListener(notifyListeners); // Listen for changes in attendance
  }

  @override
  void dispose() {
    _attendanceProvider.removeListener(notifyListeners);
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    try {
      _subjects = await _databaseService.loadSubjects();
      await _refreshAttendanceReminders();
    } catch (e) {
      // Silently fail - will use empty list as default
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Reload subjects from database (useful after clearing data)
  Future<void> reloadSubjects() async {
    _isLoading = true;
    notifyListeners();
    await _loadSubjects();
  }

  Future<void> addSubject(Subject subject) async {
    try {
      _subjects.add(subject);
      await _databaseService.saveSubjects(_subjects);
      await _refreshAttendanceReminders();
      notifyListeners();
    } catch (e) {
      // Rollback
      _subjects.removeWhere((s) => s.id == subject.id);
      rethrow;
    }
  }

  Future<void> bulkImportSubjects(List<Subject> subjects) async {
    _subjects.addAll(subjects);
    await _databaseService.saveSubjects(_subjects);
    await _refreshAttendanceReminders();
    notifyListeners();
  }

  Future<void> updateSubject(Subject oldSubject, Subject newSubject) async {
    final index = _subjects.indexWhere((s) => s.id == oldSubject.id);
    if (index != -1) {
      _subjects[index] = newSubject;
      await _databaseService.saveSubjects(_subjects);
      await _refreshAttendanceReminders();
      await _attendanceProvider.updateSubjectName(oldSubject.name, newSubject.name);
      notifyListeners();
    }
  }

  Future<void> deleteSubject(Subject subject) async {
    _subjects.removeWhere((s) => s.id == subject.id);
    await _databaseService.saveSubjects(_subjects);
    await _refreshAttendanceReminders();
    await _attendanceProvider.deleteRecordsForSubject(subject.id);
    notifyListeners();
  }

  Future<void> _refreshAttendanceReminders() async {
    try {
      await NotificationService().scheduleForSubjects(_subjects);
    } catch (e) {
      // Silently fail - notifications are non-critical
    }
  }

  double getAttendancePercentage(Subject subject) {
    final relevantRecords = _attendanceProvider.attendanceRecords
        .where((r) => r.subjectId == subject.id && r.status != AttendanceStatus.cancelled)
        .toList();

    if (relevantRecords.isEmpty) {
      return 100.0;
    }

    final attendedCount = relevantRecords
        .where((r) => r.status == AttendanceStatus.attended)
        .length;

    return (attendedCount / relevantRecords.length) * 100;
  }

  List<Subject> getClassesForDate(DateTime date) {
    // Inefficient conversion, but works for now. Should be improved.
    final dayOfWeek = DayOfWeek.values[date.weekday - 1];
    final todaysSubjects = <Subject>[];

    for (var subject in _subjects) {
      final todaysSchedule = subject.schedule.where((s) => s.day == dayOfWeek).toList();
      if (todaysSchedule.isNotEmpty) {
        todaysSubjects.add(subject.copyWith(schedule: todaysSchedule));
      }
    }
    return todaysSubjects;
  }

  /// Get classes for a date, including those marked as holidays
  List<Subject> getClassesForDateIgnoreHoliday(DateTime date) {
    final dayOfWeek = DayOfWeek.values[date.weekday - 1];
    final todaysSubjects = <Subject>[];

    for (var subject in _subjects) {
      final todaysSchedule = subject.schedule.where((s) => s.day == dayOfWeek).toList();
      if (todaysSchedule.isNotEmpty) {
        todaysSubjects.add(subject.copyWith(schedule: todaysSchedule));
      }
    }
    return todaysSubjects;
  }

  Attendance? getAttendanceForSubjectOnDate(
    String subjectId,
    DateTime date, {
    String? slotKey,
  }) {
    return _attendanceProvider.getAttendanceForSubjectOnDate(
      subjectId,
      date,
      slotKey: slotKey,
    );
  }

  Future<void> markAttendance(
    String subjectId,
    DateTime date,
    AttendanceStatus status, {
    String? slotKey,
  }) async {
    await _attendanceProvider.markAttendance(
      subjectId,
      date,
      status,
      slotKey: slotKey,
    );
  }

  Future<void> markDayAsHoliday(DateTime date) async {
    final classesForDay = getClassesForDate(date);
    for (var subject in classesForDay) {
      for (final slot in subject.schedule) {
        await _attendanceProvider.markAttendance(
          subject.id,
          date,
          AttendanceStatus.cancelled,
          slotKey: slot.slotKey,
        );
      }
    }
  }

  Future<void> markDayAsAbsent(DateTime date) async {
    final classesForDay = getClassesForDate(date);
    for (var subject in classesForDay) {
      for (final slot in subject.schedule) {
        await _attendanceProvider.markAttendance(
          subject.id,
          date,
          AttendanceStatus.absent,
          slotKey: slot.slotKey,
        );
      }
    }
  }

  /// Check if a date is marked as a holiday
  bool isHoliday(DateTime date) {
    return _attendanceProvider.isHoliday(date);
  }

  /// Check if there are any classes scheduled for a given date (day of week)
  bool hasClassesOnDate(DateTime date) {
    final dayOfWeek = DayOfWeek.values[date.weekday - 1];
    return _subjects.any((subject) => subject.schedule.any((s) => s.day == dayOfWeek));
  }

  /// Get all cancelled (holiday) attendance records for a specific date
  List<String> getHolidaySubjectIds(DateTime date) {
    return _attendanceProvider.attendanceRecords
        .where((record) => record.date == date && record.status == AttendanceStatus.cancelled)
        .map((record) => record.subjectId)
        .toList();
  }

  /// Delete attendance record for a specific subject on a specific date
  Future<void> unmarkAttendance(String subjectId, DateTime date, {String? slotKey}) async {
    await _attendanceProvider.deleteRecordForSubjectOnDate(
      subjectId,
      date,
      slotKey: slotKey,
    );
  }

  Future<void> unmarkDayAsHoliday(DateTime date) async {
    // Delete all records for this date to completely unmark the holiday
    // This allows the user to mark individual classes as attended/absent later
    await _attendanceProvider.deleteRecordsForDate(date);
  }

  Future<void> markDayAsPresent(DateTime date) async {
    // Get all subjects (including those marked as holiday)
    final dayOfWeek = DayOfWeek.values[date.weekday - 1];
    for (var subject in _subjects) {
      final slotsForDay = subject.schedule.where((s) => s.day == dayOfWeek);
      for (final slot in slotsForDay) {
        await _attendanceProvider.markAttendance(
          subject.id,
          date,
          AttendanceStatus.attended,
          slotKey: slot.slotKey,
        );
      }
    }
  }

  /// Auto-mark all unmarked classes as present at end of day
  /// Only marks classes that don't have any attendance record
  /// Skips if the day is marked as a holiday
  Future<void> autoMarkUnmarkedClassesAsPresent(DateTime date) async {
    // Skip if day is marked as holiday
    if (_attendanceProvider.isHoliday(date)) {
      return;
    }

    final dayOfWeek = DayOfWeek.values[date.weekday - 1];
    
    for (var subject in _subjects) {
      final slotsForDay = subject.schedule.where((s) => s.day == dayOfWeek).toList();
      if (slotsForDay.isEmpty) {
        continue;
      }

      for (final slot in slotsForDay) {
        final attendance = _attendanceProvider.getAttendanceForSubjectOnDate(
          subject.id,
          date,
          slotKey: slot.slotKey,
        );

        if (attendance == null) {
          await _attendanceProvider.markAttendance(
            subject.id,
            date,
            AttendanceStatus.attended,
            slotKey: slot.slotKey,
          );
        }
      }
    }
  }
}
