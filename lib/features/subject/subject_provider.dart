import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../../services/database_service.dart';
import '../../services/notification_service.dart';
import 'subject_model.dart';

class TimetableUpdateResult {
  final int matchedSubjects;
  final int newSubjects;
  final int retiredSubjects;
  final int changedSubjectSchedules;

  const TimetableUpdateResult({
    required this.matchedSubjects,
    required this.newSubjects,
    required this.retiredSubjects,
    required this.changedSubjectSchedules,
  });
}

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

  Future<TimetableUpdateResult> applyTimetableUpdateFromDate(
    List<Subject> importedSubjects,
    DateTime effectiveFromDate,
  ) async {
    final normalizedEffectiveFrom = normalizeDate(effectiveFromDate) ?? effectiveFromDate;
    final originalSubjectIds = _subjects.map((subject) => subject.id).toSet();
    final imported = List<Subject>.from(importedSubjects);
    final updatedSubjects = List<Subject>.from(_subjects);
    final matchedExistingIds = <String>{};

    int matchedCount = 0;
    int changedCount = 0;

    for (final importedSubject in imported) {
      final matchIndex = _findMatchingSubjectIndex(
        existingSubjects: updatedSubjects,
        importedSubject: importedSubject,
        matchedExistingIds: matchedExistingIds,
      );

      final importedWeeklySlots = importedSubject.schedule
          .where((slot) => !slot.isSpecialClass)
          .map(
            (slot) => slot.copyWith(
              effectiveFrom: normalizedEffectiveFrom,
              clearEffectiveUntil: true,
            ),
          )
          .toList();

      if (matchIndex == -1) {
        final seededSchedule = importedSubject.schedule.map((slot) {
          if (slot.isSpecialClass) {
            return slot;
          }
          return slot.copyWith(
            effectiveFrom: normalizedEffectiveFrom,
            clearEffectiveUntil: true,
          );
        }).toList();

        updatedSubjects.add(importedSubject.copyWith(schedule: seededSchedule));
        continue;
      }

      matchedCount++;
      final existing = updatedSubjects[matchIndex];
      matchedExistingIds.add(existing.id);

      final oldWeeklyBeforeCutoff = _closeWeeklySlotsFromDate(
        existing.schedule,
        normalizedEffectiveFrom,
      );

      final mergedSchedule = <TimeSlot>[
        ...oldWeeklyBeforeCutoff,
        ...importedWeeklySlots,
      ];

      final updatedSubject = existing.copyWith(
        name: importedSubject.name,
        acronym: importedSubject.acronym,
        schedule: _sortedSchedule(mergedSchedule),
      );

      if (_scheduleFingerprint(existing.schedule) !=
          _scheduleFingerprint(updatedSubject.schedule)) {
        changedCount++;
      }

      updatedSubjects[matchIndex] = updatedSubject;
    }

    int retiredCount = 0;

    for (int i = 0; i < updatedSubjects.length; i++) {
      final subject = updatedSubjects[i];
      if (!originalSubjectIds.contains(subject.id)) {
        continue;
      }
      if (matchedExistingIds.contains(subject.id)) {
        continue;
      }

      final trimmedSchedule = _closeWeeklySlotsFromDate(
        subject.schedule,
        normalizedEffectiveFrom,
      );

      final hadWeeklySlots = subject.schedule.any((slot) => !slot.isSpecialClass);
      final hasWeeklyAfterTrim = trimmedSchedule.any((slot) => !slot.isSpecialClass);
      if (hadWeeklySlots && !hasWeeklyAfterTrim) {
        retiredCount++;
      }

      if (_scheduleFingerprint(subject.schedule) != _scheduleFingerprint(trimmedSchedule)) {
        changedCount++;
        updatedSubjects[i] = subject.copyWith(schedule: _sortedSchedule(trimmedSchedule));
      }
    }

    _subjects = updatedSubjects;
    await _databaseService.saveSubjects(_subjects);
    await _refreshAttendanceReminders();
    notifyListeners();

    return TimetableUpdateResult(
      matchedSubjects: matchedCount,
      newSubjects: imported.length - matchedCount,
      retiredSubjects: retiredCount,
      changedSubjectSchedules: changedCount,
    );
  }

  int _findMatchingSubjectIndex({
    required List<Subject> existingSubjects,
    required Subject importedSubject,
    required Set<String> matchedExistingIds,
  }) {
    final importedAcronym = _normalizeToken(importedSubject.acronym);
    if (importedAcronym.isNotEmpty) {
      final byAcronym = existingSubjects.indexWhere(
        (existing) =>
            !matchedExistingIds.contains(existing.id) &&
            _normalizeToken(existing.acronym) == importedAcronym,
      );
      if (byAcronym != -1) {
        return byAcronym;
      }
    }

    final importedName = _normalizeToken(importedSubject.name);
    return existingSubjects.indexWhere(
      (existing) =>
          !matchedExistingIds.contains(existing.id) &&
          _normalizeToken(existing.name) == importedName,
    );
  }

  List<TimeSlot> _closeWeeklySlotsFromDate(
    List<TimeSlot> schedule,
    DateTime effectiveFrom,
  ) {
    final cutoffEnd = effectiveFrom.subtract(const Duration(days: 1));
    final normalizedCutoffEnd = normalizeDate(cutoffEnd) ?? cutoffEnd;

    return schedule.where((slot) {
      if (slot.isSpecialClass) {
        return true;
      }
      final from = normalizeDate(slot.effectiveFrom);
      if (from != null && !from.isBefore(effectiveFrom)) {
        return false;
      }
      return true;
    }).map((slot) {
      if (slot.isSpecialClass) {
        return slot;
      }

      final until = normalizeDate(slot.effectiveUntil);
      if (until != null && until.isBefore(effectiveFrom)) {
        return slot;
      }

      return slot.copyWith(effectiveUntil: normalizedCutoffEnd);
    }).toList();
  }

  String _normalizeToken(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  List<TimeSlot> _sortedSchedule(List<TimeSlot> schedule) {
    final sorted = List<TimeSlot>.from(schedule);
    sorted.sort((a, b) {
      final aSpecific = normalizeDate(a.specificDate);
      final bSpecific = normalizeDate(b.specificDate);
      if (aSpecific != null && bSpecific != null) {
        final compareSpecific = aSpecific.compareTo(bSpecific);
        if (compareSpecific != 0) {
          return compareSpecific;
        }
      }

      if (aSpecific == null && bSpecific != null) {
        return -1;
      }
      if (aSpecific != null && bSpecific == null) {
        return 1;
      }

      final compareDay = a.day.index.compareTo(b.day.index);
      if (compareDay != 0) {
        return compareDay;
      }

      final aStart = a.startTime.hour * 60 + a.startTime.minute;
      final bStart = b.startTime.hour * 60 + b.startTime.minute;
      if (aStart != bStart) {
        return aStart.compareTo(bStart);
      }

      final aFrom = normalizeDate(a.effectiveFrom);
      final bFrom = normalizeDate(b.effectiveFrom);
      if (aFrom == null && bFrom != null) {
        return -1;
      }
      if (aFrom != null && bFrom == null) {
        return 1;
      }
      if (aFrom != null && bFrom != null) {
        final compareFrom = aFrom.compareTo(bFrom);
        if (compareFrom != 0) {
          return compareFrom;
        }
      }

      final aEnd = a.endTime.hour * 60 + a.endTime.minute;
      final bEnd = b.endTime.hour * 60 + b.endTime.minute;
      return aEnd.compareTo(bEnd);
    });
    return sorted;
  }

  String _scheduleFingerprint(List<TimeSlot> schedule) {
    final sorted = _sortedSchedule(schedule);
    return sorted
        .map(
          (slot) => [
            slot.day.index,
            slot.startTime.hour,
            slot.startTime.minute,
            slot.endTime.hour,
            slot.endTime.minute,
            normalizeDate(slot.specificDate)?.toIso8601String() ?? '',
            normalizeDate(slot.effectiveFrom)?.toIso8601String() ?? '',
            normalizeDate(slot.effectiveUntil)?.toIso8601String() ?? '',
          ].join('|'),
        )
        .join('~');
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

  Future<void> updateManualAttendanceCounts({
    required String subjectId,
    required int classesHeld,
    required int classesAttended,
    required DateTime effectiveFrom,
  }) async {
    final index = _subjects.indexWhere((subject) => subject.id == subjectId);
    if (index == -1) {
      return;
    }

    final updated = _subjects[index].copyWithManualAttendanceOverride(
      effectiveFrom: effectiveFrom,
      classesHeld: classesHeld,
      classesAttended: classesAttended,
    );

    _subjects[index] = updated;
    await _databaseService.saveSubjects(_subjects);
    notifyListeners();
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
    final todaysSubjects = <Subject>[];

    for (var subject in _subjects) {
      final todaysSchedule = subject.schedule.where((s) => s.occursOnDate(date)).toList();
      if (todaysSchedule.isNotEmpty) {
        todaysSubjects.add(subject.copyWith(schedule: todaysSchedule));
      }
    }
    return todaysSubjects;
  }

  /// Get classes for a date, including those marked as holidays
  List<Subject> getClassesForDateIgnoreHoliday(DateTime date) {
    final todaysSubjects = <Subject>[];

    for (var subject in _subjects) {
      final todaysSchedule = subject.schedule.where((s) => s.occursOnDate(date)).toList();
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
    return _subjects.any((subject) => subject.schedule.any((s) => s.occursOnDate(date)));
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
    for (var subject in _subjects) {
      final slotsForDay = subject.schedule.where((s) => s.occursOnDate(date));
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

    for (var subject in _subjects) {
      final slotsForDay = subject.schedule.where((s) => s.occursOnDate(date)).toList();
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
