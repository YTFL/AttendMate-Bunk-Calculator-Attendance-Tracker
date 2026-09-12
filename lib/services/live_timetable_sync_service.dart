import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/attendance/attendance_provider.dart';
import '../features/location/location_model.dart';
import '../features/semester/semester_model.dart';
import '../features/semester/semester_provider.dart';
import '../features/settings/swipe_action_provider.dart';
import '../features/settings/time_format_provider.dart';
import '../features/subject/subject_model.dart';
import '../features/subject/subject_provider.dart';
import 'database_service.dart';
import 'google_auth_service.dart';
import 'google_drive_backup_service.dart';

class LiveTimetableSyncService extends ChangeNotifier {
  static final LiveTimetableSyncService _instance = LiveTimetableSyncService._internal();
  factory LiveTimetableSyncService() => _instance;
  LiveTimetableSyncService._internal();

  // SharedPreferences Keys
  static const String _keyIsHost = 'live_sync_is_host';
  static const String _keyHostedFileId = 'live_sync_hosted_file_id';
  static const String _keyHostedClassName = 'live_sync_hosted_class_name';
  static const String _keyHostedVersion = 'live_sync_hosted_version';
  static const String _keyHostedLastPushedAt = 'live_sync_hosted_last_pushed_at';

  static const String _keyIsSubscribed = 'live_sync_is_subscribed';
  static const String _keySubscribedFileId = 'live_sync_subscribed_file_id';
  static const String _keySubscribedClassName = 'live_sync_subscribed_class_name';
  static const String _keySubscribedCreatorName = 'live_sync_subscribed_creator_name';
  static const String _keySubscribedVersion = 'live_sync_subscribed_version';
  static const String _keySubscribedLastSyncedAt = 'live_sync_subscribed_last_synced_at';
  static const String _keyAutoCheckEnabled = 'live_sync_auto_check_enabled';

  // In-memory state
  bool _isInitialized = false;

  bool _isHost = false;
  String? _hostedFileId;
  String? _hostedClassName;
  int _hostedVersion = 1;
  DateTime? _hostedLastPushedAt;

  bool _isSubscribed = false;
  String? _subscribedFileId;
  String? _subscribedClassName;
  String? _subscribedCreatorName;
  int _subscribedVersion = 1;
  DateTime? _subscribedLastSyncedAt;
  bool _autoCheckEnabled = true;

  DateTime? _lastResumeCheckTime;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isHost => _isHost;
  String? get hostedFileId => _hostedFileId;
  String? get hostedClassName => _hostedClassName;
  int get hostedVersion => _hostedVersion;
  DateTime? get hostedLastPushedAt => _hostedLastPushedAt;

  bool get isSubscribed => _isSubscribed;
  String? get subscribedFileId => _subscribedFileId;
  String? get subscribedClassName => _subscribedClassName;
  String? get subscribedCreatorName => _subscribedCreatorName;
  int get subscribedVersion => _subscribedVersion;
  DateTime? get subscribedLastSyncedAt => _subscribedLastSyncedAt;
  bool get autoCheckEnabled => _autoCheckEnabled;

  /// Load persisted state from SharedPreferences
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      _isHost = prefs.getBool(_keyIsHost) ?? false;
      _hostedFileId = prefs.getString(_keyHostedFileId);
      _hostedClassName = prefs.getString(_keyHostedClassName);
      _hostedVersion = prefs.getInt(_keyHostedVersion) ?? 1;
      final hostTimeStr = prefs.getString(_keyHostedLastPushedAt);
      if (hostTimeStr != null && hostTimeStr.isNotEmpty) {
        _hostedLastPushedAt = DateTime.tryParse(hostTimeStr)?.toLocal();
      }

