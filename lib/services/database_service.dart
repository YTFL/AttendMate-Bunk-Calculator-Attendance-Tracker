import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import '../features/attendance/attendance_model.dart';
import '../features/semester/semester_model.dart';
import '../features/subject/subject_model.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Initialize the database
  Future<void> init() async {
    try {
      // Skip database initialization on web platform
      if (kIsWeb) {
        _isInitialized = true;
        return;
      }
      
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'attendance_tracker.db');

      _database = await openDatabase(
        path,
        version: 4,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      
      _isInitialized = true;
    } catch (e) {
      debugPrint('DatabaseService init error: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    try {
      // Subjects table
      await db.execute('''
        CREATE TABLE subjects (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          acronym TEXT,
          color INTEGER NOT NULL,
          schedule TEXT NOT NULL,
          targetAttendance INTEGER NOT NULL,
          attendanceRecords TEXT NOT NULL
        )
      ''');

      // Attendance table
      await db.execute('''
        CREATE TABLE attendance (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          subjectId TEXT NOT NULL,
          date TEXT NOT NULL,
          slotKey TEXT NOT NULL,
          status TEXT NOT NULL,
          UNIQUE(subjectId, date, slotKey)
        )
      ''');

      // Semester table (single row)
      await db.execute('''
        CREATE TABLE semester (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          startDate TEXT NOT NULL,
          endDate TEXT NOT NULL,
          targetPercentage REAL NOT NULL
        )
      ''');

      // App updates tracking (single row)
      await db.execute('''
        CREATE TABLE app_updates (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          lastCheckDate TEXT,
          deferredUntil TEXT,
          ignoredVersion TEXT
        )
      ''');
    } catch (e) {
      debugPrint('DatabaseService onCreate error: $e');
      rethrow;
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    try {
      if (oldVersion < 2) {
        // Create app_updates table for new version
        await db.execute('''
          CREATE TABLE app_updates (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            lastCheckDate TEXT,
            deferredUntil TEXT,
            ignoredVersion TEXT
          )
        ''');
      }
      if (oldVersion < 3) {
        // Add acronym column to subjects table
        // Check if column already exists to avoid duplicate column error
        final tables = await db.rawQuery(
          "PRAGMA table_info(subjects)"
        );
        final columnExists = tables.any((col) => col['name'] == 'acronym');
        
        if (!columnExists) {
          await db.execute('''
            ALTER TABLE subjects ADD COLUMN acronym TEXT
          ''');
        }
      }
      if (oldVersion < 4) {
        await db.execute('DROP TABLE IF EXISTS attendance');
        await db.execute('''
          CREATE TABLE attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subjectId TEXT NOT NULL,
            date TEXT NOT NULL,
            slotKey TEXT NOT NULL,
            status TEXT NOT NULL,
            UNIQUE(subjectId, date, slotKey)
          )
        ''');
      }
    } catch (e) {
      debugPrint('DatabaseService onUpgrade error: $e');
      rethrow;
    }
  }

  Database _getDb() {
    if (kIsWeb) {
      throw Exception('Database operations not supported on web platform');
    }
    if (_database == null || !_isInitialized) {
      throw Exception('DatabaseService not initialized. Call init() first.');
    }
    return _database!;
  }

  // ==================== SUBJECTS ====================

  Future<void> saveSubjects(List<Subject> subjects) async {
    try {
      final db = _getDb();
      final batch = db.batch();

      // Clear existing subjects
      batch.delete('subjects');

      // Insert all subjects
      for (var subject in subjects) {
        batch.insert('subjects', {
          'id': subject.id,
          'name': subject.name,
          'acronym': subject.acronym,
          'color': subject.color.toARGB32(),
          'schedule': jsonEncode(subject.schedule.map((s) => s.toJson()).toList()),
          'targetAttendance': subject.targetAttendance,
          'attendanceRecords': jsonEncode(subject.attendanceRecords.map((a) => a.toJson()).toList()),
        });
      }

      await batch.commit(noResult: true);
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Subject>> loadSubjects() async {
    try {
      final db = _getDb();
      final List<Map<String, dynamic>> maps = await db.query('subjects');
      
      final subjects = maps.map((map) {
        return Subject(
          id: map['id'] as String,
          acronym: map['acronym'] as String?,
          name: map['name'] as String,
          color: Color(map['color'] as int),
          schedule: (jsonDecode(map['schedule'] as String) as List)
              .map((s) => TimeSlot.fromJson(s as Map<String, dynamic>))
              .toList(),
          targetAttendance: map['targetAttendance'] as int,
          attendanceRecords: (jsonDecode(map['attendanceRecords'] as String) as List)
              .map((a) => Attendance.fromJson(a as Map<String, dynamic>))
              .toList(),
        );
      }).toList();
      return subjects;
    } catch (e) {
      return [];
    }
  }

  // ==================== ATTENDANCE ====================

  Future<void> saveAttendance(List<Attendance> attendance) async {
    try {
      final db = _getDb();
      final batch = db.batch();

      // Clear existing attendance
      batch.delete('attendance');

      // Insert all attendance records
      for (var record in attendance) {
        batch.insert('attendance', {
          'subjectId': record.subjectId,
          'date': record.date.toIso8601String(),
          'slotKey': record.slotKey ?? '',
          'status': record.status.toString().split('.').last,
        });
      }

      await batch.commit(noResult: true);
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Attendance>> loadAttendance() async {
    try {
      final db = _getDb();
      final List<Map<String, dynamic>> maps = await db.query('attendance');
      
      final records = maps.map((map) {
        return Attendance(
          subjectId: map['subjectId'] as String,
          date: DateTime.parse(map['date'] as String),
          slotKey: map['slotKey'] as String?,
          status: AttendanceStatus.values.firstWhere(
            (e) => e.toString().split('.').last == map['status'],
          ),
        );
      }).toList();
      return records;
    } catch (e) {
      return [];
    }
  }

  // ==================== SEMESTER ====================

  Future<void> saveSemester(Semester semester) async {
    try {
      final db = _getDb();
      
      await db.insert(
        'semester',
        {
          'id': 1,
          'startDate': semester.startDate.toIso8601String(),
          'endDate': semester.endDate.toIso8601String(),
          'targetPercentage': semester.targetPercentage,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<Semester?> loadSemester() async {
    try {
      if (kIsWeb) {
        return null;
      }
      final db = _getDb();
      final List<Map<String, dynamic>> maps = await db.query(
        'semester',
        where: 'id = ?',
        whereArgs: [1],
      );

      if (maps.isEmpty) {
        return null;
      }

      final semester = Semester(
        startDate: DateTime.parse(maps[0]['startDate'] as String),
        endDate: DateTime.parse(maps[0]['endDate'] as String),
        targetPercentage: maps[0]['targetPercentage'] as double,
      );
      return semester;
    } catch (e) {
      return null;
    }
  }

  // Close database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _isInitialized = false;
    }
  }
  
  // ==================== CLEAR DATA ====================
  
  /// Clear all subjects and attendance data (used when starting a new semester)
  Future<void> clearAllData() async {
    try {
      final db = _getDb();
      final batch = db.batch();
      
      // Clear all subjects
      batch.delete('subjects');
      
      // Clear all attendance records
      batch.delete('attendance');
      
      await batch.commit(noResult: true);
    } catch (e) {
      rethrow;
    }
  }

  // ==================== APP UPDATES ====================

  Future<void> updateLastCheckDate(DateTime dateTime) async {
    try {
      final db = _getDb();
      await db.insert(
        'app_updates',
        {
          'id': 1,
          'lastCheckDate': dateTime.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<DateTime?> getLastCheckDate() async {
    try {
      final db = _getDb();
      final List<Map<String, dynamic>> maps = await db.query(
        'app_updates',
        where: 'id = ?',
        whereArgs: [1],
      );

      if (maps.isEmpty || maps[0]['lastCheckDate'] == null) {
        return null;
      }

      return DateTime.parse(maps[0]['lastCheckDate'] as String);
    } catch (e) {
      return null;
    }
  }

  Future<void> setDeferredUntil(DateTime dateTime) async {
    try {
      final db = _getDb();
      await db.insert(
        'app_updates',
        {
          'id': 1,
          'deferredUntil': dateTime.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<DateTime?> getDeferredUntil() async {
    try {
      final db = _getDb();
      final List<Map<String, dynamic>> maps = await db.query(
        'app_updates',
        where: 'id = ?',
        whereArgs: [1],
      );

      if (maps.isEmpty || maps[0]['deferredUntil'] == null) {
        return null;
      }

      return DateTime.parse(maps[0]['deferredUntil'] as String);
    } catch (e) {
      return null;
    }
  }

  Future<void> clearDeferral() async {
    try {
      final db = _getDb();
      final currentRecord = await db.query(
        'app_updates',
        where: 'id = ?',
        whereArgs: [1],
      );

      if (currentRecord.isNotEmpty) {
        await db.update(
          'app_updates',
          {'deferredUntil': null},
          where: 'id = ?',
          whereArgs: [1],
        );
      }
    } catch (e) {
      rethrow;
    }
  }
}
