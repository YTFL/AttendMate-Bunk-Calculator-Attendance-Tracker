import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/database_service.dart';
import 'semester_model.dart';

class SemesterProvider with ChangeNotifier {
  Semester? _semester;
  final DatabaseService _databaseService = DatabaseService();
  bool _isLoading = true;

  Semester? get semester => _semester;
  bool get isLoading => _isLoading;
  
  /// Check if the semester has started (today is on or after the start date)
  bool get hasSemesterStarted {
    if (_semester == null) return false;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final startDate = DateTime(_semester!.startDate.year, _semester!.startDate.month, _semester!.startDate.day);
    return todayDate.isAtSameMomentAs(startDate) || todayDate.isAfter(startDate);
  }
  
  /// Check if the semester has ended (today is after the end date)
  bool get hasSemesterEnded {
    if (_semester == null) return false;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final endDate = DateTime(_semester!.endDate.year, _semester!.endDate.month, _semester!.endDate.day);
    return todayDate.isAfter(endDate);
  }
  
  /// Check if the semester is currently active (started and not ended)
  bool get isSemesterActive {
    return hasSemesterStarted && !hasSemesterEnded;
  }

  SemesterProvider() {
    _loadSemester();
  }

  Future<void> _loadSemester() async {
    try {
      final semester = await _databaseService.loadSemester();
      if (semester != null) {
        _semester = semester;
      }
    } catch (e) {
      // Silently fail - semester remains null
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateSemester(Semester semester) async {
    try {
      _semester = semester;
      await _databaseService.saveSemester(semester);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }
  
  /// Create a new semester and clear all old data
  Future<void> createNewSemester(Semester semester) async {
    try {
      // Clear all subjects and attendance data
      await _databaseService.clearAllData();
      
      // Save the new semester
      _semester = semester;
      await _databaseService.saveSemester(semester);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }
}
