import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/database_service.dart';
import 'snackbar_utils.dart';
import 'url_launcher_utils.dart';

class GitHubIssueHelper {
  static const String repoIssuesUrl =
      'https://github.com/YTFL/AttendMate-Bunk-Calculator-Attendance-Tracker/issues/new';

  /// Format and open a new GitHub Issue with details from a log entry or error.
  static Future<void> createIssueFromLog({
    BuildContext? context,
    required String tag,
    required String message,
    String level = 'ERROR',
    String? timestamp,
    String? errorStackTrace,
  }) async {
    // Log event to database if needed
    try {
      await DatabaseService().logAppEvent(
        tag: tag,
        message: message,
        level: level,
      );
    } catch (_) {}

    String versionStr = 'Unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      versionStr = 'v${info.version} (Build ${info.buildNumber})';
    } catch (_) {}

    String platformStr = 'Unknown Platform';
    try {
      platformStr = Platform.isAndroid
          ? 'Android'
          : Platform.isIOS
              ? 'iOS'
              : Platform.isWindows
                  ? 'Windows'
                  : Platform.isMacOS
                      ? 'macOS'
                      : Platform.isLinux
                          ? 'Linux'
                          : 'Unknown';
    } catch (_) {}

    final timeStr = timestamp ?? DateTime.now().toIso8601String();

    // Prepare full log markdown text for clipboard
    final fullLogMarkdown = StringBuffer()
      ..writeln('### Environment')
      ..writeln('- **App Version:** $versionStr')
      ..writeln('- **Platform:** $platformStr')
      ..writeln('- **Timestamp:** $timeStr')
      ..writeln()
      ..writeln('### Log Details')
      ..writeln('- **Tag:** `$tag`')
      ..writeln('- **Level:** `$level`')
      ..writeln()
      ..writeln('```')
      ..writeln(message)
      ..writeln('```');

    if (errorStackTrace != null && errorStackTrace.isNotEmpty) {
      fullLogMarkdown
        ..writeln()
        ..writeln('### Stack Trace')
        ..writeln('```')
        ..writeln(errorStackTrace)
        ..writeln('```');
    }

    final clipboardText = fullLogMarkdown.toString();
    await Clipboard.setData(ClipboardData(text: clipboardText));

    // Construct short issue title
    final firstLine = message.replaceAll('\r\n', '\n').split('\n').first.trim();
    final titleMsg = firstLine.length > 50
        ? '${firstLine.substring(0, 47)}...'
        : (firstLine.isEmpty ? 'App Diagnostic Log Report' : firstLine);
    final issueTitle = '[DIAGNOSTICS] [$tag] $titleMsg';

    // Construct logs text for URL parameter (truncate if too long to fit browser URL limits)
    final truncatedLog = message.length > 600
        ? '${message.substring(0, 600)}\n... [Log truncated for URL length. Full log copied to clipboard!]'
        : message;

    final String logsFieldContent = (errorStackTrace != null && errorStackTrace.isNotEmpty)
        ? '$truncatedLog\n\n--- Stack Trace ---\n$errorStackTrace'
        : truncatedLog;

    final Uri issueUri = Uri.parse(repoIssuesUrl).replace(
      queryParameters: {
        'template': 'diagnostics_report.yml',
        'title': issueTitle,
        'app-version': versionStr,
        'platform-device': platformStr,
        'log-tag': '$tag ($level)',
        'diagnostic-logs': logsFieldContent,
      },
    );

    final launched = await UrlLauncherUtils.launchExternalUrl(issueUri.toString());

    if (context != null && context.mounted) {
      if (launched) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('Opening GitHub Issue page... Log copied to clipboard!'),
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('Could not open browser. Full log copied to clipboard.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Create issue from a database log map entry
  static Future<void> createIssueFromLogMap(
    BuildContext? context,
    Map<String, dynamic> log,
  ) async {
    await createIssueFromLog(
      context: context,
      tag: log['tag']?.toString() ?? 'AppLog',
      message: log['message']?.toString() ?? '',
      level: log['level']?.toString() ?? 'INFO',
      timestamp: log['timestamp']?.toString(),
    );
  }

  /// Create issue from multiple logs (e.g. recent logs or filtered error logs)
  static Future<void> createIssueFromLogsList(
    BuildContext? context,
    List<Map<String, dynamic>> logs,
  ) async {
    if (logs.isEmpty) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(content: Text('No logs available to report.')),
        );
      }
      return;
    }

    final latestError = logs.firstWhere(
      (l) => l['level'] == 'ERROR',
      orElse: () => logs.first,
    );

    final buffer = StringBuffer();
    for (final l in logs.take(15)) {
      final timeStr = l['timestamp'] as String? ?? '';
      final level = l['level'] as String? ?? 'INFO';
      final tag = l['tag'] as String? ?? '';
      final msg = l['message'] as String? ?? '';
      buffer.writeln('[$timeStr] [$level][$tag] $msg');
    }

    await createIssueFromLog(
      context: context,
      tag: latestError['tag']?.toString() ?? 'Diagnostics',
      message: buffer.toString(),
      level: latestError['level']?.toString() ?? 'ERROR',
      timestamp: latestError['timestamp']?.toString(),
    );
  }

  /// Helper to display a snackbar with a direct "Report Issue" action button.
  static void showErrorSnackBar(
    BuildContext context,
    String message, {
    String tag = 'Error',
    Object? error,
    StackTrace? stackTrace,
  }) {
    final fullMsg = error != null ? '$message ($error)' : message;

    // Log the error to database
    DatabaseService().logAppEvent(
      tag: tag,
      message: fullMsg,
      level: 'ERROR',
    );

    ScaffoldMessenger.of(context).showReplacingSnackBar(
      SnackBar(
        content: Text(fullMsg),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Report Issue',
          onPressed: () {
            createIssueFromLog(
              context: context,
              tag: tag,
              message: fullMsg,
              level: 'ERROR',
              errorStackTrace: stackTrace?.toString(),
            );
          },
        ),
      ),
    );
  }
}
