import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';
import 'backup_service.dart';
import 'database_service.dart';
import 'google_auth_service.dart';
import 'notification_service.dart';

class DriveBackupFileInfo {
  final String fileId;
  final String fileName;
  final DateTime modifiedTime;
  final int sizeBytes;

  DriveBackupFileInfo({
    required this.fileId,
    required this.fileName,
    required this.modifiedTime,
    required this.sizeBytes,
  });
}

class GoogleDriveBackupService {
  static final GoogleDriveBackupService _instance = GoogleDriveBackupService._internal();
  factory GoogleDriveBackupService() => _instance;
  GoogleDriveBackupService._internal();

  static const String backupFileName = 'attendmate_cloud_backup.json';
  static const String appFolderName = 'AttendMate';
  static const String prefGoogleDriveBackupEnabledKey = 'google_drive_backup_enabled';
  static const String prefLastDriveBackupTimeKey = 'last_google_drive_backup_time';

  static bool? _cachedIsBackupEnabled;
  static DateTime? _cachedLastBackupTime;
  static DriveBackupFileInfo? _cachedExistingBackup;

  /// Fast synchronous getter for in-memory cached state
  static bool get isBackupEnabledSync => _cachedIsBackupEnabled ?? false;
  static DateTime? get lastBackupTimeSync => _cachedLastBackupTime;
  static DriveBackupFileInfo? get cachedExistingBackup => _cachedExistingBackup;

  /// Helper to find or create the dedicated 'AttendMate' folder in Google Drive
  Future<String?> getOrCreateAppFolder(drive.DriveApi driveApi) async {
    try {
      final folderList = await driveApi.files.list(
        q: "name = '$appFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      final folders = folderList.files;
      if (folders != null && folders.isNotEmpty) {
        return folders.first.id;
      }

      final newFolder = drive.File()
        ..name = appFolderName
        ..description = 'AttendMate application backups and shared timetables'
        ..mimeType = 'application/vnd.google-apps.folder';

      final created = await driveApi.files.create(
        newFolder,
        $fields: 'id',
      );
      return created.id;
    } catch (e) {
      debugPrint('GoogleDriveBackupService getOrCreateAppFolder error: $e');
      return null;
    }
  }

  Future<bool> isBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getBool(prefGoogleDriveBackupEnabledKey) ?? false;
    _cachedIsBackupEnabled = val;
    return val;
  }

