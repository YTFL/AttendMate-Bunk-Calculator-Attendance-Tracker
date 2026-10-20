import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/google_auth_service.dart';
import '../../services/live_timetable_sync_service.dart';
import '../../services/semester_share_service.dart';
import '../../utils/error_utils.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/day_cycle_background.dart';
import '../../widgets/glass_dialog.dart';
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

        final apply = await showGlassDialog<bool>(
          context: context,
          builder: (ctx) => GlassDialog(
            icon: Icon(Icons.system_update_rounded, color: Theme.of(ctx).colorScheme.primary, size: 28),
            title: const Text('Timetable Update Available'),
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

    return DayCycleBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'Classroom Timetable & Sharing',
            style: GoogleFonts.roboto(
              fontWeight: FontWeight.w700,
              fontSize: rs.font(17),
            ),
          ),
          centerTitle: false,
        ),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(
              rs.scale(16),
              rs.scale(12),
              rs.scale(16),
              rs.scale(140),
            ),
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

  Widget _buildGlassCard({
    required Widget child,
    required bool isDarkMode,
    EdgeInsetsGeometry? padding,
    Color? borderColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding ?? const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF0F0F16).withValues(alpha: 0.60)
                : Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor ??
                  (isDarkMode
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.black.withValues(alpha: 0.08)),
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildOneTimeShareCard(ThemeData theme, ResponsiveScale rs) {
    final isDarkMode = theme.brightness == Brightness.dark;
    final cardBorder = isDarkMode
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.08);
    final badgeBg = isDarkMode
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return _buildGlassCard(
      isDarkMode: isDarkMode,
      padding: rs.insetsAll(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: rs.insetsAll(10),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cardBorder, width: 0.8),
                ),
                child: Icon(
                  Icons.share_outlined,
                  color: isDarkMode ? Colors.white : Colors.black,
                  size: rs.scale(20),
                ),
              ),
              SizedBox(width: rs.width(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'One-Time Semester Share',
                      style: GoogleFonts.roboto(
                        fontWeight: FontWeight.w700,
                        fontSize: rs.font(15.5),
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    SizedBox(height: rs.height(2)),
                    Text(
                      'Export or import semester files without cloud sync',
                      style: TextStyle(
                        fontSize: rs.font(12),
                        color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
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
              color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
              height: 1.4,
            ),
          ),
          SizedBox(height: rs.height(16)),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => SemesterShareService().shareSemesterWithFriend(context),
                  icon: Icon(
                    Icons.share_rounded,
                    size: 16,
                    color: isDarkMode ? Colors.black : Colors.white,
                  ),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Share File',
                      style: GoogleFonts.roboto(
                        fontWeight: FontWeight.w700,
                        fontSize: rs.font(12.5),
                        color: isDarkMode ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode ? Colors.white : Colors.black,
                    foregroundColor: isDarkMode ? Colors.black : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: rs.height(12)),
                  ),
                ),
              ),
              SizedBox(width: rs.width(10)),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _handleImportSharedFile,
                  icon: Icon(
                    Icons.file_open_outlined,
                    size: 16,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Import File',
                      style: GoogleFonts.roboto(
                        fontWeight: FontWeight.w600,
                        fontSize: rs.font(12.5),
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: cardBorder, width: 0.8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: rs.height(12)),
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

    return _buildGlassCard(
      isDarkMode: isDarkMode,
      borderColor: Colors.green.withValues(alpha: 0.45),
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

    return _buildGlassCard(
      isDarkMode: isDarkMode,
      borderColor: colorScheme.primary.withValues(alpha: 0.45),
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
    final isDarkMode = theme.brightness == Brightness.dark;
    final cardBorder = isDarkMode
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.08);
    final badgeBg = isDarkMode
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final inputBg = isDarkMode
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);

    return Column(
      children: [
        // JOIN CARD (Classmate)
        _buildGlassCard(
          isDarkMode: isDarkMode,
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
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorder, width: 0.8),
                      ),
                      child: Icon(
                        Icons.group_add_outlined,
                        color: isDarkMode ? Colors.white : Colors.black,
                        size: 20,
                      ),
                    ),
                    SizedBox(width: rs.width(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Join Class Timetable',
                            style: GoogleFonts.roboto(
                              fontWeight: FontWeight.w700,
                              fontSize: rs.font(15.5),
                              color: isDarkMode ? Colors.white : Colors.black,
                            ),
                          ),
                          SizedBox(height: rs.height(2)),
                          Text(
                            'No Google Sign-In required for classmates',
                            style: TextStyle(
                              fontSize: rs.font(12),
                              color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
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
                  style: GoogleFonts.roboto(
                    fontSize: rs.font(13.5),
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Class Code or Google Drive Link',
                    hintText: 'Paste code shared by your Class Rep',
                    labelStyle: TextStyle(
                      color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                      fontSize: 13,
                    ),
                    hintStyle: TextStyle(
                      color: isDarkMode ? Colors.white24 : Colors.black26,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.key_rounded,
                      size: 18,
                      color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        Icons.paste_rounded,
                        size: 18,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                      tooltip: 'Paste',
                      onPressed: _pasteFromClipboard,
                    ),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cardBorder, width: 0.8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: isDarkMode ? Colors.white : Colors.black,
                        width: 1.2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                SizedBox(height: rs.height(14)),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handlePreviewAndJoin,
                    icon: Icon(
                      Icons.download_rounded,
                      size: 16,
                      color: isDarkMode ? Colors.black : Colors.white,
                    ),
                    label: Text(
                      'Preview & Subscribe',
                      style: GoogleFonts.roboto(
                        fontWeight: FontWeight.w700,
                        fontSize: rs.font(13),
                        color: isDarkMode ? Colors.black : Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDarkMode ? Colors.white : Colors.black,
                      foregroundColor: isDarkMode ? Colors.black : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: EdgeInsets.symmetric(vertical: rs.height(13)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: rs.height(16)),

        // HOST CARD (Class Rep)
        _buildGlassCard(
          isDarkMode: isDarkMode,
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
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorder, width: 0.8),
                      ),
                      child: Icon(
                        Icons.campaign_outlined,
                        color: isDarkMode ? Colors.white : Colors.black,
                        size: 20,
                      ),
                    ),
                    SizedBox(width: rs.width(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Host Live Timetable',
                            style: GoogleFonts.roboto(
                              fontWeight: FontWeight.w700,
                              fontSize: rs.font(15.5),
                              color: isDarkMode ? Colors.white : Colors.black,
                            ),
                          ),
                          SizedBox(height: rs.height(2)),
                          Text(
                            'For Class Representatives / Timetable Managers',
                            style: TextStyle(
                              fontSize: rs.font(12),
                              color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
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
                  style: GoogleFonts.roboto(
                    fontSize: rs.font(13.5),
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Class / Branch / Section Name',
                    hintText: 'e.g., CSE 3rd Year - Section A',
                    labelStyle: TextStyle(
                      color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                      fontSize: 13,
                    ),
                    hintStyle: TextStyle(
                      color: isDarkMode ? Colors.white24 : Colors.black26,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.school_outlined,
                      size: 18,
                      color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                    ),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cardBorder, width: 0.8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: isDarkMode ? Colors.white : Colors.black,
                        width: 1.2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a class name' : null,
                ),
                SizedBox(height: rs.height(12)),
                TextFormField(
                  controller: _creatorNameController,
                  style: GoogleFonts.roboto(
                    fontSize: rs.font(13.5),
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Your Name (Class Rep)',
                    hintText: 'e.g., Alex (Class Rep)',
                    labelStyle: TextStyle(
                      color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                      fontSize: 13,
                    ),
                    hintStyle: TextStyle(
                      color: isDarkMode ? Colors.white24 : Colors.black26,
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                    ),
                    filled: true,
                    fillColor: inputBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: cardBorder, width: 0.8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: isDarkMode ? Colors.white : Colors.black,
                        width: 1.2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                SizedBox(height: rs.height(14)),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _handleStartHosting,
                    icon: Icon(
                      Icons.cloud_upload_outlined,
                      size: 17,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Host Timetable on Google Drive',
                        style: GoogleFonts.roboto(
                          fontWeight: FontWeight.w700,
                          fontSize: rs.font(13),
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: cardBorder, width: 0.8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: EdgeInsets.symmetric(vertical: rs.height(13)),
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
