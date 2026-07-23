import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../services/database_service.dart';

class DiagnosticsLogScreen extends StatefulWidget {
  const DiagnosticsLogScreen({super.key});

  @override
  State<DiagnosticsLogScreen> createState() => _DiagnosticsLogScreenState();
}

class _DiagnosticsLogScreenState extends State<DiagnosticsLogScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String _selectedFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _refreshLogs();
  }

  Future<void> _refreshLogs() async {
    setState(() => _isLoading = true);
    final logs = await _databaseService.loadAppLogs();
    setState(() {
      _logs = logs;
      _isLoading = false;
    });
  }

  Future<void> _clearLogs() async {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Logs'),
        content: const Text('Are you sure you want to delete all diagnostic logs?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _databaseService.clearAppLogs();
      await _refreshLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logs cleared successfully.')),
        );
      }
    }
  }

  Future<void> _copyLogsToClipboard() async {
    if (_logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logs to copy.')),
      );
      return;
    }

    final buffer = StringBuffer();
    for (final log in _logs) {
      final timeStr = log['timestamp'] as String;
      final level = log['level'] as String;
      final tag = log['tag'] as String;
      final message = log['message'] as String;
      buffer.writeln('[$timeStr] [$level][$tag] $message');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logs copied to clipboard!')),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredLogs {
    if (_selectedFilter == 'ALL') return _logs;
    return _logs.where((l) => l['level'] == _selectedFilter).toList();
  }

  Color _getLevelColor(String level, ColorScheme colors) {
    switch (level) {
      case 'ERROR':
        return colors.error;
      case 'WARNING':
        return Colors.amber.shade700;
      case 'INFO':
      default:
        return Colors.green.shade600;
    }
  }

  IconData _getLevelIcon(String level) {
    switch (level) {
      case 'ERROR':
        return Icons.error_outline_rounded;
      case 'WARNING':
        return Icons.warning_amber_rounded;
      case 'INFO':
      default:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filtered = _filteredLogs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy all to clipboard',
            onPressed: _copyLogsToClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear logs',
            onPressed: _clearLogs,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _refreshLogs,
        tooltip: 'Refresh logs',
        child: const Icon(Icons.refresh_rounded),
      ),
      body: Column(
        children: [
          // Filter Row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('ALL', 'All Logs'),
                  const SizedBox(width: 8),
                  _buildFilterChip('INFO', 'Info'),
                  const SizedBox(width: 8),
                  _buildFilterChip('WARNING', 'Warnings'),
                  const SizedBox(width: 8),
                  _buildFilterChip('ERROR', 'Errors'),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // Logs List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 64,
                              color: colorScheme.onSurface.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No logs found',
                              style: TextStyle(
                                fontSize: 16,
                                color: colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: filtered.length,
                        itemBuilder: (ctx, index) {
                          final log = filtered[index];
                          final timestamp = DateTime.tryParse(log['timestamp'] as String) ?? DateTime.now();
                          final timeStr = DateFormat('HH:mm:ss.SSS').format(timestamp);
                          final dateStr = DateFormat('MMM d').format(timestamp);
                          final level = log['level'] as String;
                          final tag = log['tag'] as String;
                          final message = log['message'] as String;
                          final color = _getLevelColor(level, colorScheme);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                              ),
                            ),
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _getLevelIcon(level),
                                        size: 16,
                                        color: color,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        level,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: color,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          tag,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onPrimaryContainer,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '$dateStr, $timeStr',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    message,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedFilter == value;

    return FilterChip(
      selected: isSelected,
      label: Text(label),
      onSelected: (_) {
        setState(() {
          _selectedFilter = value;
        });
      },
      selectedColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
