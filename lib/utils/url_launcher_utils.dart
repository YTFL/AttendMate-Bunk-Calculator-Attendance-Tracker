import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show navigatorKey;

enum LaunchResult {
  opened,
  cancelled,
  failed;

  bool get isOpened => this == LaunchResult.opened;
  bool get isCancelled => this == LaunchResult.cancelled;
  bool get isFailed => this == LaunchResult.failed;
}

class UrlLauncherUtils {
  /// Directly launches an external URI without confirmation popup.
  static Future<bool> launchDirect(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return false;

    Uri? uri;
    if (trimmed.startsWith('mailto:')) {
      uri = Uri.tryParse(trimmed);
    } else if (trimmed.contains('@') && !trimmed.startsWith('http')) {
      uri = Uri.tryParse('mailto:$trimmed');
    } else if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      uri = Uri.tryParse(trimmed);
    } else {
      uri = Uri.tryParse('https://$trimmed');
    }

    if (uri == null) return false;

    try {
      final isMail = uri.scheme == 'mailto';
      final launched = await launchUrl(
        uri,
        mode: isMail ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
      if (launched) return true;

      // Fallback
      return await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      try {
        return await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {
        return false;
      }
    }
  }

  /// Prompts a confirmation popup before opening any external URL.
  /// The popup states "Redirecting to external URL", displays the exact URL,
  /// and provides "Back" (cancels and stays) and "Continue" (opens the URL) buttons.
  static Future<LaunchResult> launchExternalUrl(
    String url, {
    BuildContext? context,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return LaunchResult.failed;

    final targetContext = context ?? navigatorKey.currentContext;
    if (targetContext == null || !targetContext.mounted) {
      final launched = await launchDirect(trimmed);
      return launched ? LaunchResult.opened : LaunchResult.failed;
    }

    final theme = Theme.of(targetContext);
    final isDarkMode = theme.brightness == Brightness.dark;

    final displayUrl = trimmed.length > 250
        ? '${trimmed.substring(0, 250)}...'
        : trimmed;

    final bool? shouldContinue = await showDialog<bool>(
      context: targetContext,
      barrierDismissible: true,
      barrierColor: isDarkMode ? Colors.white.withAlpha(25) : null,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.open_in_new_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Redirecting to external URL',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are about to leave AttendMate and open an external web page:',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                      : theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.18),
                    width: 1,
                  ),
                ),
                child: SelectableText(
                  displayUrl,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Back'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (shouldContinue == true) {
      final launched = await launchDirect(trimmed);
      return launched ? LaunchResult.opened : LaunchResult.failed;
    }

    return LaunchResult.cancelled;
  }
}