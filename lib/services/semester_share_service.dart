import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../features/attendance/attendance_provider.dart';
import '../features/location/location_model.dart';
import '../features/semester/semester_model.dart';
import '../features/semester/semester_provider.dart';
import '../features/semester/semester_share_preview_dialog.dart';
import '../features/settings/swipe_action_provider.dart';
import '../features/settings/time_format_provider.dart';
import '../features/subject/import_timetable_screen.dart';
import '../features/subject/subject_model.dart';
import '../features/subject/subject_provider.dart';
import '../utils/error_utils.dart';
import '../utils/snackbar_utils.dart';
import 'backup_service.dart';
import 'database_service.dart';

enum ImportFileType {
  fullBackup,
  semesterShare,
  timetableJson,
  unknown,
}

class SemesterShareService {
  static final SemesterShareService _instance = SemesterShareService._internal();
  factory SemesterShareService() => _instance;
  SemesterShareService._internal();

  static const MethodChannel _fileChannel = MethodChannel('com.attendmate.app/file_import');

  /// Export complete semester template excluding user attendance history
  Future<Map<String, dynamic>> exportSemesterShareData() async {
    final dbService = DatabaseService();
    await dbService.init();

    final semester = await dbService.loadSemester();
    final subjects = await dbService.loadSubjects();
    final locations = await dbService.loadLocations();

    final sanitizedSubjects = subjects.map((s) {
      final jsonMap = s.toJson();
      // Ensure past attendance records are completely stripped
      jsonMap['attendanceRecords'] = [];
      return jsonMap;
    }).toList();

    return {
      'app': 'AttendMate',
      'type': 'semester_share',
      'schema_version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'semester': semester?.toJson(),
      'subjects': sanitizedSubjects,
      'locations': locations.map((l) => l.toMap()).toList(),
    };
  }

