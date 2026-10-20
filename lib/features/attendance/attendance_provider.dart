import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/backup_service.dart';
import '../../services/database_service.dart';
import '../calendar/calendar_utils.dart';
import 'attendance_model.dart';
import '../planner/planned_leave_model.dart';
import '../subject/subject_model.dart';

class AttendanceProvider with ChangeNotifier {
  List<Attendance> _attendanceRecords = [];
  final DatabaseService _databaseService = DatabaseService();
  bool _isLoading = true;

  List<Attendance> get attendanceRecords => _attendanceRecords;
  bool get isLoading => _isLoading;

  AttendanceProvider() {
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    try {
      _attendanceRecords = await _databaseService.loadAttendance();
    } catch (e) {
      // Silently fail - will use empty list as default
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Reload attendance from database (useful after clearing data or resuming from background)
  Future<void> reloadAttendance({bool showLoading = false}) async {
    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }
    await _loadAttendance();
  }

  Future<void> markAttendance(
    String subjectId,
    DateTime date,
    AttendanceStatus status, {
    String? slotKey,
  }) async {
    try {
      final normalizedDate = DateTime(date.year, date.month, date.day);
      final cleanSlotKey = slotKey ?? '';

      // Remove any existing record for this subject on this day that matches this slot or was a wildcard
      _attendanceRecords.removeWhere(
        (record) =>
            record.subjectId == subjectId &&
            CalendarUtils.isSameDay(record.date, normalizedDate) &&
            ((record.slotKey ?? '') == cleanSlotKey ||
             (record.slotKey ?? '').isEmpty ||
             cleanSlotKey.isEmpty),
      );

      final newRecord = Attendance(
        subjectId: subjectId,
        date: normalizedDate,
        status: status,
        slotKey: slotKey,
      );
      _attendanceRecords.add(newRecord);

      await _databaseService.saveSingleAttendance(newRecord);
      await BackupService().notifyDataChanged();
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> markMultipleAttendance(List<Attendance> records) async {
    if (records.isEmpty) return;
    try {
      final normalizedRecords = <Attendance>[];
      for (final record in records) {
        final normDate = DateTime(record.date.year, record.date.month, record.date.day);
        final cleanSlotKey = record.slotKey ?? '';
        _attendanceRecords.removeWhere(
          (r) =>
              r.subjectId == record.subjectId &&
              CalendarUtils.isSameDay(r.date, normDate) &&
              ((r.slotKey ?? '') == cleanSlotKey ||
               (r.slotKey ?? '').isEmpty ||
               cleanSlotKey.isEmpty),
        );
        final normRecord = Attendance(
          subjectId: record.subjectId,
          date: normDate,
          status: record.status,
          slotKey: record.slotKey,
        );
        _attendanceRecords.add(normRecord);
        normalizedRecords.add(normRecord);
      }
      await _databaseService.saveMultipleAttendanceIncremental(normalizedRecords);
      await BackupService().notifyDataChanged();
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Attendance? getAttendanceForSubjectOnDate(
    String subjectId,
    DateTime date, {
    String? slotKey,
  }) {
    try {
      final cleanSlotKey = slotKey ?? '';
      final matchingRecords = _attendanceRecords.where((record) {
        return record.subjectId == subjectId &&
            CalendarUtils.isSameDay(record.date, date);
      }).toList();

      if (matchingRecords.isEmpty) return null;

      if (cleanSlotKey.isNotEmpty) {
        // Look for exact slot match first
        final exactIndex = matchingRecords.indexWhere((r) => (r.slotKey ?? '') == cleanSlotKey);
        if (exactIndex != -1) return matchingRecords[exactIndex];

        // Fallback to wildcard (record marked for whole day without slotKey)
        final wildcardIndex = matchingRecords.indexWhere((r) => (r.slotKey ?? '').isEmpty);
        if (wildcardIndex != -1) return matchingRecords[wildcardIndex];

        return matchingRecords.first;
      }

      // No slotKey specified: prefer wildcard record
      final wildcardIndex = matchingRecords.indexWhere((r) => (r.slotKey ?? '').isEmpty);
      if (wildcardIndex != -1) return matchingRecords[wildcardIndex];
      return matchingRecords.first;
    } catch (e) {
      return null; // No record found
    }
  }

  bool isHoliday(DateTime date) {
    // A day is a holiday if all records for that day are 'cancelled'
    final recordsForDay = _attendanceRecords.where((record) => CalendarUtils.isSameDay(record.date, date)).toList();
    if (recordsForDay.isEmpty) return false;
    return recordsForDay.every((record) => record.status == AttendanceStatus.cancelled);
  }

  Future<void> deleteRecordsForSubject(String subjectId) async {
    _attendanceRecords.removeWhere((record) => record.subjectId == subjectId);
    await _databaseService.deleteAttendanceForSubject(subjectId);
    notifyListeners();
  }

  /// Delete attendance records for a specific subject on or after a given date
  Future<void> deleteRecordsForSubjectFromDate(String subjectId, DateTime fromDate) async {
    final normFromDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
    _attendanceRecords.removeWhere((record) {
      if (record.subjectId != subjectId) return false;
      final normRecordDate = DateTime(record.date.year, record.date.month, record.date.day);
      return !normRecordDate.isBefore(normFromDate);
    });
    await _databaseService.deleteAttendanceForSubjectFromDate(subjectId, normFromDate);
    notifyListeners();
  }

  /// Delete all attendance records for a specific date
  Future<void> deleteRecordsForDate(DateTime date) async {
    final normDate = DateTime(date.year, date.month, date.day);
    _attendanceRecords.removeWhere((record) => CalendarUtils.isSameDay(record.date, normDate));
    await _databaseService.deleteAttendanceForDate(normDate);
    await BackupService().notifyDataChanged();
    notifyListeners();
  }

  /// Delete attendance record for a specific subject on a specific date
  Future<void> deleteRecordForSubjectOnDate(
    String subjectId,
    DateTime date, {
    String? slotKey,
  }) async {
    final normDate = DateTime(date.year, date.month, date.day);
    final cleanSlotKey = slotKey ?? '';
    _attendanceRecords.removeWhere(
      (record) =>
          record.subjectId == subjectId &&
          CalendarUtils.isSameDay(record.date, normDate) &&
          (cleanSlotKey.isEmpty || (record.slotKey ?? '') == cleanSlotKey || (record.slotKey ?? '').isEmpty),
    );
    await _databaseService.deleteSingleAttendance(
      subjectId: subjectId,
      date: normDate,
      slotKey: slotKey,
    );
    await BackupService().notifyDataChanged();
    notifyListeners();
  }

  /// Mark all class slots falling within active planned leaves as absent across the entire leave duration (including future dates).
  Future<void> syncPlannedLeavesWithAttendance({
    required List<PlannedLeave> plannedLeaves,
    required List<Subject> subjects,
  }) async {
    if (plannedLeaves.isEmpty || subjects.isEmpty) return;

    final recordsToMark = <Attendance>[];

    for (final leave in plannedLeaves) {
      DateTime current = DateTime(leave.startDate.year, leave.startDate.month, leave.startDate.day);
      final end = DateTime(leave.endDate.year, leave.endDate.month, leave.endDate.day);

      while (!current.isAfter(end)) {
        for (final subject in subjects) {
          if (leave.affectedSubjectIds.isNotEmpty && !leave.affectedSubjectIds.contains(subject.id)) {
            continue;
          }

          for (final slot in subject.schedule) {
            if (slot.occursOnDate(current)) {
              final slotStart = DateTime(current.year, current.month, current.day, slot.startTime.hour, slot.startTime.minute);
              final slotEnd = DateTime(current.year, current.month, current.day, slot.endTime.hour, slot.endTime.minute);

              if (slotStart.isBefore(leave.endDate) && slotEnd.isAfter(leave.startDate)) {
                final hasRecord = _attendanceRecords.any(
                  (r) =>
                      r.subjectId == subject.id &&
                      r.date.year == current.year &&
                      r.date.month == current.month &&
                      r.date.day == current.day &&
                      (r.slotKey == null || r.slotKey == slot.slotKey || r.slotKey!.isEmpty),
                );

                if (!hasRecord) {
                  recordsToMark.add(Attendance(
                    subjectId: subject.id,
                    date: current,
                    status: AttendanceStatus.absent,
                    slotKey: slot.slotKey,
                  ));
                }
              }
            }
          }
        }
        current = current.add(const Duration(days: 1));
      }
    }

    if (recordsToMark.isNotEmpty) {
      await markMultipleAttendance(recordsToMark);
    }
  }

  /// Cleans up absent records that were tied to a removed/edited planned leave (if not covered by other remaining leaves).
  Future<void> cleanupPlannedLeaveAttendance({
    required PlannedLeave deletedLeave,
    required List<PlannedLeave> remainingLeaves,
    required List<Subject> subjects,
  }) async {
    if (subjects.isEmpty) return;

    DateTime current = DateTime(deletedLeave.startDate.year, deletedLeave.startDate.month, deletedLeave.startDate.day);
    final end = DateTime(deletedLeave.endDate.year, deletedLeave.endDate.month, deletedLeave.endDate.day);

    while (!current.isAfter(end)) {
      for (final subject in subjects) {
        if (deletedLeave.affectedSubjectIds.isNotEmpty && !deletedLeave.affectedSubjectIds.contains(subject.id)) {
          continue;
        }

        for (final slot in subject.schedule) {
          if (slot.occursOnDate(current)) {
            final slotStart = DateTime(current.year, current.month, current.day, slot.startTime.hour, slot.startTime.minute);
            final slotEnd = DateTime(current.year, current.month, current.day, slot.endTime.hour, slot.endTime.minute);

            if (slotStart.isBefore(deletedLeave.endDate) && slotEnd.isAfter(deletedLeave.startDate)) {
              final isCoveredByOtherLeave = remainingLeaves.any((l) =>
                  (l.affectedSubjectIds.isEmpty || l.affectedSubjectIds.contains(subject.id)) &&
                  slotStart.isBefore(l.endDate) &&
                  slotEnd.isAfter(l.startDate));

              if (!isCoveredByOtherLeave) {
                final existingRecord = getAttendanceForSubjectOnDate(
                  subject.id,
                  current,
                  slotKey: slot.slotKey,
                );
                if (existingRecord != null && existingRecord.status == AttendanceStatus.absent) {
                  await deleteRecordForSubjectOnDate(
                    subject.id,
                    current,
                    slotKey: slot.slotKey,
                  );
                }
              }
            }
          }
        }
      }
      current = current.add(const Duration(days: 1));
    }
  }
}
