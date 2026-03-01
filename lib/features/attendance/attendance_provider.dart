import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/database_service.dart';
import 'attendance_model.dart';

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
  
  /// Reload attendance from database (useful after clearing data)
  Future<void> reloadAttendance() async {
    _isLoading = true;
    notifyListeners();
    await _loadAttendance();
  }

  Future<void> markAttendance(
    String subjectId,
    DateTime date,
    AttendanceStatus status, {
    String? slotKey,
  }) async {
    try {
      // Remove any existing record for this subject on this day to avoid duplicates
      _attendanceRecords.removeWhere(
        (record) =>
            record.subjectId == subjectId &&
            record.date == date &&
            (record.slotKey ?? '') == (slotKey ?? ''),
      );

      final newRecord = Attendance(
        subjectId: subjectId,
        date: date,
        status: status,
        slotKey: slotKey,
      );
      _attendanceRecords.add(newRecord);

      await _databaseService.saveAttendance(_attendanceRecords);
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
      if (slotKey != null) {
        return _attendanceRecords.firstWhere(
          (record) =>
              record.subjectId == subjectId &&
              record.date == date &&
              (record.slotKey ?? '') == slotKey,
        );
      }

      return _attendanceRecords.firstWhere((record) {
        return record.subjectId == subjectId &&
            record.date == date &&
            ((record.slotKey ?? '').isEmpty);
      });
    } catch (e) {
      return null; // No record found
    }
  }

  bool isHoliday(DateTime date) {
    // A day is a holiday if all records for that day are 'cancelled'
    final recordsForDay = _attendanceRecords.where((record) => record.date == date).toList();
    if (recordsForDay.isEmpty) return false;
    return recordsForDay.every((record) => record.status == AttendanceStatus.cancelled);
  }

  Future<void> updateSubjectName(String oldName, String newName) async {
    // This method is no longer needed as we are using subjectId
    // However, if you have old data that needs migration, you would implement that here.
  }

  Future<void> deleteRecordsForSubject(String subjectId) async {
    _attendanceRecords.removeWhere((record) => record.subjectId == subjectId);
    await _databaseService.saveAttendance(_attendanceRecords);
    notifyListeners();
  }

  /// Delete all attendance records for a specific date
  Future<void> deleteRecordsForDate(DateTime date) async {
    _attendanceRecords.removeWhere((record) => record.date == date);
    await _databaseService.saveAttendance(_attendanceRecords);
    notifyListeners();
  }

  /// Delete attendance record for a specific subject on a specific date
  Future<void> deleteRecordForSubjectOnDate(
    String subjectId,
    DateTime date, {
    String? slotKey,
  }) async {
    _attendanceRecords.removeWhere(
      (record) =>
          record.subjectId == subjectId &&
          record.date == date &&
          (slotKey == null || (record.slotKey ?? '') == slotKey),
    );
    await _databaseService.saveAttendance(_attendanceRecords);
    notifyListeners();
  }
}
