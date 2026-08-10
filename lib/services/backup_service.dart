import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../features/attendance/attendance_provider.dart';
import '../features/semester/semester_provider.dart';
import '../features/settings/swipe_action_provider.dart';
import '../features/settings/time_format_provider.dart';
import '../features/subject/subject_provider.dart';
import 'database_service.dart';
import 'notification_service.dart';

class BackupFileInfo {
  final File file;
  final String fileName;
  final DateTime createdAt;
  final int fileSizeBytes;
  final int subjectCount;
  final int attendanceCount;
  final String? semesterRange;
  final Map<String, dynamic>? rawData;

  BackupFileInfo({
    required this.file,
    required this.fileName,
    required this.createdAt,
    required this.fileSizeBytes,
    required this.subjectCount,
    required this.attendanceCount,
    this.semesterRange,
    this.rawData,
  });
}

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  static const String _prefBackupDirPathKey = 'backup_directory_path';
  static const String _prefHasUnbackedChangesKey = 'has_unbacked_data_changes';
  static const String _prefBackupEnabledKey = 'semester_backup_enabled';
  static const int maxRollingBackups = 3;
  static const MethodChannel _fileChannel = MethodChannel('com.attendmate.app/file_import');

  /// Check if automatic backups are enabled by user
  Future<bool> isBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefBackupEnabledKey) ?? true;
  }

  /// Enable or disable automatic backups
  Future<void> setBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBackupEnabledKey, enabled);
  }

  /// Call whenever app state / database data changes
  Future<void> notifyDataChanged() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefHasUnbackedChangesKey, true);
  }

  /// Check if there are unsaved data changes requiring a backup
  Future<bool> hasUnbackedDataChanges() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefHasUnbackedChangesKey) ?? false;
  }

  /// Clear the dirty flag after a successful backup
  Future<void> clearUnbackedDataChanges() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefHasUnbackedChangesKey, false);
  }

  /// Convert SAF tree URI (content://...) into a standard Android filesystem path if possible
  String _convertSafUriToPath(String uriStr) {
    if (!uriStr.startsWith('content://')) return uriStr;
    try {
      final decoded = Uri.decodeFull(uriStr);
      final treeIndex = decoded.indexOf('/tree/');
      if (treeIndex != -1) {
        final treePart = decoded.substring(treeIndex + 6);
        final split = treePart.split(':');
        if (split.length >= 2) {
          final typePart = split[0];
          final type = typePart.contains('/') ? typePart.split('/').last : typePart;
          final relativePath = split.sublist(1).join(':');
          if (type.toLowerCase() == 'primary') {
            return relativePath.isEmpty ? '/storage/emulated/0' : '/storage/emulated/0/$relativePath';
          } else {
            return relativePath.isEmpty ? '/storage/$type' : '/storage/$type/$relativePath';
          }
        }
      }
    } catch (_) {}
    return uriStr;
  }

  /// Get the current backup directory path. Returns null if not specified by user.
  Future<String?> getBackupDirectoryPath() async {
    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString(_prefBackupDirPathKey);
    if (customPath != null && customPath.trim().isNotEmpty) {
      final rawPath = customPath.trim();
      final converted = _convertSafUriToPath(rawPath);
      final customDir = Directory(converted);
      if (await customDir.exists()) {
        return customDir.path;
      }
      return converted;
    }
    return null;
  }

  /// Check if user has specified a backup folder
  Future<bool> hasUserSetBackupDirectory() async {
    final path = await getBackupDirectoryPath();
    return path != null && path.trim().isNotEmpty;
  }

  /// Set a custom backup directory path
  Future<void> setBackupDirectoryPath(String newPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBackupDirPathKey, newPath.trim());
  }

  /// Export complete 1:1 database and preferences state into a JSON map
  Future<Map<String, dynamic>> exportBackupData() async {
    final dbService = DatabaseService();
    await dbService.init();

    // Raw query database tables to preserve exact column structure
    final db = await dbService.getRawDatabase();

    final subjects = await db.query('subjects');
    final attendance = await db.query('attendance');
    final semester = await db.query('semester');
    final locations = await db.query('locations');
    final plannedLeaves = await db.query('planned_leaves');
    final systemCalendarEvents = await db.query('system_calendar_events');
    final appUpdates = await db.query('app_updates');

    // Collect SharedPreferences settings
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> preferencesMap = {};
    for (final key in prefs.getKeys()) {
      // Exclude backup directory path itself so user's folder preference remains local
      if (key == _prefBackupDirPathKey) continue;
      preferencesMap[key] = prefs.get(key);
    }

    final now = DateTime.now().toUtc();
    return {
      'app': 'AttendMate',
      'schema_version': 1,
      'app_version': '2.0.0',
      'created_at': now.toIso8601String(),
      'database': {
        'subjects': subjects,
        'attendance': attendance,
        'semester': semester,
        'locations': locations,
        'planned_leaves': plannedLeaves,
        'system_calendar_events': systemCalendarEvents,
        'app_updates': appUpdates,
      },
      'preferences': preferencesMap,
    };
  }

  Future<Directory> _getFallbackBackupDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${docsDir.path}${Platform.pathSeparator}backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// Create a backup file in the designated folder and enforce the 3 rolling backups limit
  Future<File?> createBackup({
    bool showNotification = false,
    String? triggerReason,
    bool force = false,
  }) async {
    try {
      if (!force && !await isBackupEnabled()) {
        debugPrint('BackupService: Auto-backup skipped because backups are turned off by user.');
        return null;
      }

      final dirPath = await getBackupDirectoryPath();
      if (dirPath == null || dirPath.trim().isEmpty) {
        debugPrint('BackupService: Auto-backup skipped because no backup directory is specified by user.');
        return null;
      }

      if (!force) {
        final hasChanges = await hasUnbackedDataChanges();
        if (!hasChanges) {
          debugPrint('BackupService: Auto-backup skipped because no data changes occurred since last backup.');
          return null;
        }
      }

      final backupData = await exportBackupData();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'attendmate_backup_$timestamp.json';
      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);

      bool success = false;
      if (dirPath.startsWith('content://')) {
        try {
          success = await _fileChannel.invokeMethod('writeBackupFile', {
            'dirUri': dirPath,
            'fileName': filename,
            'content': jsonString,
          }) ?? false;
        } catch (e) {
          debugPrint('BackupService: Platform channel writeBackupFile failed ($e). Writing to fallback app storage...');
          final fallbackDir = await _getFallbackBackupDirectory();
          final file = File('${fallbackDir.path}${Platform.pathSeparator}$filename');
          await file.writeAsString(jsonString);
          success = true;
        }
      } else {
        try {
          final dir = Directory(dirPath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          final sep = Platform.pathSeparator;
          final file = File('${dir.path}$sep$filename');
          await file.writeAsString(jsonString);
          success = true;
        } on FileSystemException catch (fse) {
          debugPrint('BackupService: Direct path $dirPath restricted by OS ($fse). Writing to fallback app storage...');
          final fallbackDir = await _getFallbackBackupDirectory();
          final file = File('${fallbackDir.path}${Platform.pathSeparator}$filename');
          await file.writeAsString(jsonString);
          success = true;
        }
      }

      if (!success) {
        debugPrint('BackupService: Native writeBackupFile returned false');
        return null;
      }

      // Clear the dirty flag since backup was successfully created
      await clearUnbackedDataChanges();

      // Enforce the 3 rolling backups limit immediately
      await enforceRollingLimit();

      await DatabaseService().logAppEvent(
        tag: 'BackupService',
        message: 'Backup successfully created: $filename ${triggerReason != null ? "($triggerReason)" : ""}',
      );

      if (showNotification) {
        try {
          await NotificationService().showBackupNotification(
            title: 'Semester Backup Created',
            body: 'Your attendance data & settings have been backed up.',
          );
        } catch (e) {
          debugPrint('BackupService: Suppressed notification error in background: $e');
        }
      }

      return File(filename);
    } catch (e) {
      debugPrint('BackupService createBackup error: $e');
      await DatabaseService().logAppEvent(
        tag: 'BackupService',
        message: 'Failed to create backup: $e',
        level: 'ERROR',
      );
      return null;
    }
  }

  /// Helper to fetch raw list of backup file maps from either SAF tree URI or direct directory path
  Future<List<Map<String, dynamic>>> _fetchBackupFilesRaw(String dirPath) async {
    final List<Map<String, dynamic>> items = [];

    if (dirPath.startsWith('content://')) {
      try {
        final List<dynamic>? rawList = await _fileChannel.invokeMethod('getBackupFiles', {
          'dirUri': dirPath,
        });
        if (rawList != null) {
          items.addAll(rawList.map((e) => Map<String, dynamic>.from(e as Map)));
        }
      } catch (_) {}
    } else {
      try {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final List<FileSystemEntity> entities = dir.listSync();
          for (final entity in entities) {
            if (entity is File) {
              final fileName = entity.path.split(RegExp(r'[/\\]')).last;
              if (fileName.startsWith('attendmate_backup_') && fileName.endsWith('.json')) {
                try {
                  final stat = await entity.stat();
                  final content = await entity.readAsString();
                  items.add({
                    'fileName': fileName,
                    'fileSizeBytes': stat.size,
                    'lastModified': stat.modified.millisecondsSinceEpoch,
                    'content': content,
                  });
                } catch (_) {}
              }
            }
          }
        }
      } catch (_) {}
    }

    // Always combine with items from fallback app storage if present
    try {
      final fallbackDir = await _getFallbackBackupDirectory();
      if (fallbackDir.path != dirPath && await fallbackDir.exists()) {
        final List<FileSystemEntity> entities = fallbackDir.listSync();
        for (final entity in entities) {
          if (entity is File) {
            final fileName = entity.path.split(RegExp(r'[/\\]')).last;
            if (fileName.startsWith('attendmate_backup_') && fileName.endsWith('.json')) {
              if (!items.any((element) => element['fileName'] == fileName)) {
                try {
                  final stat = await entity.stat();
                  final content = await entity.readAsString();
                  items.add({
                    'fileName': fileName,
                    'fileSizeBytes': stat.size,
                    'lastModified': stat.modified.millisecondsSinceEpoch,
                    'content': content,
                  });
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (_) {}

    return items;
  }

  /// Enforces that at any given time, at most [maxRollingBackups] (3) exist in the directory
  Future<void> enforceRollingLimit() async {
    try {
      final dirPath = await getBackupDirectoryPath();
      if (dirPath == null || dirPath.trim().isEmpty) return;

      final items = await _fetchBackupFilesRaw(dirPath);
      if (items.length <= maxRollingBackups) return;

      items.sort((a, b) {
        final aMod = (a['lastModified'] as num?)?.toInt() ?? 0;
        final bMod = (b['lastModified'] as num?)?.toInt() ?? 0;
        return bMod.compareTo(aMod);
      });

      final itemsToDelete = items.sublist(maxRollingBackups);
      for (final item in itemsToDelete) {
        final fileName = item['fileName'] as String;
        try {
          await deleteBackupFile(fileName);
          debugPrint('Pruned old rolling backup: $fileName');
        } catch (e) {
          debugPrint('Failed to delete old backup file: $e');
        }
      }
    } catch (e) {
      debugPrint('Error enforcing rolling backup limit: $e');
    }
  }

  /// Retrieve list of available backup files in the designated folder (up to 3)
  Future<List<BackupFileInfo>> getBackupFiles() async {
    try {
      final dirPath = await getBackupDirectoryPath();
      if (dirPath == null || dirPath.trim().isEmpty) return [];

      final items = await _fetchBackupFilesRaw(dirPath);
      if (items.isEmpty) return [];

      items.sort((a, b) {
        final aMod = (a['lastModified'] as num?)?.toInt() ?? 0;
        final bMod = (b['lastModified'] as num?)?.toInt() ?? 0;
        return bMod.compareTo(aMod);
      });

      final List<BackupFileInfo> list = [];
      for (final item in items.take(maxRollingBackups)) {
        try {
          final fileName = item['fileName'] as String;
          final content = item['content'] as String;
          final fileSizeBytes = (item['fileSizeBytes'] as num?)?.toInt() ?? 0;
          final lastModified = (item['lastModified'] as num?)?.toInt() ?? 0;

          final data = jsonDecode(content) as Map<String, dynamic>;

          final createdAtStr = data['created_at'] as String?;
          final createdAt = createdAtStr != null
              ? DateTime.tryParse(createdAtStr)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(lastModified)
              : DateTime.fromMillisecondsSinceEpoch(lastModified);

          final db = data['database'] as Map<String, dynamic>? ?? {};
          final subjects = db['subjects'] as List? ?? [];
          final attendance = db['attendance'] as List? ?? [];
          final semesterList = db['semester'] as List? ?? [];

          String? semesterRange;
          if (semesterList.isNotEmpty) {
            final semMap = semesterList.first as Map<String, dynamic>;
            final start = semMap['start_date'] as String? ?? semMap['startDate'] as String?;
            final end = semMap['end_date'] as String? ?? semMap['endDate'] as String?;
            if (start != null && end != null) {
              try {
                final d1 = DateFormat.yMMMd().format(DateTime.parse(start));
                final d2 = DateFormat.yMMMd().format(DateTime.parse(end));
                semesterRange = '$d1 - $d2';
              } catch (_) {}
            }
          }

          list.add(
            BackupFileInfo(
              file: File(fileName),
              fileName: fileName,
              createdAt: createdAt,
              fileSizeBytes: fileSizeBytes,
              subjectCount: subjects.length,
              attendanceCount: attendance.length,
              semesterRange: semesterRange,
              rawData: data,
            ),
          );
        } catch (e) {
          list.add(
            BackupFileInfo(
              file: File(item['fileName'] as String? ?? 'backup.json'),
              fileName: item['fileName'] as String? ?? 'backup.json',
              createdAt: DateTime.fromMillisecondsSinceEpoch((item['lastModified'] as num?)?.toInt() ?? 0),
              fileSizeBytes: (item['fileSizeBytes'] as num?)?.toInt() ?? 0,
              subjectCount: 0,
              attendanceCount: 0,
              semesterRange: 'Corrupted or legacy format',
            ),
          );
        }
      }

      return list;
    } catch (e) {
      debugPrint('Error getting backup files: $e');
      return [];
    }
  }

  /// Restore 1:1 exact application state from JSON backup data
  Future<bool> restoreBackupFromData(
    Map<String, dynamic> backupData, {
    BuildContext? context,
  }) async {
    try {
      if (backupData['app'] != 'AttendMate' || backupData['database'] == null) {
        throw Exception('Invalid AttendMate backup file format.');
      }

      final dbService = DatabaseService();
      await dbService.init();
      final db = await dbService.getRawDatabase();

      final dbMap = backupData['database'] as Map<String, dynamic>;
      final subjects = (dbMap['subjects'] as List? ?? []).cast<Map<String, dynamic>>();
      final attendance = (dbMap['attendance'] as List? ?? []).cast<Map<String, dynamic>>();
      final semester = (dbMap['semester'] as List? ?? []).cast<Map<String, dynamic>>();
      final locations = (dbMap['locations'] as List? ?? []).cast<Map<String, dynamic>>();
      final plannedLeaves = (dbMap['planned_leaves'] as List? ?? []).cast<Map<String, dynamic>>();
      final systemCalendarEvents = (dbMap['system_calendar_events'] as List? ?? []).cast<Map<String, dynamic>>();
      final appUpdates = (dbMap['app_updates'] as List? ?? []).cast<Map<String, dynamic>>();

      // Execute atomic transaction for database restoration
      await db.transaction((txn) async {
        await txn.delete('subjects');
        await txn.delete('attendance');
        await txn.delete('semester');
        await txn.delete('locations');
        await txn.delete('planned_leaves');
        await txn.delete('system_calendar_events');
        await txn.delete('app_updates');

        for (final row in subjects) {
          await txn.insert('subjects', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final row in attendance) {
          await txn.insert('attendance', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final row in semester) {
          await txn.insert('semester', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final row in locations) {
          await txn.insert('locations', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final row in plannedLeaves) {
          await txn.insert('planned_leaves', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final row in systemCalendarEvents) {
          await txn.insert('system_calendar_events', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        for (final row in appUpdates) {
          await txn.insert('app_updates', row, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

      // Restore SharedPreferences
      final prefMap = backupData['preferences'] as Map<String, dynamic>?;
      if (prefMap != null && prefMap.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        for (final entry in prefMap.entries) {
          if (entry.key == _prefBackupDirPathKey) continue;
          final value = entry.value;
          if (value is bool) {
            await prefs.setBool(entry.key, value);
          } else if (value is int) {
            await prefs.setInt(entry.key, value);
          } else if (value is double) {
            await prefs.setDouble(entry.key, value);
          } else if (value is String) {
            await prefs.setString(entry.key, value);
          } else if (value is List) {
            await prefs.setStringList(entry.key, value.cast<String>());
          }
        }
      }

      await DatabaseService().logAppEvent(
        tag: 'BackupService',
        message: 'Database & preferences restored successfully from backup.',
      );

      // Re-initialize app state providers if context is present
      if (context != null && context.mounted) {
        final attendanceProv = Provider.of<AttendanceProvider>(context, listen: false);
        final semesterProv = Provider.of<SemesterProvider>(context, listen: false);
        final subjectProv = Provider.of<SubjectProvider>(context, listen: false);
        final timeFormatProv = Provider.of<TimeFormatProvider>(context, listen: false);
        final swipeActionProv = Provider.of<SwipeActionProvider>(context, listen: false);

        await semesterProv.loadSemester();
        await attendanceProv.reloadAttendance();
        await subjectProv.reloadSubjects();
        if (context.mounted) {
          await timeFormatProv.init(context);
        }
        await swipeActionProv.init();
      }

      return true;
    } catch (e) {
      debugPrint('BackupService restore error: $e');
      await DatabaseService().logAppEvent(
        tag: 'BackupService',
        message: 'Failed to restore backup: $e',
        level: 'ERROR',
      );
      rethrow;
    }
  }

  /// Restore state from a backup File
  Future<bool> restoreBackupFromFile(File file, {BuildContext? context}) async {
    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    if (context != null && !context.mounted) return false;
    return restoreBackupFromData(data, context: context);
  }

  /// Delete a backup file
  Future<void> deleteBackupFile(String fileName) async {
    try {
      final dirPath = await getBackupDirectoryPath();
      if (dirPath == null) return;
      if (dirPath.startsWith('content://')) {
        await _fileChannel.invokeMethod('deleteBackupFile', {
          'dirUri': dirPath,
          'fileName': fileName,
        });
      } else {
        final sep = Platform.pathSeparator;
        final file = File('$dirPath$sep$fileName');
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('Error deleting backup file: $e');
    }
  }
}
