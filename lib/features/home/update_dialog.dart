import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/app_update_model.dart';

class UpdateDialog extends StatelessWidget {
  final AppUpdate update;
  final String currentVersion;
  final VoidCallback onInstallNow;
  final VoidCallback onRemindLater;
  final bool isDownloading;

  const UpdateDialog({
    super.key,
    required this.update,
    required this.currentVersion,
    required this.onInstallNow,
    required this.onRemindLater,
    this.isDownloading = false,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('App Update Available'),
      content: _UpdateContent(update: update, currentVersion: currentVersion),
      actions: [
        TextButton(
          onPressed: isDownloading ? null : onRemindLater,
          child: const Text('Remind Later'),
        ),
        ElevatedButton.icon(
          onPressed: isDownloading ? null : onInstallNow,
          icon: isDownloading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
                )
              : const Icon(Icons.download),
          label: Text(isDownloading ? 'Downloading...' : 'Install Now'),
        ),
      ],
    );
  }
}

class UpdateFullScreen extends StatelessWidget {
  final AppUpdate update;
  final String currentVersion;
  final VoidCallback onInstallNow;
  final VoidCallback onRemindLater;
  final bool isDownloading;

  const UpdateFullScreen({
    super.key,
    required this.update,
    required this.currentVersion,
    required this.onInstallNow,
    required this.onRemindLater,
    this.isDownloading = false,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('App Update Available'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _UpdateContent(update: update, currentVersion: currentVersion),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isDownloading ? null : onRemindLater,
                    child: const Text('Remind Later'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isDownloading ? null : onInstallNow,
                    icon: isDownloading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).primaryColor,
                              ),
                            ),
                          )
                        : const Icon(Icons.download),
                    label: Text(isDownloading ? 'Downloading...' : 'Install Now'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateContent extends StatelessWidget {
  final AppUpdate update;
  final String currentVersion;

  const _UpdateContent({required this.update, required this.currentVersion});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A new version is available',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Version',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                  Text(
                    currentVersion,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              Icon(
                Icons.arrow_forward,
                color: Colors.grey[400],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'New Version',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                  Text(
                    update.version,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'What\'s New',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[900]
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: MarkdownBody(
              data: update.changelog,
              selectable: true,
              softLineBreak: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: Theme.of(context).textTheme.bodySmall,
                code: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
