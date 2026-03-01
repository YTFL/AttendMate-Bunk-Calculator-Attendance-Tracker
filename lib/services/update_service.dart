import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_update_model.dart';
import 'database_service.dart';

enum InstallResult {
  installerStarted,
  permissionRequired,
  installerUnavailable,
  failed,
}

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  final DatabaseService _dbService = DatabaseService();
  static const platform = MethodChannel('com.attendmate.app/update');

  // GitHub raw URL for update.json
  static const String updateJsonUrl =
      'https://raw.githubusercontent.com/YTFL/AttendMate-Bunk-Calculator-Attendance-Tracker/main/update.json';

  // Reminder period: 24 hours
  static const Duration reminderPeriod = Duration(hours: 24);

  static const String _installResultStarted = 'installer_started';
  static const String _installResultPermissionRequired = 'permission_required';
  static const String _installResultInstallerNotFound = 'installer_not_found';

  /// Check if update is available and not deferred
  /// Returns null if no update needed, otherwise returns AppUpdate
  /// Checks on every call (no 24-hour throttling for foreground checks)
  Future<AppUpdate?> checkForUpdate({bool respectDeferral = true}) async {
    try {
      // Check if deferred
      if (respectDeferral) {
        final deferredUntil = await _dbService.getDeferredUntil();
        if (deferredUntil != null && DateTime.now().isBefore(deferredUntil)) {
          return null;
        }
      }

      // Fetch remote update info
      final remoteUpdate = await fetchRemoteUpdate();
      if (remoteUpdate == null) return null;

      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      final versionComparison = AppUpdate.compareVersions(
        remoteUpdate.version,
        currentVersion,
      );
      final hasUpdateAvailable =
          versionComparison > 0 ||
          (versionComparison == 0 && remoteUpdate.buildNumber > currentBuildNumber);

      // Compare versions and build numbers
      if (hasUpdateAvailable) {
        // Update last check date
        await _dbService.updateLastCheckDate(DateTime.now());
        return remoteUpdate;
      }

      // App is on latest version - delete any downloaded APKs
      await deleteDownloadedAPK();
      return null;
    } catch (e) {
      debugPrint('Error checking for update: $e');
      return null;
    }
  }

  /// Fetch update metadata from GitHub
  Future<AppUpdate?> fetchRemoteUpdate() async {
    try {
      final response = await http.get(Uri.parse(updateJsonUrl)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final update = AppUpdate.fromJson(json);
        
        // Fetch release notes from GitHub API
        final releaseNotes = await fetchReleaseNotes(update.version);
        return update.copyWith(changelog: releaseNotes);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching remote update: $e');
      return null;
    }
  }

  /// Fetch release notes from GitHub releases API
  Future<String> fetchReleaseNotes(String version) async {
    try {
      final releaseUrl =
          'https://api.github.com/repos/YTFL/AttendMate-Bunk-Calculator-Attendance-Tracker/releases/tags/v$version';
      
      final response = await http.get(Uri.parse(releaseUrl)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final body = json['body'] as String? ?? '';
        if (body.isEmpty) {
          return 'No release notes available';
        }

        final sanitizedBody = _sanitizeReleaseNotesForInAppUpdate(body);
        return sanitizedBody.isNotEmpty ? sanitizedBody : 'No release notes available';
      }
      return 'Release notes not found';
    } catch (e) {
      debugPrint('Error fetching release notes: $e');
      return 'Unable to fetch release notes';
    }
  }

  String _sanitizeReleaseNotesForInAppUpdate(String markdown) {
    final normalized = markdown.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return normalized;

    var lines = normalized.split('\n');
    lines = _removeTopMetadataBlock(lines);
    lines = _removeInstallationSection(lines);

    final sanitized = lines.join('\n').trim();
    return sanitized;
  }

  List<String> _removeTopMetadataBlock(List<String> lines) {
    if (lines.isEmpty) return lines;

    final firstNonEmptyIndex = lines.indexWhere((line) => line.trim().isNotEmpty);
    if (firstNonEmptyIndex == -1) return lines;

    final firstNonEmpty = lines[firstNonEmptyIndex].trim();
    if (!firstNonEmpty.startsWith('# ')) {
      return lines;
    }

    final separatorIndex = lines.indexWhere(
      (line) => line.trim() == '---',
      firstNonEmptyIndex,
    );

    if (separatorIndex == -1) {
      return lines;
    }

    return lines.sublist(separatorIndex + 1);
  }

  List<String> _removeInstallationSection(List<String> lines) {
    if (lines.isEmpty) return lines;

    final installationHeaderRegex = RegExp(r'^##\s+.*installation', caseSensitive: false);
    final sectionHeaderRegex = RegExp(r'^##\s+');

    final startIndex = lines.indexWhere(
      (line) => installationHeaderRegex.hasMatch(line.trim()),
    );

    if (startIndex == -1) {
      return lines;
    }

    var endIndex = lines.length;
    for (var index = startIndex + 1; index < lines.length; index++) {
      if (sectionHeaderRegex.hasMatch(lines[index].trim())) {
        endIndex = index;
        break;
      }
    }

    return [
      ...lines.sublist(0, startIndex),
      ...lines.sublist(endIndex),
    ];
  }

  /// Fetch the published date of the latest GitHub release
  Future<DateTime?> fetchLatestReleaseDate() async {
    try {
      const latestReleaseUrl =
          'https://api.github.com/repos/YTFL/AttendMate-Bunk-Calculator-Attendance-Tracker/releases/latest';

      final response = await http.get(Uri.parse(latestReleaseUrl)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final publishedAt = json['published_at'] as String?;
        if (publishedAt == null || publishedAt.isEmpty) {
          return null;
        }
        return DateTime.tryParse(publishedAt);
      }

      return null;
    } catch (e) {
      debugPrint('Error fetching latest release date: $e');
      return null;
    }
  }

  /// Download APK file from GitHub releases
  /// URL pattern: https://github.com/YTFL/AttendMate-Bunk-Calculator-Attendance-Tracker/releases/download/v{version}/AttendMate-v{version}.apk
  Future<File?> downloadAPK(String remoteVersion) async {
    try {
      final apkUrl =
          'https://github.com/YTFL/AttendMate-Bunk-Calculator-Attendance-Tracker/releases/download/v$remoteVersion/AttendMate-v$remoteVersion.apk';

      final response = await http.get(Uri.parse(apkUrl)).timeout(
        const Duration(seconds: 60),
      );

      if (response.statusCode == 200) {
        final directory = await getApplicationDocumentsDirectory();
        final apkPath = '${directory.path}/attendmate-update.apk';
        final file = File(apkPath);
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
      return null;
    } catch (e) {
      debugPrint('Error downloading APK: $e');
      return null;
    }
  }

  /// Delete the downloaded APK file
  Future<void> deleteDownloadedAPK() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final apkPath = '${directory.path}/attendmate-update.apk';
      final file = File(apkPath);
      
      if (await file.exists()) {
        await file.delete();
        debugPrint('Deleted downloaded APK: $apkPath');
      }
    } catch (e) {
      debugPrint('Error deleting downloaded APK: $e');
    }
  }

  /// Install APK using Android system installer via native method channel
  Future<InstallResult> installAPK(File apkFile) async {
    try {
      if (!Platform.isAndroid) {
        return InstallResult.failed;
      }

      final openResult = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      switch (openResult.type) {
        case ResultType.done:
          return InstallResult.installerStarted;
        case ResultType.noAppToOpen:
          return InstallResult.installerUnavailable;
        case ResultType.permissionDenied:
          return InstallResult.permissionRequired;
        case ResultType.fileNotFound:
          return InstallResult.failed;
        case ResultType.error:
          break;
      }

      // Fallback: call native Android method if OpenFilex fails
      final result = await platform.invokeMethod<String>(
        'installAPK',
        {'apkPath': apkFile.path},
      );

      if (result == _installResultStarted) {
        return InstallResult.installerStarted;
      }
      if (result == _installResultPermissionRequired) {
        return InstallResult.permissionRequired;
      }
      if (result == _installResultInstallerNotFound) {
        return InstallResult.installerUnavailable;
      }
      return InstallResult.failed;
    } catch (e) {
      debugPrint('Error installing APK: $e');
      return InstallResult.failed;
    }
  }

  /// Defer update for 7 days
  Future<void> deferUpdate() async {
    try {
      final deferUntil = DateTime.now().add(reminderPeriod);
      await _dbService.setDeferredUntil(deferUntil);
    } catch (e) {
      debugPrint('Error deferring update: $e');
    }
  }

  /// Clear deferral
  Future<void> clearDeferral() async {
    try {
      await _dbService.clearDeferral();
    } catch (e) {
      debugPrint('Error clearing deferral: $e');
    }
  }

  /// Get last update check date
  Future<DateTime?> getLastCheckDate() async {
    try {
      return await _dbService.getLastCheckDate();
    } catch (e) {
      return null;
    }
  }

  /// Check if 24 hours have passed since last check
  Future<bool> shouldCheckForUpdate() async {
    try {
      final lastCheck = await getLastCheckDate();
      if (lastCheck == null) return true;

      final now = DateTime.now();
      final difference = now.difference(lastCheck);
      return difference.inHours >= 24;
    } catch (e) {
      return true;
    }
  }
}
