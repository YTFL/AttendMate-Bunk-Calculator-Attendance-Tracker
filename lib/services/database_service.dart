import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'backup_service.dart';
import '../features/attendance/attendance_model.dart';
import '../features/semester/semester_model.dart';
import '../features/subject/subject_model.dart';
import '../features/location/location_model.dart';
import '../features/planner/planned_leave_model.dart';

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
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'attendance_tracker.db');

      _database = await openDatabase(
        path,
        version: 8,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );

      // Create app_logs table dynamically to allow event logging for diagnostic/debugging purposes.
      await _database!.execute('''
        CREATE TABLE IF NOT EXISTS app_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT NOT NULL,
          tag TEXT NOT NULL,
          message TEXT NOT NULL,
          level TEXT NOT NULL
        )
      ''');
      
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
          attendanceRecords TEXT NOT NULL,
          locationId TEXT,
          room TEXT,
          block TEXT
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

      // System Calendar Events mapping table
      await db.execute('''
        CREATE TABLE system_calendar_events (
          eventId TEXT PRIMARY KEY,
          subjectId TEXT NOT NULL,
          slotKey TEXT NOT NULL,
          date TEXT NOT NULL
        )
      ''');

      // Create lookup index to speed up calendar sync operations
      await db.execute('''
        CREATE INDEX idx_system_calendar_events_lookup 
        ON system_calendar_events (subjectId, slotKey, date)
      ''');

      // Locations table
      await db.execute('''
        CREATE TABLE locations (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          block TEXT,
          latitude REAL,
          longitude REAL
        )
      ''');

      // Planned leaves table
      await db.execute('''
        CREATE TABLE planned_leaves (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          startDate TEXT NOT NULL,
          endDate TEXT NOT NULL,
          affectedSubjectIds TEXT NOT NULL
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
      if (oldVersion < 5) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS system_calendar_events (
            eventId TEXT PRIMARY KEY,
            subjectId TEXT NOT NULL,
            slotKey TEXT NOT NULL,
            date TEXT NOT NULL
          )
        ''');
      }
      if (oldVersion < 6) {
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_system_calendar_events_lookup 
          ON system_calendar_events (subjectId, slotKey, date)
        ''');
      }
      if (oldVersion < 7) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS locations (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            block TEXT,
            latitude REAL,
            longitude REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS planned_leaves (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            startDate TEXT NOT NULL,
            endDate TEXT NOT NULL,
            affectedSubjectIds TEXT NOT NULL
          )
        ''');
      }
      if (oldVersion < 8) {
        // Add subject-level location columns
        final cols = await db.rawQuery('PRAGMA table_info(subjects)');
        final existing = cols.map((c) => c['name'] as String).toSet();
        if (!existing.contains('locationId')) {
          await db.execute('ALTER TABLE subjects ADD COLUMN locationId TEXT');
        }
        if (!existing.contains('room')) {
          await db.execute('ALTER TABLE subjects ADD COLUMN room TEXT');
        }
        if (!existing.contains('block')) {
          await db.execute('ALTER TABLE subjects ADD COLUMN block TEXT');
        }
      }
    } catch (e) {
      debugPrint('DatabaseService onUpgrade error: $e');
      rethrow;
    }
  }

  Database _getDb() {
    if (_database == null || !_isInitialized) {
      throw Exception('DatabaseService not initialized. Call init() first.');
    }
    return _database!;
  }

  /// Expose raw database instance for BackupService transactions
  Future<Database> getRawDatabase() async {
    if (_database == null || !_isInitialized) {
      await init();
    }
    return _getDb();
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
          'locationId': subject.locationId,
          'room': subject.room,
          'block': subject.block,
        });
      }

      await batch.commit(noResult: true);
      await BackupService().notifyDataChanged();
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
          locationId: map['locationId'] as String?,
          room: map['room'] as String?,
          block: map['block'] as String?,
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
      await BackupService().notifyDataChanged();
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
      await BackupService().notifyDataChanged();
    } catch (e) {
      rethrow;
    }
  }

  Future<Semester?> loadSemester() async {
    try {
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
      await BackupService().notifyDataChanged();
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

  // ==================== SYSTEM CALENDAR EVENTS ====================

  Future<void> saveSystemCalendarEvent({
    required String eventId,
    required String subjectId,
    required String slotKey,
    required DateTime date,
  }) async {
    try {
      final db = _getDb();
      await db.insert(
        'system_calendar_events',
        {
          'eventId': eventId,
          'subjectId': subjectId,
          'slotKey': slotKey,
          'date': date.toIso8601String().split('T')[0],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('DatabaseService saveSystemCalendarEvent error: $e');
      rethrow;
    }
  }

  Future<String?> getSystemCalendarEvent({
    required String subjectId,
    required String slotKey,
    required DateTime date,
  }) async {
    try {
      final db = _getDb();
      final maps = await db.query(
        'system_calendar_events',
        columns: ['eventId'],
        where: 'subjectId = ? AND slotKey = ? AND date = ?',
        whereArgs: [subjectId, slotKey, date.toIso8601String().split('T')[0]],
      );
      if (maps.isEmpty) return null;
      return maps.first['eventId'] as String?;
    } catch (e) {
      debugPrint('DatabaseService getSystemCalendarEvent error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getSystemCalendarEventsForSubject(String subjectId) async {
    try {
      final db = _getDb();
      return await db.query(
        'system_calendar_events',
        where: 'subjectId = ?',
        whereArgs: [subjectId],
      );
    } catch (e) {
      debugPrint('DatabaseService getSystemCalendarEventsForSubject error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAllSystemCalendarEvents() async {
    try {
      final db = _getDb();
      return await db.query('system_calendar_events');
    } catch (e) {
      debugPrint('DatabaseService getAllSystemCalendarEvents error: $e');
      return [];
    }
  }

  Future<void> deleteSystemCalendarEvent(String eventId) async {
    try {
      final db = _getDb();
      await db.delete(
        'system_calendar_events',
        where: 'eventId = ?',
        whereArgs: [eventId],
      );
    } catch (e) {
      debugPrint('DatabaseService deleteSystemCalendarEvent error: $e');
      rethrow;
    }
  }

  Future<void> deleteSystemCalendarEventsForSubject(String subjectId) async {
    try {
      final db = _getDb();
      await db.delete(
        'system_calendar_events',
        where: 'subjectId = ?',
        whereArgs: [subjectId],
      );
    } catch (e) {
      debugPrint('DatabaseService deleteSystemCalendarEventsForSubject error: $e');
      rethrow;
    }
  }

  Future<void> clearSystemCalendarEvents() async {
    try {
      final db = _getDb();
      await db.delete('system_calendar_events');
    } catch (e) {
      debugPrint('DatabaseService clearSystemCalendarEvents error: $e');
      rethrow;
    }
  }

  Future<void> clearSemesterAndAllData() async {
    try {
      final db = _getDb();
      final batch = db.batch();
      batch.delete('semester');
      batch.delete('subjects');
      batch.delete('attendance');
      batch.delete('system_calendar_events');
      await batch.commit(noResult: true);
      await BackupService().notifyDataChanged();
    } catch (e) {
      debugPrint('DatabaseService clearSemesterAndAllData error: $e');
      rethrow;
    }
  }

  // ==================== INCREMENTAL ATTENDANCE WRITES ====================

  /// Save a single attendance record, replacing it if it already exists
  Future<void> saveSingleAttendance(Attendance record) async {
    try {
      final db = _getDb();
      await db.insert(
        'attendance',
        {
          'subjectId': record.subjectId,
          'date': record.date.toIso8601String(),
          'slotKey': record.slotKey ?? '',
          'status': record.status.toString().split('.').last,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await BackupService().notifyDataChanged();
    } catch (e) {
      debugPrint('DatabaseService saveSingleAttendance error: $e');
      rethrow;
    }
  }

  /// Delete a single attendance record matching subjectId, date, and slotKey
  Future<void> deleteSingleAttendance({
    required String subjectId,
    required DateTime date,
    String? slotKey,
  }) async {
    try {
      final db = _getDb();
      await db.delete(
        'attendance',
        where: 'subjectId = ? AND date = ? AND slotKey = ?',
        whereArgs: [subjectId, date.toIso8601String(), slotKey ?? ''],
      );
      await BackupService().notifyDataChanged();
    } catch (e) {
      debugPrint('DatabaseService deleteSingleAttendance error: $e');
      rethrow;
    }
  }

  /// Delete all attendance records associated with a subject
  Future<void> deleteAttendanceForSubject(String subjectId) async {
    try {
      final db = _getDb();
      await db.delete(
        'attendance',
        where: 'subjectId = ?',
        whereArgs: [subjectId],
      );
      await BackupService().notifyDataChanged();
    } catch (e) {
      debugPrint('DatabaseService deleteAttendanceForSubject error: $e');
      rethrow;
    }
  }

  /// Delete all attendance records on a specific date
  Future<void> deleteAttendanceForDate(DateTime date) async {
    try {
      final db = _getDb();
      await db.delete(
        'attendance',
        where: 'date = ?',
        whereArgs: [date.toIso8601String()],
      );
      await BackupService().notifyDataChanged();
    } catch (e) {
      debugPrint('DatabaseService deleteAttendanceForDate error: $e');
      rethrow;
    }
  }

  /// Insert or replace multiple attendance records using a transaction batch
  Future<void> saveMultipleAttendanceIncremental(List<Attendance> records) async {
    try {
      final db = _getDb();
      final batch = db.batch();
      for (final record in records) {
        batch.insert(
          'attendance',
          {
            'subjectId': record.subjectId,
            'date': record.date.toIso8601String(),
            'slotKey': record.slotKey ?? '',
            'status': record.status.toString().split('.').last,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      await BackupService().notifyDataChanged();
    } catch (e) {
      debugPrint('DatabaseService saveMultipleAttendanceIncremental error: $e');
      rethrow;
    }
  }

  // ==================== LOCATIONS ====================

  Future<void> saveLocation(LocationConfig location) async {
    try {
      final db = _getDb();
      await db.insert(
        'locations',
        location.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await BackupService().notifyDataChanged();
    } catch (e) {
      debugPrint('DatabaseService saveLocation error: $e');
      rethrow;
    }
  }

  Future<List<LocationConfig>> loadLocations() async {
    try {
      final db = _getDb();
      final List<Map<String, dynamic>> maps = await db.query('locations');
      return maps.map((map) => LocationConfig.fromMap(map)).toList();
    } catch (e) {
      debugPrint('DatabaseService loadLocations error: $e');
      return [];
    }
  }

  Future<void> deleteLocation(String id) async {
    try {
      final db = _getDb();
      await db.delete(
        'locations',
        where: 'id = ?',
        whereArgs: [id],
      );
      await BackupService().notifyDataChanged();
    } catch (e) {
      debugPrint('DatabaseService deleteLocation error: $e');
      rethrow;
    }
  }

  // ==================== PLANNED LEAVES ====================

  Future<void> savePlannedLeave(PlannedLeave leave) async {
    try {
      final db = _getDb();
      await db.insert(
        'planned_leaves',
        leave.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await BackupService().notifyDataChanged();
    } catch (e) {
      debugPrint('DatabaseService savePlannedLeave error: $e');
      rethrow;
    }
  }

  Future<List<PlannedLeave>> loadPlannedLeaves() async {
    try {
      final db = _getDb();
      final List<Map<String, dynamic>> maps = await db.query('planned_leaves');
      return maps.map((map) => PlannedLeave.fromMap(map)).toList();
    } catch (e) {
      debugPrint('DatabaseService loadPlannedLeaves error: $e');
      return [];
    }
  }

  Future<void> deletePlannedLeave(String id) async {
    try {
      final db = _getDb();
      await db.delete(
        'planned_leaves',
        where: 'id = ?',
        whereArgs: [id],
      );
      await BackupService().notifyDataChanged();
    } catch (e) {
      debugPrint('DatabaseService deletePlannedLeave error: $e');
      rethrow;
    }
  }

  // ==================== APP LOGS (DIAGNOSTICS) ====================

  Future<void> logAppEvent({
    required String tag,
    required String message,
    String level = 'INFO',
  }) async {
    try {
      final db = _getDb();
      await db.insert('app_logs', {
        'timestamp': DateTime.now().toIso8601String(),
        'tag': tag,
        'message': message,
        'level': level,
      });
      debugPrint('[$level][$tag] $message');
    } catch (e) {
      debugPrint('Error logging app event: $e');
    }
  }

  Future<List<Map<String, dynamic>>> loadAppLogs() async {
    try {
      final db = _getDb();
      return await db.query('app_logs', orderBy: 'timestamp DESC', limit: 200);
    } catch (e) {
      debugPrint('DatabaseService loadAppLogs error: $e');
      return [];
    }
  }

  Future<void> clearAppLogs() async {
    try {
      final db = _getDb();
      await db.delete('app_logs');
    } catch (e) {
      debugPrint('DatabaseService clearAppLogs error: $e');
    }
  }
}