  /// Trigger native share sheet or copy JSON data to share with classmate
  Future<void> shareSemesterWithFriend(BuildContext context) async {
    try {
      final data = await exportSemesterShareData();
      final subjects = data['subjects'] as List? ?? [];
      if (subjects.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showReplacingSnackBar(
            const SnackBar(
              content: Text('No subjects to share. Please add subjects first.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final timestamp = DateFormat('yyyyMMdd').format(DateTime.now());
      final filename = 'attendmate_semester_share_$timestamp.json';
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);

      bool sharedNatively = false;
      try {
        sharedNatively = await _fileChannel.invokeMethod<bool>('shareFile', {
          'fileName': filename,
          'content': jsonString,
        }) ?? false;
      } catch (_) {}

      if (!sharedNatively) {
        // Fallback: Copy raw JSON to clipboard
        await Clipboard.setData(ClipboardData(text: jsonString));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showReplacingSnackBar(
            const SnackBar(
              content: Text('Semester share data copied to clipboard! Send it to your friend.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to share semester')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Auto-detect the type of JSON file content
  ImportFileType detectFileType(Map<String, dynamic> jsonMap) {
    // Check for explicit semester share type first
    final type = jsonMap['type'] as String?;
    if (type == 'semester_share') {
      return ImportFileType.semesterShare;
    }

    // Check for full backup (contains database object with subjects/attendance or top-level preferences)
    if (jsonMap['app'] == 'AttendMate') {
      final db = jsonMap['database'];
      if (db is Map<String, dynamic>) {
        if (db.containsKey('subjects') || db.containsKey('attendance') || db.containsKey('semester')) {
          return ImportFileType.fullBackup;
        }
      }
      if (jsonMap.containsKey('preferences') || jsonMap.containsKey('schema_version')) {
        return ImportFileType.fullBackup;
      }
      if (jsonMap.containsKey('semester') && jsonMap.containsKey('subjects')) {
        return ImportFileType.semesterShare;
      }
    }

    // Fallback detection without explicit 'app': 'AttendMate'
    if (jsonMap.containsKey('database') && jsonMap['database'] is Map<String, dynamic>) {
      final db = jsonMap['database'] as Map<String, dynamic>;
      if (db.containsKey('subjects') || db.containsKey('attendance') || db.containsKey('semester')) {
        return ImportFileType.fullBackup;
      }
    }

    if (jsonMap.containsKey('semester') && jsonMap.containsKey('subjects')) {
      return ImportFileType.semesterShare;
    }

    if (jsonMap.containsKey('subjects') && jsonMap['subjects'] is List) {
      return ImportFileType.timetableJson;
    }

    return ImportFileType.unknown;
  }

  static bool _isDialogShowing = false;

  /// Auto-detect content and process the opened file appropriately
  Future<void> processOpenedJsonContent(String content, BuildContext context) async {
    if (_isDialogShowing) return;
    _isDialogShowing = true;
    try {
      dynamic decoded;
      try {
        decoded = jsonDecode(content);
      } catch (_) {
        if (content.contains(',') || content.contains('{') || content.contains('\n')) {
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ImportTimetableScreen(initialText: content),
              ),
            );
          }
          return;
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showReplacingSnackBar(
            const SnackBar(
              content: Text('Unable to parse file. Please ensure it is valid JSON or CSV data.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (decoded is! Map<String, dynamic>) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showReplacingSnackBar(
            const SnackBar(
              content: Text('Unrecognized file structure.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final fileType = detectFileType(decoded);

      switch (fileType) {
        case ImportFileType.fullBackup:
          if (context.mounted) {
            await _promptFullBackupRestore(decoded, context);
          }
          break;
        case ImportFileType.semesterShare:
          if (context.mounted) {
            await showDialog(
              context: context,
              builder: (ctx) => SemesterSharePreviewDialog(shareData: decoded),
            );
          }
          break;
        case ImportFileType.timetableJson:
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ImportTimetableScreen(initialText: content),
              ),
            );
          }
          break;
        case ImportFileType.unknown:
          if (context.mounted) {
            ScaffoldMessenger.of(context).showReplacingSnackBar(
              const SnackBar(
                content: Text('The selected file is not a valid AttendMate backup or semester file.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          break;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Error processing file')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isDialogShowing = false;
    }
  }

  /// Prompt full backup restore when opening a full backup package
  Future<void> _promptFullBackupRestore(Map<String, dynamic> backupData, BuildContext context) async {
    final dbMap = backupData['database'] as Map<String, dynamic>? ?? {};
    final subjects = dbMap['subjects'] as List? ?? [];
    final attendance = dbMap['attendance'] as List? ?? [];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.backup_rounded, color: Theme.of(dialogCtx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Restore Full Backup?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This file is a full AttendMate app backup. Restoring will replace your current app data and settings with:',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(dialogCtx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${subjects.length} Subjects • ${attendance.length} Attendance Records',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Restore Backup'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await BackupService().restoreBackupFromData(backupData, context: context);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showReplacingSnackBar(
            const SnackBar(
              content: Text('App data and settings restored successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showReplacingSnackBar(
            SnackBar(
              content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to restore backup')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// Import shared semester package into local database and app state
  Future<bool> importSharedSemesterPackage(
    Map<String, dynamic> package,
    BuildContext context, {
    required bool mergeIntoCurrent,
  }) async {
    try {
      final semesterProv = Provider.of<SemesterProvider>(context, listen: false);
      final subjectProv = Provider.of<SubjectProvider>(context, listen: false);
      final attendanceProv = Provider.of<AttendanceProvider>(context, listen: false);
      final timeFormatProv = Provider.of<TimeFormatProvider>(context, listen: false);
      final swipeActionProv = Provider.of<SwipeActionProvider>(context, listen: false);

      final dbService = DatabaseService();
      await dbService.init();
      if (!context.mounted) return false;

      // Extract semester
      final semesterMap = package['semester'] as Map<String, dynamic>?;
      Semester? importedSemester;
      if (semesterMap != null) {
        importedSemester = Semester.fromJson(semesterMap);
      }

      // Extract subjects
      final subjectsRaw = package['subjects'] as List? ?? [];
      final List<Subject> importedSubjects = [];
      for (final item in subjectsRaw) {
        if (item is Map<String, dynamic>) {
          final s = Subject.fromJson(item);
          // Force clean attendance history
          importedSubjects.add(s.copyWith(attendanceRecords: const []));
        }
      }

      // Extract locations
      final locationsRaw = package['locations'] as List? ?? [];
      final List<LocationConfig> importedLocations = [];
      for (final item in locationsRaw) {
        if (item is Map<String, dynamic>) {
          importedLocations.add(LocationConfig.fromMap(item));
        }
      }

      if (!mergeIntoCurrent) {
        // Fresh Setup: Completely overwrite existing database (subjects, attendance, locations, semester, etc.)
        await dbService.clearSemesterAndAllData();

        if (importedSemester != null) {
          await semesterProv.updateSemester(importedSemester);
        }
      } else {
        // Merge mode: If current semester is null, set imported semester
        if (semesterProv.semester == null && importedSemester != null) {
          await semesterProv.updateSemester(importedSemester);
        }
      }

      // Save location configurations
      for (final loc in importedLocations) {
        await dbService.saveLocation(loc);
      }

      // Save subjects
      if (!mergeIntoCurrent) {
        await dbService.saveSubjects(importedSubjects);
      } else {
        // Merge into existing subjects
        final currentSubjects = List<Subject>.from(subjectProv.subjects);
        for (final newSub in importedSubjects) {
          final existingIdx = currentSubjects.indexWhere(
            (s) => s.name.trim().toLowerCase() == newSub.name.trim().toLowerCase() ||
                (s.acronym != null && s.acronym!.trim().toLowerCase() == (newSub.acronym ?? '').trim().toLowerCase()),
          );

          if (existingIdx != -1) {
            currentSubjects[existingIdx] = currentSubjects[existingIdx].copyWith(
              schedule: newSub.schedule,
              room: () => newSub.room,
              block: () => newSub.block,
            );
          } else {
            currentSubjects.add(newSub);
          }
        }
        await dbService.saveSubjects(currentSubjects);
      }

      // Reload providers
      await semesterProv.loadSemester();
      await subjectProv.reloadSubjects();
      await attendanceProv.reloadAttendance();
      if (context.mounted) {
        await timeFormatProv.init(context);
      }
      await swipeActionProv.init();

      return true;
    } catch (e) {
      debugPrint('SemesterShareService import error: $e');
      rethrow;
    }
  }
}