      _isSubscribed = prefs.getBool(_keyIsSubscribed) ?? false;
      _subscribedFileId = prefs.getString(_keySubscribedFileId);
      _subscribedClassName = prefs.getString(_keySubscribedClassName);
      _subscribedCreatorName = prefs.getString(_keySubscribedCreatorName);
      _subscribedVersion = prefs.getInt(_keySubscribedVersion) ?? 1;
      final subTimeStr = prefs.getString(_keySubscribedLastSyncedAt);
      if (subTimeStr != null && subTimeStr.isNotEmpty) {
        _subscribedLastSyncedAt = DateTime.tryParse(subTimeStr)?.toLocal();
      }
      _autoCheckEnabled = prefs.getBool(_keyAutoCheckEnabled) ?? true;

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('LiveTimetableSyncService init error: $e');
    }
  }

  // ==========================================
  // URL & CODE EXTRACTION UTILS
  // ==========================================

  /// Extracts Google Drive File ID from various link formats, QR code formats, or raw IDs
  static String extractGoogleDriveFileId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    // Format: https://drive.google.com/file/d/FILE_ID/view...
    final fileDMatch = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (fileDMatch != null && fileDMatch.group(1) != null) {
      return fileDMatch.group(1)!;
    }

    // Format: ?id=FILE_ID or &id=FILE_ID
    final idParamMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (idParamMatch != null && idParamMatch.group(1) != null) {
      return idParamMatch.group(1)!;
    }

    // Format: attendmate://live/FILE_ID or attendmate://timetable/FILE_ID
    final customSchemeMatch = RegExp(r'attendmate://(?:live|timetable)/([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (customSchemeMatch != null && customSchemeMatch.group(1) != null) {
      return customSchemeMatch.group(1)!;
    }

    // Format: raw ID string (Google Drive IDs are typically alphanumeric with '-' or '_', 25-45 characters)
    if (RegExp(r'^[a-zA-Z0-9_-]{15,}$').hasMatch(trimmed)) {
      return trimmed;
    }

    return trimmed;
  }

  // ==========================================
  // HOST (CLASS REP) FUNCTIONALITY
  // ==========================================

  /// Packages current local timetable data without student attendance history
  Future<Map<String, dynamic>> _prepareLivePayload({
    required String className,
    required String creatorName,
    required int version,
  }) async {
    final dbService = DatabaseService();
    await dbService.init();

    final semester = await dbService.loadSemester();
    final subjects = await dbService.loadSubjects();
    final locations = await dbService.loadLocations();

    final sanitizedSubjects = subjects.map((s) {
      final jsonMap = s.toJson();
      // Ensure past attendance records are stripped completely for class distribution
      jsonMap['attendanceRecords'] = [];
      return jsonMap;
    }).toList();

    return {
      'app': 'AttendMate',
      'type': 'live_timetable_share',
      'schema_version': 1,
      'sync_version': version,
      'class_name': className.trim(),
      'creator_name': creatorName.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'semester': semester?.toJson(),
      'subjects': sanitizedSubjects,
      'locations': locations.map((l) => l.toMap()).toList(),
    };
  }

  /// Publishes local timetable to Google Drive as a public file and marks this device as Host
  Future<String> hostLiveTimetable({
    required String className,
    required String creatorName,
  }) async {
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) {
      throw Exception('Google account authentication required to host a class timetable.');
    }

    final driveApi = drive.DriveApi(client);
    final payload = await _prepareLivePayload(
      className: className,
      creatorName: creatorName,
      version: 1,
    );

    final subjects = payload['subjects'] as List? ?? [];
    if (subjects.isEmpty) {
      throw Exception('No subjects found to share. Please add subjects to your timetable first.');
    }

    final jsonString = jsonEncode(payload);
    final bytes = utf8.encode(jsonString);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'application/json',
    );

    // 1. Create file on Drive inside AttendMate folder
    final folderId = await GoogleDriveBackupService().getOrCreateAppFolder(driveApi);
    final sanitizedFileName = className.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final driveFile = drive.File()
      ..name = 'attendmate_live_$sanitizedFileName.json'
      ..description = 'AttendMate Live Timetable for $className'
      ..mimeType = 'application/json'
      ..parents = folderId != null ? [folderId] : null;

    final createdFile = await driveApi.files.create(
      driveFile,
      uploadMedia: media,
      $fields: 'id, name',
    );

    final fileId = createdFile.id;
    if (fileId == null || fileId.isEmpty) {
      throw Exception('Failed to create file on Google Drive.');
    }

    // 2. Grant public read-only permission (role: reader, type: anyone)
    final permission = drive.Permission()
      ..role = 'reader'
      ..type = 'anyone';

    await driveApi.permissions.create(
      permission,
      fileId,
      $fields: 'id',
    );

    // 3. Save Host state
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    _isHost = true;
    _hostedFileId = fileId;
    _hostedClassName = className;
    _hostedVersion = 1;
    _hostedLastPushedAt = now;

    await prefs.setBool(_keyIsHost, true);
    await prefs.setString(_keyHostedFileId, fileId);
    await prefs.setString(_keyHostedClassName, className);
    await prefs.setInt(_keyHostedVersion, 1);
    await prefs.setString(_keyHostedLastPushedAt, now.toUtc().toIso8601String());

    // If previously subscribed, cancel subscription since this device is now Host
    if (_isSubscribed) {
      await unsubscribe();
    }

    await DatabaseService().logAppEvent(
      tag: 'LiveTimetableSync',
      message: 'Successfully published Live Timetable: $className ($fileId)',
    );

    notifyListeners();
    return fileId;
  }

  /// Pushes local schedule changes to the existing hosted Google Drive file
  Future<int> pushLiveUpdate() async {
    if (!_isHost || _hostedFileId == null) {
      throw Exception('This device is not currently hosting a live timetable.');
    }

    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) {
      throw Exception('Google account authentication required to push timetable updates.');
    }

    final newVersion = _hostedVersion + 1;
    final payload = await _prepareLivePayload(
      className: _hostedClassName ?? 'Class Timetable',
      creatorName: GoogleAuthService.instance.currentUser?.displayName ?? 'Class Rep',
      version: newVersion,
    );

    final jsonString = jsonEncode(payload);
    final bytes = utf8.encode(jsonString);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'application/json',
    );

    final driveApi = drive.DriveApi(client);
    final updateFile = drive.File();

    await driveApi.files.update(
      updateFile,
      _hostedFileId!,
      uploadMedia: media,
    );

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    _hostedVersion = newVersion;
    _hostedLastPushedAt = now;

    await prefs.setInt(_keyHostedVersion, newVersion);
    await prefs.setString(_keyHostedLastPushedAt, now.toUtc().toIso8601String());

    await DatabaseService().logAppEvent(
      tag: 'LiveTimetableSync',
      message: 'Pushed Live Timetable update v$newVersion ($_hostedFileId)',
    );

    notifyListeners();
    return newVersion;
  }

  /// Stops hosting the timetable and removes local hosting metadata
  Future<void> stopHosting({bool deleteFromDrive = false}) async {
    if (_isHost && _hostedFileId != null && deleteFromDrive) {
      try {
        final client = await GoogleAuthService.instance.getAuthenticatedClient();
        if (client != null) {
          final driveApi = drive.DriveApi(client);
          await driveApi.files.delete(_hostedFileId!);
        }
      } catch (e) {
        debugPrint('Failed to delete live file from Google Drive: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    _isHost = false;
    _hostedFileId = null;
    _hostedClassName = null;
    _hostedVersion = 1;
    _hostedLastPushedAt = null;

    await prefs.remove(_keyIsHost);
    await prefs.remove(_keyHostedFileId);
    await prefs.remove(_keyHostedClassName);
    await prefs.remove(_keyHostedVersion);
    await prefs.remove(_keyHostedLastPushedAt);

    await DatabaseService().logAppEvent(
      tag: 'LiveTimetableSync',
      message: 'Stopped hosting live timetable.',
    );

    notifyListeners();
  }

  // ==========================================
  // FOLLOWER (SUBSCRIBER) FUNCTIONALITY
  // ==========================================

  /// Downloads public timetable data from Google Drive anonymously without requiring user sign-in
  Future<Map<String, dynamic>> fetchPublicTimetable(String codeOrUrl) async {
    final fileId = extractGoogleDriveFileId(codeOrUrl);
    if (fileId.isEmpty) {
      throw Exception('Invalid Class Code or Google Drive link.');
    }

    final primaryUrl = Uri.parse('https://drive.google.com/uc?export=download&id=$fileId');
    http.Response response;

    try {
      response = await http.get(
        primaryUrl,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'AttendMate-App',
        },
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      // Fallback endpoint
      final fallbackUrl = Uri.parse(
        'https://drive.usercontent.google.com/download?id=$fileId&export=download&authuser=0',
      );
      response = await http.get(
        fallbackUrl,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'AttendMate-App',
        },
      ).timeout(const Duration(seconds: 15));
    }

    if (response.statusCode == 200) {
      final body = utf8.decode(response.bodyBytes);
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (!decoded.containsKey('subjects')) {
          throw Exception('The shared file does not contain timetable subject data.');
        }
        return decoded;
      }
      throw Exception('Malformed timetable data received from Google Drive.');
    } else if (response.statusCode == 404) {
      throw Exception('Class timetable not found. The host may have unshared or removed it.');
    } else if (response.statusCode == 403) {
      throw Exception('Access restricted. Please ensure the host enabled public sharing.');
    } else {
      throw Exception('Failed to fetch timetable (HTTP ${response.statusCode}).');
    }
  }

  /// Subscribes to a timetable, merges data into local database, and persists subscription info
  Future<bool> subscribeToTimetable(
    String codeOrUrl,
    Map<String, dynamic> data,
    BuildContext context, {
    required bool mergeIntoCurrent,
    bool alreadyImported = false,
  }) async {
    final fileId = extractGoogleDriveFileId(codeOrUrl);
    if (fileId.isEmpty) {
      throw Exception('Invalid Class Code.');
    }

    if (!alreadyImported) {
      final success = await applyTimetableData(
        data,
        context,
        mergeIntoCurrent: mergeIntoCurrent,
      );
      if (!success) return false;
    }

    final className = data['class_name'] as String? ?? 'Class Timetable';
    final creatorName = data['creator_name'] as String? ?? 'Class Rep';
    final version = data['sync_version'] as int? ?? 1;
    final now = DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    _isSubscribed = true;
    _subscribedFileId = fileId;
    _subscribedClassName = className;
    _subscribedCreatorName = creatorName;
    _subscribedVersion = version;
    _subscribedLastSyncedAt = now;

    await prefs.setBool(_keyIsSubscribed, true);
    await prefs.setString(_keySubscribedFileId, fileId);
    await prefs.setString(_keySubscribedClassName, className);
    await prefs.setString(_keySubscribedCreatorName, creatorName);
    await prefs.setInt(_keySubscribedVersion, version);
    await prefs.setString(_keySubscribedLastSyncedAt, now.toUtc().toIso8601String());

    // If this device was previously marked as host, clear host status
    if (_isHost) {
      await stopHosting(deleteFromDrive: false);
    }

    await DatabaseService().logAppEvent(
      tag: 'LiveTimetableSync',
      message: 'Subscribed to Live Timetable: $className ($fileId, v$version)',
    );

    notifyListeners();
    return true;
  }

  /// Checks if the hosted timetable has a newer version or update timestamp
  Future<Map<String, dynamic>?> checkForRemoteUpdates() async {
    if (!_isSubscribed || _subscribedFileId == null) {
      return null;
    }

    try {
      final remoteData = await fetchPublicTimetable(_subscribedFileId!);
      final remoteVersion = remoteData['sync_version'] as int? ?? 1;

      if (remoteVersion > _subscribedVersion) {
        return remoteData;
      }

      // Check timestamp if version is equal
      final remoteUpdatedAtStr = remoteData['updated_at'] as String?;
      if (remoteUpdatedAtStr != null && _subscribedLastSyncedAt != null) {
        final remoteTime = DateTime.tryParse(remoteUpdatedAtStr)?.toLocal();
        if (remoteTime != null && remoteTime.isAfter(_subscribedLastSyncedAt!)) {
          return remoteData;
        }
      }

      return null;
    } catch (e) {
      debugPrint('checkForRemoteUpdates error: $e');
      return null;
    }
  }

  /// Applies an update received from the Host without overwriting local attendance records
  Future<bool> applyRemoteUpdate(
    Map<String, dynamic> remoteData,
    BuildContext context,
  ) async {
    final success = await applyTimetableData(
      remoteData,
      context,
      mergeIntoCurrent: true,
    );

    if (!success) return false;

    final newVersion = remoteData['sync_version'] as int? ?? (_subscribedVersion + 1);
    final now = DateTime.now();

    final prefs = await SharedPreferences.getInstance();
    _subscribedVersion = newVersion;
    _subscribedLastSyncedAt = now;

    await prefs.setInt(_keySubscribedVersion, newVersion);
    await prefs.setString(_keySubscribedLastSyncedAt, now.toUtc().toIso8601String());

    await DatabaseService().logAppEvent(
      tag: 'LiveTimetableSync',
      message: 'Applied Live Timetable update v$newVersion ($_subscribedFileId)',
    );

    notifyListeners();
    return true;
  }

  /// Unsubscribes from live updates (retains all existing subjects and attendance intact)
  Future<void> unsubscribe() async {
    final prefs = await SharedPreferences.getInstance();

    _isSubscribed = false;
    _subscribedFileId = null;
    _subscribedClassName = null;
    _subscribedCreatorName = null;
    _subscribedVersion = 1;
    _subscribedLastSyncedAt = null;

    await prefs.remove(_keyIsSubscribed);
    await prefs.remove(_keySubscribedFileId);
    await prefs.remove(_keySubscribedClassName);
    await prefs.remove(_keySubscribedCreatorName);
    await prefs.remove(_keySubscribedVersion);
    await prefs.remove(_keySubscribedLastSyncedAt);

    await DatabaseService().logAppEvent(
      tag: 'LiveTimetableSync',
      message: 'Unsubscribed from live timetable updates.',
    );

    notifyListeners();
  }

  /// Toggles auto-checking on app resume
  Future<void> setAutoCheckEnabled(bool enabled) async {
    _autoCheckEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoCheckEnabled, enabled);
    notifyListeners();
  }

  // ==========================================
  // SAFE NON-DESTRUCTIVE DATABASE MERGE
  // ==========================================

  /// Merges remote timetable data into SQLite while strictly preserving local attendance records
  Future<bool> applyTimetableData(
    Map<String, dynamic> data,
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

      // 1. Extract Semester
      final semesterMap = data['semester'] as Map<String, dynamic>?;
      Semester? importedSemester;
      if (semesterMap != null) {
        importedSemester = Semester.fromJson(semesterMap);
      }

      // 2. Extract Subjects
      final subjectsRaw = data['subjects'] as List? ?? [];
      final List<Subject> importedSubjects = [];
      for (final item in subjectsRaw) {
        if (item is Map<String, dynamic>) {
          final s = Subject.fromJson(item);
          // Always ensure incoming attendance records are empty
          importedSubjects.add(s.copyWith(attendanceRecords: const []));
        }
      }

      // 3. Extract Locations
      final locationsRaw = data['locations'] as List? ?? [];
      final List<LocationConfig> importedLocations = [];
      for (final item in locationsRaw) {
        if (item is Map<String, dynamic>) {
          importedLocations.add(LocationConfig.fromMap(item));
        }
      }

      if (!mergeIntoCurrent) {
        // Complete overwrite (only used on initial fresh setup)
        await dbService.clearSemesterAndAllData();
        if (importedSemester != null) {
          await semesterProv.updateSemester(importedSemester);
        }
      } else {
        // Non-destructive merge: update semester dates if not set
        if (semesterProv.semester == null && importedSemester != null) {
          await semesterProv.updateSemester(importedSemester);
        }
      }

      // Save Locations
      for (final loc in importedLocations) {
        await dbService.saveLocation(loc);
      }

      // Merge Subjects safely
      if (!mergeIntoCurrent) {
        await dbService.saveSubjects(importedSubjects);
      } else {
        final currentSubjects = List<Subject>.from(subjectProv.subjects);

        for (final newSub in importedSubjects) {
          final existingIdx = currentSubjects.indexWhere(
            (s) =>
                s.name.trim().toLowerCase() == newSub.name.trim().toLowerCase() ||
                (s.acronym != null &&
                    s.acronym!.trim().isNotEmpty &&
                    s.acronym!.trim().toLowerCase() == (newSub.acronym ?? '').trim().toLowerCase()),
          );

          if (existingIdx != -1) {
            // MATCH FOUND:
            // Update schedule timings, room, block, locationId
            // Crucially: KEEPS existing ID, existing attendanceRecords, and existing targetAttendance!
            currentSubjects[existingIdx] = currentSubjects[existingIdx].copyWith(
              schedule: newSub.schedule,
              room: () => newSub.room,
              block: () => newSub.block,
              locationId: () => newSub.locationId,
            );
          } else {
            // NEW SUBJECT added by Class Rep: add it with empty attendance
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
      debugPrint('LiveTimetableSyncService applyTimetableData error: $e');
      return false;
    }
  }

  // ==========================================
  // APP RESUME HOOK
  // ==========================================

  /// Checks for updates when the app resumes (rate-limited to once every 10 minutes)
  Future<void> checkOnAppResume(BuildContext context) async {
    if (!_isInitialized) {
      await init();
    }

    if (!_isSubscribed || !_autoCheckEnabled || _subscribedFileId == null) {
      return;
    }

    final now = DateTime.now();
    if (_lastResumeCheckTime != null && now.difference(_lastResumeCheckTime!).inMinutes < 10) {
      return;
    }
    _lastResumeCheckTime = now;

    final updateData = await checkForRemoteUpdates();
    if (updateData != null && context.mounted) {
      final className = updateData['class_name'] as String? ?? _subscribedClassName ?? 'Class';
      final newVer = updateData['sync_version'] as int? ?? (_subscribedVersion + 1);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
          content: Text('$className timetable updated (v$newVer)!'),
          action: SnackBarAction(
            label: 'Apply Update',
            onPressed: () async {
              final ok = await applyRemoteUpdate(updateData, context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
                    content: Text(
                      ok
                          ? 'Timetable updated successfully!'
                          : 'Failed to apply timetable update.',
                    ),
                  ),
                );
              }
            },
          ),
        ),
      );
    }
  }
}
