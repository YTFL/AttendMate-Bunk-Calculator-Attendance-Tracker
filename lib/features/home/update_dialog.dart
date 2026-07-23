import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../models/app_update_model.dart';

class UpdateFullScreen extends StatelessWidget {
  final AppUpdate update;
  final String currentVersion;
  final VoidCallback onInstallNow;
  final VoidCallback onRemindLater;
  final bool isDownloading;
  final double downloadProgress;

  const UpdateFullScreen({
    super.key,
    required this.update,
    required this.currentVersion,
    required this.onInstallNow,
    required this.onRemindLater,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
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
            child: isDownloading
                ? _buildProgressBar(context, downloadProgress)
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onRemindLater,
                          child: const Text('Remind Later'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onInstallNow,
                          icon: const Icon(Icons.download),
                          label: const Text('Install Now'),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, double progress) {
    final percent = (progress * 100).clamp(0, 100).toInt();
    final textString = progress > 0 ? 'Downloading... $percent%' : 'Downloading...';
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColor = isDark ? primaryColor.withValues(alpha: 0.4) : primaryColor;
    const progressColor = Colors.white;
    const textOnBackground = Colors.white;
    const textOnProgress = Colors.black87;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final filledWidth = totalWidth * progress.clamp(0.0, 1.0);

          return Stack(
            children: [
              // Background Layer Text
              SizedBox(
                width: totalWidth,
                height: 48,
                child: Center(
                  child: Text(
                    textString,
                    style: const TextStyle(
                      color: textOnBackground,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              // White progress fill layer with dark text clipped to filledWidth
              if (filledWidth > 0)
                ClipRect(
                  clipper: _ProgressClipper(filledWidth),
                  child: Container(
                    width: totalWidth,
                    height: 48,
                    decoration: BoxDecoration(
                      color: progressColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        textString,
                        style: const TextStyle(
                          color: textOnProgress,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProgressClipper extends CustomClipper<Rect> {
  final double width;
  _ProgressClipper(this.width);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(0, 0, width, size.height);
  }

  @override
  bool shouldReclip(_ProgressClipper oldClipper) {
    return oldClipper.width != width;
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
