import 'package:flutter/material.dart';

class SyncProgressDialog extends StatefulWidget {
  final String title;
  final Future<void> Function(void Function(double progress, String status) onProgress) action;

  const SyncProgressDialog({
    super.key,
    required this.title,
    required this.action,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required Future<void> Function(void Function(double progress, String status) onProgress) action,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SyncProgressDialog(
        title: title,
        action: action,
      ),
    );
  }

  @override
  State<SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends State<SyncProgressDialog> {
  double _progress = 0.0;
  String _status = 'Starting sync...';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _executeSync());
  }

  Future<void> _executeSync() async {
    try {
      await widget.action((progress, status) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _status = status;
          });
        }
      });
      if (mounted) {
        setState(() {
          _progress = 1.0;
          _status = 'Sync complete!';
        });
        await Future.delayed(const Duration(milliseconds: 350));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  Widget _buildProgressBar(BuildContext context, double progress) {
    final percent = (progress * 100).clamp(0, 100).toInt();
    final isClearing = widget.title.toLowerCase().contains('clear') ||
        widget.title.toLowerCase().contains('delet');
    final actionWord = isClearing ? 'Clearing...' : 'Syncing...';
    final textString = progress > 0 ? '$actionWord $percent%' : actionWord;

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false, // Prevents back navigation during sync!
      child: AlertDialog(
        icon: _error != null
            ? const Icon(Icons.error_outline, size: 38, color: Colors.red)
            : const Icon(Icons.sync_rounded, size: 38, color: Colors.blue),
        title: Text(
          _error != null ? 'Sync Failed' : widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 13, color: Colors.red),
                ),
              ] else ...[
                if (_status.isNotEmpty) ...[
                  Text(
                    _status,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                ],
                _buildProgressBar(context, _progress),
                const SizedBox(height: 12),
                Text(
                  'Please do not exit AttendMate while synchronization is in progress.',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (_error != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Dismiss'),
            ),
        ],
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
