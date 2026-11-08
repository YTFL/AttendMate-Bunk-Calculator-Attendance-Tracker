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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final percentage = (_progress * 100).clamp(0, 100).toInt();

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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _status,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$percentage%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress.clamp(0.0, 1.0),
                    minHeight: 8,
                  ),
                ),
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
