import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/backup_service.dart';
import '../../utils/error_utils.dart';
import '../../utils/snackbar_utils.dart';

class SemesterBackupScreen extends StatefulWidget {
  const SemesterBackupScreen({super.key});

  @override
  State<SemesterBackupScreen> createState() => _SemesterBackupScreenState();
}

class _SemesterBackupScreenState extends State<SemesterBackupScreen> {
  static const MethodChannel _fileImportChannel = MethodChannel('com.attendmate.app/file_import');
  final BackupService _backupService = BackupService();

  String? _backupDirectoryPath;
  List<BackupFileInfo> _backups = [];
  bool _isBackupEnabled = true;
  bool _isLoading = true;
  bool _isCreatingBackup = false;
  bool _isRestoring = false;

  @override
  void initState() {
    super.initState();
    _loadBackupData();
  }

  Future<void> _loadBackupData() async {
    setState(() {
      _isLoading = true;
    });

    final dirPath = await _backupService.getBackupDirectoryPath();
    final backupFiles = await _backupService.getBackupFiles();
    final enabled = await _backupService.isBackupEnabled();

    if (!mounted) return;
    setState(() {
      _backupDirectoryPath = dirPath;
      _backups = backupFiles;
      _isBackupEnabled = enabled;
      _isLoading = false;
    });
  }

  Future<void> _toggleBackupEnabled(bool value) async {
    setState(() {
      _isBackupEnabled = value;
    });
    await _backupService.setBackupEnabled(value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showReplacingSnackBar(
      SnackBar(
        content: Text(value ? 'Automatic semester backups enabled.' : 'Automatic backups turned off. Existing backups were kept intact.'),
        backgroundColor: value ? Colors.green.shade700 : Colors.orange.shade800,
      ),
    );
  }

  Future<void> _pickBackupFolder() async {
    try {
      final selectedDirectory = await _fileImportChannel.invokeMethod<String>('pickDirectory');

      if (selectedDirectory != null && selectedDirectory.trim().isNotEmpty) {
        await _backupService.setBackupDirectoryPath(selectedDirectory.trim());
        if (!mounted) return;
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(content: Text('Backup location updated successfully.')),
        );
        await _loadBackupData();
      }
    } catch (e) {
      if (!mounted) return;
      if (isUserCancellation(e)) return;
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Could not set directory')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _createBackupNow() async {
    if (_isCreatingBackup) return;

    if (_backupDirectoryPath == null) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(content: Text('Please select a backup storage folder first.')),
      );
      await _pickBackupFolder();
      if (_backupDirectoryPath == null) return;
    }

    setState(() {
      _isCreatingBackup = true;
    });

