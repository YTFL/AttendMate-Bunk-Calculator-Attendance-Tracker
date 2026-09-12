import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/google_auth_service.dart';
import '../../services/live_timetable_sync_service.dart';
import '../../services/semester_share_service.dart';
import '../../utils/error_utils.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import 'semester_share_preview_dialog.dart';

class LiveTimetableSyncScreen extends StatefulWidget {
  const LiveTimetableSyncScreen({super.key});

  @override
  State<LiveTimetableSyncScreen> createState() => _LiveTimetableSyncScreenState();
}

class _LiveTimetableSyncScreenState extends State<LiveTimetableSyncScreen> {
  final LiveTimetableSyncService _syncService = LiveTimetableSyncService();
  final MethodChannel _fileChannel = const MethodChannel('com.attendmate.app/file_import');

  // Controllers for hosting
  final _hostFormKey = GlobalKey<FormState>();
  final TextEditingController _classNameController = TextEditingController();
  final TextEditingController _creatorNameController = TextEditingController();

  // Controllers for joining
  final _joinFormKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();

  bool _isLoading = false;
  String? _loadingMessage;

  @override
  void initState() {
    super.initState();
    _syncService.init();
    _syncService.addListener(_onServiceChanged);
    _initDefaultNames();
  }

  Future<void> _initDefaultNames() async {
    final displayName = await GoogleAuthService.instance.getSignedInUserDisplayName();
    if (displayName != null && displayName.isNotEmpty && mounted) {
      _creatorNameController.text = displayName;
    }
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _syncService.removeListener(_onServiceChanged);
    _classNameController.dispose();
    _creatorNameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // ==========================================
  // HOST ACTIONS
  // ==========================================

  Future<void> _handleStartHosting() async {
    if (!_hostFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Publishing timetable to Google Drive...';
    });

    try {
      await _syncService.hostLiveTimetable(
        className: _classNameController.text.trim(),
        creatorName: _creatorNameController.text.trim().isEmpty
            ? 'Class Rep'
            : _creatorNameController.text.trim(),
      );

      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(
          context,
          'Live Timetable published! Share the code with your class.',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(
          context,
          formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to host timetable'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = null;
        });
      }
    }
  }

  Future<void> _handlePushUpdate() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Pushing timetable update to class...';
    });

    try {
      final newVer = await _syncService.pushLiveUpdate();
      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(
          context,
          'Timetable update pushed successfully (v$newVer)!',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(
          context,
          formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to push update'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = null;
        });
      }
    }
  }

  Future<void> _handleStopHosting() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop Hosting Timetable?'),
        content: const Text(
          'Your classmates will no longer receive automatic live updates from your Google Drive. Your local timetable and attendance data will remain untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop Hosting'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _syncService.stopHosting(deleteFromDrive: false);
      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(context, 'Stopped hosting live timetable.');
      }
    }
  }

  // ==========================================
  // SUBSCRIBER ACTIONS
  // ==========================================

  Future<void> _handlePreviewAndJoin() async {
    final rawInput = _codeController.text.trim();
    if (rawInput.isEmpty) {
      SnackbarUtils.showErrorSnackBar(context, 'Please enter a Class Code or Drive link.');
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Fetching class timetable...';
    });

    try {
      final data = await _syncService.fetchPublicTimetable(rawInput);
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _loadingMessage = null;
      });

      // Show preview dialog
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => SemesterSharePreviewDialog(
          shareData: data,
          confirmButtonLabel: 'Subscribe & Import',
        ),
      );

      if (result == true && mounted) {
        // Register subscription with the service (import already performed by dialog)
        await _syncService.subscribeToTimetable(
          rawInput,
          data,
          context,
          mergeIntoCurrent: true,
          alreadyImported: true,
        );

        if (mounted) {
          SnackbarUtils.showSuccessSnackBar(
            context,
            'Subscribed to ${data['class_name'] ?? 'Class Timetable'}! You will receive live updates.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = null;
        });
        SnackbarUtils.showErrorSnackBar(
          context,
          formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to join timetable'),
        );
      }
    }
  }

  Future<void> _handleCheckForUpdates() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Checking Google Drive for updates...';
    });

    try {
      final updateData = await _syncService.checkForRemoteUpdates();
      if (!mounted) return;

      if (updateData != null) {
        final newVer = updateData['sync_version'] as int? ?? (_syncService.subscribedVersion + 1);
        final className = updateData['class_name'] as String? ?? _syncService.subscribedClassName ?? 'Class';

        final apply = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.system_update_rounded, color: Theme.of(ctx).colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Timetable Update Available'),
              ],
            ),
            content: Text(
              '$className has an updated schedule (Version $newVer). Would you like to update your schedule now?\n\n'
              'Note: Your personal attendance records will NOT be lost or reset.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Update Now'),
              ),
            ],
          ),
        );

        if (apply == true && mounted) {
          final ok = await _syncService.applyRemoteUpdate(updateData, context);
          if (mounted) {
            if (ok) {
              SnackbarUtils.showSuccessSnackBar(context, 'Timetable updated to Version $newVer!');
            } else {
              SnackbarUtils.showErrorSnackBar(context, 'Failed to update timetable.');
            }
          }
        }
      } else {
        SnackbarUtils.showSuccessSnackBar(
          context,
          'Your timetable is up to date (Version ${_syncService.subscribedVersion})!',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(
          context,
          formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to check updates'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = null;
        });
      }
    }
  }

  Future<void> _handleUnsubscribe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect from Live Updates?'),
        content: const Text(
          'You will stop receiving schedule updates from your Class Rep. All your current subjects and attendance history will remain safely stored on your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _syncService.unsubscribe();
      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(context, 'Disconnected from live timetable.');
      }
    }
  }

  // ==========================================
  // SHARING UTILS
  // ==========================================

  Future<void> _shareClassCode(String code, String className) async {
    final shareMessage =
        'Join our live class timetable on AttendMate!\n\n'
        'Class: $className\n'
        'Class Code: $code\n\n'
        'How to join:\n'
        '1. Open AttendMate > Semester > Live Timetable\n'
        '2. Paste the Class Code to stay in sync!';

    bool sharedNatively = false;
    try {
      sharedNatively = await _fileChannel.invokeMethod<bool>('shareText', {
        'title': 'AttendMate Class Timetable Code',
        'text': shareMessage,
      }) ?? false;
    } catch (_) {}

    if (!sharedNatively) {
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(context, 'Class Code copied to clipboard!');
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _codeController.text = data.text!.trim();
      });
      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(context, 'Pasted code from clipboard.');
      }
    }
  }

  // ==========================================
  // BUILD METHOD & UI
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rs = context.rs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Classroom Timetable & Sharing'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          ListView(
            padding: rs.insetsAll(16),
            children: [
              if (_syncService.isHost) ...[
                _buildHostActiveCard(theme, rs),
              ] else if (_syncService.isSubscribed) ...[
                _buildSubscriberActiveCard(theme, rs),
              ] else ...[
                _buildSetupOptions(theme, rs),
              ],
              SizedBox(height: rs.height(16)),
              _buildOneTimeShareCard(theme, rs),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black45,
              child: Center(
                child: Card(
                  margin: rs.insetsAll(32),
                  child: Padding(
                    padding: rs.insetsAll(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        if (_loadingMessage != null) ...[
                          SizedBox(height: rs.height(16)),
                          Text(
                            _loadingMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: rs.font(14)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleImportSharedFile() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await _fileChannel.invokeMethod<dynamic>('pickImportFile');
      if (result == null) return;
      if (result is! Map) {
        throw Exception('Invalid file picker response.');
      }

      final bytesDynamic = result['bytes'];
      List<int> bytes = [];
      if (bytesDynamic is Uint8List) {
        bytes = bytesDynamic.toList();
      } else if (bytesDynamic is List) {
        bytes = bytesDynamic.cast<int>();
      }

      if (bytes.isEmpty) {
        throw Exception('Selected file is empty.');
      }

      String content;
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        content = latin1.decode(bytes, allowInvalid: true);
      }

      if (!mounted) return;
      await SemesterShareService().processOpenedJsonContent(content, context);
    } catch (e) {
      if (!mounted) return;
      if (isUserCancellation(e)) return;
      messenger.showReplacingSnackBar(
        SnackBar(
          content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to import file')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildOneTimeShareCard(ThemeData theme, ResponsiveScale rs) {
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: isDarkMode ? 0.4 : 0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: rs.insetsAll(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: rs.insetsAll(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.share_outlined,
                  color: colorScheme.primary,
                  size: rs.scale(22),
                ),
              ),
              SizedBox(width: rs.width(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'One-Time Semester Share',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: rs.font(16),
                        color: colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: rs.height(2)),
                    Text(
                      'Export or import semester files without cloud sync',
                      style: TextStyle(
                        fontSize: rs.font(12),
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(12)),
          Text(
            'Share your semester dates and schedule directly with friends via file or messaging app. Personal attendance records are never included.',
            style: TextStyle(
              fontSize: rs.font(12.5),
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
              height: 1.4,
            ),
          ),
          SizedBox(height: rs.height(16)),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => SemesterShareService().shareSemesterWithFriend(context),
                  icon: const Icon(Icons.share_rounded, size: 17),
                  label: const Text('Share File'),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: rs.height(11)),
                  ),
                ),
              ),
              SizedBox(width: rs.width(10)),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _handleImportSharedFile,
                  icon: const Icon(Icons.file_open_outlined, size: 17),
                  label: const Text('Import File'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: rs.height(11)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // HOST VIEW
  // ==========================================

  Widget _buildHostActiveCard(ThemeData theme, ResponsiveScale rs) {
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;
    final dateFormat = DateFormat('MMM d, y • h:mm a');
    final lastPushedText = _syncService.hostedLastPushedAt != null
        ? dateFormat.format(_syncService.hostedLastPushedAt!)
        : 'Just now';

    final fileId = _syncService.hostedFileId ?? '';

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.green.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: rs.insetsAll(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: rs.width(10),
                  vertical: rs.height(5),
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: rs.width(6)),
                    Text(
                      'Hosting Live',
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: rs.font(12),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: rs.width(10),
                  vertical: rs.height(4),
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'v${_syncService.hostedVersion}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: rs.font(12),
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(14)),
          Text(
            _syncService.hostedClassName ?? 'Class Timetable',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: rs.font(19),
              color: colorScheme.onSurface,
            ),
          ),
          SizedBox(height: rs.height(4)),
          Row(
            children: [
              Icon(Icons.cloud_done_outlined, size: 14, color: colorScheme.outline),
              SizedBox(width: rs.width(6)),
              Text(
                'Synced: $lastPushedText',
                style: TextStyle(
                  fontSize: rs.font(12),
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(16)),
          const Divider(),
          SizedBox(height: rs.height(10)),
          Text(
            'Class Code (Share with classmates)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: rs.font(13),
              color: colorScheme.onSurface,
            ),
          ),
          SizedBox(height: rs.height(8)),
          Container(
            padding: rs.insetsAll(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    fileId,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: rs.font(12.5),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: 'Copy Code',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: fileId));
                    SnackbarUtils.showSuccessSnackBar(context, 'Class Code copied to clipboard!');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded, size: 18),
                  tooltip: 'Share with Class',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _shareClassCode(fileId, _syncService.hostedClassName ?? 'Class'),
                ),
              ],
            ),
          ),
          SizedBox(height: rs.height(16)),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _handlePushUpdate,
              icon: const Icon(Icons.cloud_upload_rounded, size: 18),
              label: const Text('Push Changes to Class'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(vertical: rs.height(12)),
              ),
            ),
          ),
          SizedBox(height: rs.height(6)),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _handleStopHosting,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.error,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Stop Live Hosting'),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SUBSCRIBER VIEW
  // ==========================================

  Widget _buildSubscriberActiveCard(ThemeData theme, ResponsiveScale rs) {
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;
    final dateFormat = DateFormat('MMM d, y • h:mm a');
    final lastSyncText = _syncService.subscribedLastSyncedAt != null
        ? dateFormat.format(_syncService.subscribedLastSyncedAt!)
        : 'Never';

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: rs.insetsAll(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: rs.width(10),
                  vertical: rs.height(5),
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync_rounded, color: colorScheme.primary, size: rs.scale(14)),
                    SizedBox(width: rs.width(6)),
                    Text(
                      'Subscribed',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: rs.font(12),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: rs.width(10),
                  vertical: rs.height(4),
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'v${_syncService.subscribedVersion}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: rs.font(12),
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(14)),
          Text(
            _syncService.subscribedClassName ?? 'Class Timetable',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: rs.font(19),
              color: colorScheme.onSurface,
            ),
          ),
          SizedBox(height: rs.height(4)),
          Text(
            'Managed by: ${_syncService.subscribedCreatorName ?? 'Class Rep'}',
            style: TextStyle(
              fontSize: rs.font(13),
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: rs.height(2)),
          Row(
            children: [
              Icon(Icons.history_rounded, size: 14, color: colorScheme.outline),
              SizedBox(width: rs.width(6)),
              Text(
                'Last checked: $lastSyncText',
                style: TextStyle(
                  fontSize: rs.font(12),
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(14)),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Auto-check on app open',
              style: TextStyle(fontSize: rs.font(13.5), fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Notifies you automatically when your Class Rep updates the schedule',
              style: TextStyle(fontSize: rs.font(11.5), color: colorScheme.onSurfaceVariant),
            ),
            value: _syncService.autoCheckEnabled,
            onChanged: (val) => _syncService.setAutoCheckEnabled(val),
          ),
          SizedBox(height: rs.height(10)),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _handleCheckForUpdates,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Check for Updates Now'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(vertical: rs.height(12)),
              ),
            ),
          ),
          SizedBox(height: rs.height(6)),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _handleUnsubscribe,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.error,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.link_off_rounded, size: 16),
              label: const Text('Disconnect from Live Updates'),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SETUP OPTIONS (UNCONNECTED)
  // ==========================================

  Widget _buildSetupOptions(ThemeData theme, ResponsiveScale rs) {
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // JOIN CARD (Classmate)
        Container(
          decoration: BoxDecoration(
            color: isDarkMode ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: isDarkMode ? 0.4 : 0.6),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: rs.insetsAll(18),
          child: Form(
            key: _joinFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: rs.insetsAll(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.group_add_rounded, color: Colors.blue, size: 22),
                    ),
                    SizedBox(width: rs.width(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Join Class Timetable',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: rs.font(16),
                              color: colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: rs.height(2)),
                          Text(
                            'No Google Sign-In required for classmates',
                            style: TextStyle(
                              fontSize: rs.font(12),
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: rs.height(16)),
                TextFormField(
                  controller: _codeController,
                  decoration: InputDecoration(
                    labelText: 'Class Code or Google Drive Link',
                    hintText: 'Paste code shared by your Class Rep',
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste_rounded, size: 20),
                      tooltip: 'Paste',
                      onPressed: _pasteFromClipboard,
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
                SizedBox(height: rs.height(14)),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _handlePreviewAndJoin,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Preview & Subscribe'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: EdgeInsets.symmetric(vertical: rs.height(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: rs.height(16)),

        // HOST CARD (Class Rep)
        Container(
          decoration: BoxDecoration(
            color: isDarkMode ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: isDarkMode ? 0.4 : 0.6),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: rs.insetsAll(18),
          child: Form(
            key: _hostFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: rs.insetsAll(10),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.campaign_rounded, color: Colors.purple, size: 22),
                    ),
                    SizedBox(width: rs.width(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Host Live Timetable',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: rs.font(16),
                              color: colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: rs.height(2)),
                          Text(
                            'For Class Representatives / Timetable Managers',
                            style: TextStyle(
                              fontSize: rs.font(12),
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: rs.height(16)),
                TextFormField(
                  controller: _classNameController,
                  decoration: InputDecoration(
                    labelText: 'Class / Branch / Section Name',
                    hintText: 'e.g., CSE 3rd Year - Section A',
                    prefixIcon: const Icon(Icons.school_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a class name' : null,
                ),
                SizedBox(height: rs.height(12)),
                TextFormField(
                  controller: _creatorNameController,
                  decoration: InputDecoration(
                    labelText: 'Your Name (Class Rep)',
                    hintText: 'e.g., Alex (Class Rep)',
                    prefixIcon: const Icon(Icons.person_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
                SizedBox(height: rs.height(14)),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: _handleStartHosting,
                    icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                    label: const Text('Host Timetable on Google Drive'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: EdgeInsets.symmetric(vertical: rs.height(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
