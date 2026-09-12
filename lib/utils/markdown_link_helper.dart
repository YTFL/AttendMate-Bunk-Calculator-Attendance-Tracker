import 'package:flutter/material.dart';
import 'url_launcher_utils.dart';

class MarkdownLinkHelper {
  /// Open a markdown link (URL, mailto:, etc.)
  static Future<void> openLink(BuildContext context, String? href) async {
    if (href == null || href.trim().isEmpty) return;

    final result = await UrlLauncherUtils.launchExternalUrl(href, context: context);
    if (result == LaunchResult.failed && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link: $href')),
      );
    }
  }
}