    try {
      final file = await _backupService.createBackup(
        showNotification: false,
        triggerReason: 'Manual trigger',
        force: true,
      );

      if (!mounted) return;
      setState(() {
        _isCreatingBackup = false;
      });

      if (file != null) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(content: Text('Backup created successfully.')),
        );
        await _loadBackupData();
      } else {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(content: Text('Failed to create backup.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreatingBackup = false;
      });
      if (isUserCancellation(e)) return;
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to create backup')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _importBackupFile() async {
    try {
      final result = await _fileImportChannel.invokeMethod<dynamic>('pickImportFile');
      if (result == null) return;
      if (result is! Map) {
        throw Exception('Invalid file picker response.');
      }

      final bytesRaw = result['bytes'];
      List<int> bytes = [];
      if (bytesRaw is List) {
        bytes = bytesRaw.cast<int>();
      } else if (bytesRaw is Uint8List) {
        bytes = bytesRaw.toList();
      }

      if (bytes.isEmpty) {
        throw Exception('Selected backup file is empty or unreadable.');
      }

      String content;
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        throw Exception('Unable to read file contents. Please ensure it is a valid text/JSON backup file.');
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(content);
      } catch (_) {
        throw Exception('The selected file is not a valid JSON file.');
      }

      if (decoded is! Map<String, dynamic>) {
        throw Exception('The selected file does not contain a valid AttendMate backup structure.');
      }

      final data = decoded;
      if (data['app'] != 'AttendMate' || data['database'] == null || data['database'] is! Map) {
        throw Exception('The selected file is not a valid AttendMate backup file.');
      }

      if (!mounted) return;
      await _confirmAndRestoreMap(data, title: 'Import & Restore Backup');
    } catch (e) {
      if (!mounted) return;
      if (isUserCancellation(e)) return;

      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to import backup')),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _confirmAndRestoreFile(BackupFileInfo info) async {
    if (info.rawData != null) {
      await _confirmAndRestoreMap(info.rawData!, title: 'Restore Backup?');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Theme.of(dialogCtx).colorScheme.error),
            const SizedBox(width: 8),
            const Text('Restore Backup?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Restoring this file will replace your current attendance data and settings with:',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(dialogCtx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${info.subjectCount} Subjects • ${info.attendanceCount} Attendance Records',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Restore Data'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isRestoring = true;
    });

    try {
      await _backupService.restoreBackupFromFile(info.file, context: context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(content: Text('App data and settings restored successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      if (isUserCancellation(e)) return;
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to restore backup')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
        await _loadBackupData();
      }
    }
  }

  Future<void> _confirmAndRestoreMap(Map<String, dynamic> data, {required String title}) async {
    if (data['app'] != 'AttendMate' || data['database'] == null || data['database'] is! Map) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: const Text('The selected file is not a valid AttendMate backup file.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final dbMap = data['database'] as Map<String, dynamic>? ?? {};
    final subjects = dbMap['subjects'] as List? ?? [];
    final attendance = dbMap['attendance'] as List? ?? [];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Theme.of(dialogCtx).colorScheme.error),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Restoring this file will replace your current attendance data and settings with:',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(dialogCtx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${subjects.length} Subjects • ${attendance.length} Attendance Records',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            const Text('This action cannot be undone.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Restore Data'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isRestoring = true;
    });

    try {
      await _backupService.restoreBackupFromData(data, context: context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(content: Text('App data and settings restored successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      if (isUserCancellation(e)) return;
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to restore backup')),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
        await _loadBackupData();
      }
    }
  }

  Future<void> _deleteBackup(BackupFileInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Backup?'),
        content: Text('Are you sure you want to delete "${info.fileName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('Delete', style: TextStyle(color: Theme.of(dialogCtx).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _backupService.deleteBackupFile(info.fileName);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(content: Text('Backup file deleted.')),
        );
        await _loadBackupData();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to delete backup')),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  String _formatUserReadablePath(String? rawPath) {
    if (rawPath == null || rawPath.trim().isEmpty) {
      return 'Not specified (Select a location below)';
    }

    final decoded = Uri.decodeFull(rawPath.trim());

    if (decoded.startsWith('content://')) {
      if (decoded.contains('/tree/')) {
        final treePart = decoded.split('/tree/').last;
        final docId = treePart.split('/document/').first;
        final split = docId.split(':');
        if (split.length >= 2) {
          final volume = split[0];
          final relativePath = split.sublist(1).join(':').replaceAll('/', ' / ');
          final cleanRel = relativePath.trim().isEmpty ? '' : ' / $relativePath';
          if (volume.toLowerCase() == 'primary') {
            return 'Internal Storage$cleanRel';
          } else {
            return 'SD Card ($volume)$cleanRel';
          }
        }
      }
      return 'Custom Storage Folder';
    }

    if (decoded.startsWith('/storage/emulated/0')) {
      final relativePath = decoded.replaceFirst('/storage/emulated/0', '').replaceAll('/', ' / ');
      return 'Internal Storage$relativePath';
    }

    return decoded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Semester Backup'),
      ),
      body: _isLoading || _isRestoring
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_isRestoring ? 'Restoring complete data & state...' : 'Loading backups...'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Automatic Backups Toggle Box
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    value: _isBackupEnabled,
                    onChanged: _toggleBackupEnabled,
                    secondary: Icon(
                      _isBackupEnabled ? Icons.backup_rounded : Icons.backup_table_outlined,
                      color: _isBackupEnabled ? colorScheme.primary : colorScheme.outline,
                    ),
                    title: const Text(
                      'Automatic Backups',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      _isBackupEnabled ? 'Enabled' : 'Disabled',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _isBackupEnabled ? colorScheme.primary : colorScheme.outline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Location Selection Box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.folder_special_outlined,
                            color: _backupDirectoryPath == null ? colorScheme.error : colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Backup Storage Folder',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _pickBackupFolder,
                            icon: const Icon(Icons.folder_open, size: 16),
                            label: Text(_backupDirectoryPath == null ? 'Select' : 'Change'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatUserReadablePath(_backupDirectoryPath),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: _backupDirectoryPath == null ? FontWeight.bold : FontWeight.w600,
                          color: _backupDirectoryPath == null ? colorScheme.error : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Manual Actions Row
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isCreatingBackup ? null : _createBackupNow,
                        icon: _isCreatingBackup
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.backup_outlined),
                        label: Text(_isCreatingBackup ? 'Creating...' : 'Create Backup'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _importBackupFile,
                        icon: const Icon(Icons.file_open_outlined),
                        label: const Text('Import File'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Section Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'AVAILABLE BACKUPS (${_backups.length}/3)',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        'Auto 3 Rolling Limit',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                if (_backups.isEmpty)
                  Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(top: 8),
                    color: colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                      child: Column(
                        children: [
                          Icon(Icons.cloud_off_outlined, size: 48, color: colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            'No Backups Found',
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap "Create Backup" above to save your current attendance, subjects, and settings.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._backups.map((info) => _buildBackupCard(context, info)),
              ],
            ),
    );
  }

  Widget _buildBackupCard(BuildContext context, BackupFileInfo info) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sizeKb = (info.fileSizeBytes / 1024).toStringAsFixed(1);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_outlined, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMM d, y • h:mm a').format(info.createdAt),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: colorScheme.error,
                  tooltip: 'Delete Backup',
                  onPressed: () => _deleteBackup(info),
                ),
              ],
            ),
            const Divider(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildChip(context, Icons.book_outlined, '${info.subjectCount} Subjects'),
                _buildChip(context, Icons.check_circle_outline, '${info.attendanceCount} Records'),
                _buildChip(context, Icons.data_usage_outlined, '$sizeKb KB'),
              ],
            ),
            if (info.semesterRange != null) ...[
              const SizedBox(height: 8),
              Text(
                'Semester: ${info.semesterRange}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => _confirmAndRestoreFile(info),
                icon: const Icon(Icons.settings_backup_restore_outlined, size: 18),
                label: const Text('Restore This Backup'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, IconData icon, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