  Future<void> setBackupEnabled(bool enabled) async {
    _cachedIsBackupEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefGoogleDriveBackupEnabledKey, enabled);
  }

  Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(prefLastDriveBackupTimeKey);
    if (str != null && str.isNotEmpty) {
      _cachedLastBackupTime = DateTime.tryParse(str)?.toLocal();
      return _cachedLastBackupTime;
    }
    return null;
  }

  /// Query Google Drive for the existing single cloud backup file
  Future<DriveBackupFileInfo?> checkForExistingBackup() async {
    try {
      final client = await GoogleAuthService.instance.getAuthenticatedClient();
      if (client == null) {
        _cachedExistingBackup = null;
        return null;
      }

      final driveApi = drive.DriveApi(client);
      final fileList = await driveApi.files.list(
        q: "name = '$backupFileName' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime, size, createdTime)',
      );

      final files = fileList.files;
      if (files != null && files.isNotEmpty) {
        final f = files.first;
        final modifiedTime = f.modifiedTime ?? f.createdTime ?? DateTime.now();
        final sizeBytes = int.tryParse(f.size ?? '0') ?? 0;
        final info = DriveBackupFileInfo(
          fileId: f.id!,
          fileName: f.name ?? backupFileName,
          modifiedTime: modifiedTime.toLocal(),
          sizeBytes: sizeBytes,
        );
        _cachedExistingBackup = info;
        return info;
      }
      _cachedExistingBackup = null;
      return null;
    } catch (e) {
      debugPrint('GoogleDriveBackupService checkForExistingBackup error: $e');
      return null;
    }
  }

  /// Upload the latest database state to Google Drive as a single JSON file
  Future<bool> uploadBackup({bool force = false, bool interactive = true}) async {
    try {
      if (!force && !await isBackupEnabled()) {
        debugPrint('GoogleDriveBackupService: Auto-backup skipped (disabled).');
        await DatabaseService().logAppEvent(
          tag: 'GoogleDriveBackup',
          message: 'Google Drive backup skipped: Disabled in settings.',
          level: 'INFO',
        );
        return false;
      }

      final client = await GoogleAuthService.instance.getAuthenticatedClient(interactive: interactive);
      if (client == null) {
        debugPrint('GoogleDriveBackupService: No authenticated Google client available.');
        await DatabaseService().logAppEvent(
          tag: 'GoogleDriveBackup',
          message: 'Google Drive backup aborted: Unable to obtain authenticated client ${interactive ? "" : "(silent login returned null; user may need to re-login in Google Integrations)"}.',
          level: 'WARNING',
        );
        return false;
      }

      final driveApi = drive.DriveApi(client);
      final backupData = await BackupService().exportBackupData();
      final jsonString = jsonEncode(backupData);
      final bytes = utf8.encode(jsonString);

      final mediaContent = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'application/json',
      );

      // Check if file already exists in Drive
      final existing = await checkForExistingBackup();
      final folderId = await getOrCreateAppFolder(driveApi);

      String targetFileId;
      if (existing != null) {
        final updateFile = drive.File();
        final updated = await driveApi.files.update(
          updateFile,
          existing.fileId,
          uploadMedia: mediaContent,
          addParents: folderId,
        );
        targetFileId = updated.id ?? existing.fileId;
        debugPrint('GoogleDriveBackupService: Updated existing backup $targetFileId');
      } else {
        final newFile = drive.File()
          ..name = backupFileName
          ..description = 'AttendMate full database cloud backup'
          ..mimeType = 'application/json'
          ..parents = folderId != null ? [folderId] : null;

        final created = await driveApi.files.create(
          newFile,
          uploadMedia: mediaContent,
        );
        targetFileId = created.id ?? 'unknown';
        debugPrint('GoogleDriveBackupService: Created new cloud backup $targetFileId');
      }

      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toUtc();
      await prefs.setString(prefLastDriveBackupTimeKey, now.toIso8601String());

      await DatabaseService().logAppEvent(
        tag: 'GoogleDriveBackup',
        message: 'Successfully backed up database to Google Drive ($backupFileName, ID: $targetFileId).',
        level: 'INFO',
      );

      return true;
    } catch (e) {
      debugPrint('GoogleDriveBackupService uploadBackup error: $e');
      await DatabaseService().logAppEvent(
        tag: 'GoogleDriveBackup',
        message: 'Failed to backup database to Google Drive: $e',
        level: 'ERROR',
      );
      return false;
    }
  }

  /// Download and restore the latest database backup from Google Drive
  Future<bool> restoreLatestBackupFromDrive({BuildContext? context}) async {
    try {
      final client = await GoogleAuthService.instance.getAuthenticatedClient();
      if (client == null) {
        throw Exception('Google account is not authenticated.');
      }

      final existing = await checkForExistingBackup();
      if (existing == null) {
        throw Exception('No cloud backup found on your Google Drive.');
      }

      final driveApi = drive.DriveApi(client);
      final dynamic mediaResponse = await driveApi.files.get(
        existing.fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );

      if (mediaResponse is! drive.Media) {
        throw Exception('Failed to retrieve file contents from Google Drive.');
      }

      final List<int> byteList = [];
      await for (final chunk in mediaResponse.stream) {
        byteList.addAll(chunk);
      }

      final jsonString = utf8.decode(byteList);
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

      if (context != null && !context.mounted) return false;
      final success = await BackupService().restoreBackupFromData(backupData, context: context);
      if (success) {
        await DatabaseService().logAppEvent(
          tag: 'GoogleDriveBackup',
          message: 'Restored database successfully from Google Drive backup (${existing.fileId}).',
        );
      }
      return success;
    } catch (e) {
      debugPrint('GoogleDriveBackupService restore error: $e');
      return false;
    }
  }

  /// Background midnight backup trigger
  Future<void> executeMidnightBackup() async {
    await DatabaseService().logAppEvent(
      tag: 'GoogleDriveBackup',
      message: 'Midnight Google Drive cloud backup trigger started.',
      level: 'INFO',
    );

    if (!await isBackupEnabled()) {
      await DatabaseService().logAppEvent(
        tag: 'GoogleDriveBackup',
        message: 'Midnight cloud backup skipped: Google Drive backup is disabled in settings.',
        level: 'INFO',
      );
      return;
    }

    final signedIn = await GoogleAuthService.instance.isSignedIn();
    if (!signedIn) {
      await DatabaseService().logAppEvent(
        tag: 'GoogleDriveBackup',
        message: 'Midnight cloud backup skipped: User is not signed into Google account.',
        level: 'WARNING',
      );
      return;
    }

    final hasChanges = await BackupService().hasUnbackedDataChanges();
    if (!hasChanges) {
      await DatabaseService().logAppEvent(
        tag: 'GoogleDriveBackup',
        message: 'Midnight cloud backup skipped: No unbacked database changes found since last backup.',
        level: 'INFO',
      );
      return;
    }

    await DatabaseService().logAppEvent(
      tag: 'GoogleDriveBackup',
      message: 'Running midnight Google Drive backup...',
      level: 'INFO',
    );

    final success = await uploadBackup(force: true, interactive: false);
    if (success) {
      try {
        await NotificationService().showBackupNotification(
          title: 'Google Drive Backup Synced',
          body: 'Your attendance data & settings have been backed up to Google Drive.',
        );
      } catch (e) {
        debugPrint('GoogleDriveBackupService: Suppressed notification error in background: $e');
      }
    }
  }
}
