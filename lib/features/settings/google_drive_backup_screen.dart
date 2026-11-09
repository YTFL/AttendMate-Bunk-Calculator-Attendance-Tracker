import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_drive_backup_service.dart';
import '../../utils/snackbar_utils.dart';

class GoogleDriveBackupScreen extends StatefulWidget {
  const GoogleDriveBackupScreen({super.key});

  @override
  State<GoogleDriveBackupScreen> createState() => _GoogleDriveBackupScreenState();
}

class _GoogleDriveBackupScreenState extends State<GoogleDriveBackupScreen> {
  final _authService = GoogleAuthService.instance;
  final _driveService = GoogleDriveBackupService();

  bool _isDriveBackupEnabled = GoogleDriveBackupService.isBackupEnabledSync;
  DateTime? _lastDriveBackupTime = GoogleDriveBackupService.lastBackupTimeSync;
  DriveBackupFileInfo? _existingDriveBackup = GoogleDriveBackupService.cachedExistingBackup;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _authService.addListener(_onAuthStateChanged);
    _loadSettings();
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  void _onAuthStateChanged() {
    if (mounted) {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final driveEnabled = await _driveService.isBackupEnabled();
    final lastBackup = await _driveService.getLastBackupTime();

    if (mounted) {
      setState(() {
        _isDriveBackupEnabled = driveEnabled;
        _lastDriveBackupTime = lastBackup;
      });
    }

    final isSignedIn = await _authService.isSignedIn();
    if (isSignedIn) {
      final existingBackup = await _driveService.checkForExistingBackup();
      if (mounted) {
        setState(() {
          _existingDriveBackup = existingBackup;
        });
      }
    }
  }

  Future<void> _handleSignIn() async {
    setState(() => _isLoading = true);
    final account = await _authService.signIn();
    setState(() => _isLoading = false);

    if (account != null && mounted) {
      SnackbarUtils.showSuccessSnackBar(context, 'Signed in as ${account.email}');
      await _checkExistingCloudBackup();
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out from Google?'),
        content: const Text(
          'Logging out will disable Google Drive cloud backups until you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await _authService.signOut();
      await _driveService.setBackupEnabled(false);
      setState(() {
        _isDriveBackupEnabled = false;
        _isLoading = false;
        _existingDriveBackup = null;
      });
      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(context, 'Logged out from Google Account.');
      }
    }
  }

  Future<void> _checkExistingCloudBackup() async {
    final backup = await _driveService.checkForExistingBackup();
    setState(() => _existingDriveBackup = backup);

    if (backup != null && mounted) {
      final formattedDate = DateFormat.yMMMd().add_jm().format(backup.modifiedTime);
      final sizeKb = (backup.sizeBytes / 1024).toStringAsFixed(1);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.cloud_download_outlined, size: 40, color: Colors.blue),
          title: const Text('Cloud Backup Found'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A previous AttendMate backup was found on your Google Drive:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Date: $formattedDate', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Size: $sizeKb KB'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Would you like to restore your subjects and attendance from this backup now?',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep Local Data'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _restoreFromDrive();
              },
              child: const Text('Restore from Drive'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _restoreFromDrive() async {
    setState(() => _isLoading = true);
    final success = await _driveService.restoreLatestBackupFromDrive(context: context);
    setState(() => _isLoading = false);

    if (mounted) {
      if (success) {
        SnackbarUtils.showSuccessSnackBar(context, 'Successfully restored database from Google Drive.');
      } else {
        SnackbarUtils.showErrorSnackBar(context, 'Failed to restore backup from Google Drive.');
      }
    }
  }

  Future<void> _forceDriveBackup() async {
    setState(() => _isLoading = true);
    final success = await _driveService.uploadBackup(force: true);
    await _loadSettings();
    setState(() => _isLoading = false);

    if (mounted) {
      if (success) {
        SnackbarUtils.showSuccessSnackBar(context, 'Google Drive backup completed successfully.');
      } else {
        SnackbarUtils.showErrorSnackBar(context, 'Failed to backup database to Google Drive.');
      }
    }
  }

  Future<void> _toggleDriveBackup(bool val) async {
    setState(() => _isDriveBackupEnabled = val);
    await _driveService.setBackupEnabled(val);
    if (!mounted) return;
    if (val) {
      SnackbarUtils.showSuccessSnackBar(
        context,
        'Google Drive midnight backup enabled.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final canPop = !_isLoading;

    return PopScope(
      canPop: canPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Google Drive Backup'),
          automaticallyImplyLeading: canPop,
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // User Profile / Sign-in Card
                if (user != null) ...[
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                            child: user.photoUrl == null
                                ? Text(
                                    (user.displayName?.isNotEmpty == true
                                            ? user.displayName![0]
                                            : user.email[0])
                                        .toUpperCase(),
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.displayName ?? 'Google User',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  user.email,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout_rounded, color: Colors.red),
                            tooltip: 'Log Out',
                            onPressed: _isLoading ? null : _handleSignOut,
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Connect Google Drive',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sign in with your Google account to back up your attendance, subjects, and timetable securely to Google Drive.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _isLoading ? null : _handleSignIn,
                            icon: const Icon(Icons.login),
                            label: const Text('Sign in with Google'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Backup Controls Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.cloud_sync_outlined, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Automatic Cloud Backup',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Daily midnight backup to Google Drive',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: user != null && _isDriveBackupEnabled,
                              onChanged: (user == null || _isLoading) ? null : _toggleDriveBackup,
                            ),
                          ],
                        ),
                        if (_lastDriveBackupTime != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Last Cloud Backup: ${DateFormat.yMMMd().add_jm().format(_lastDriveBackupTime!)}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (user != null) ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isLoading ? null : _forceDriveBackup,
                                  icon: const Icon(Icons.backup_outlined, size: 16),
                                  label: const Text('Backup to Drive Now', maxLines: 1, overflow: TextOverflow.ellipsis),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                  ),
                                ),
                              ),
                              if (_existingDriveBackup != null) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _isLoading
                                        ? null
                                        : () {
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text('Restore from Cloud?'),
                                                content: Text(
                                                  'This will overwrite your current local attendance data with the backup from ${DateFormat.yMMMd().add_jm().format(_existingDriveBackup!.modifiedTime)}.',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () {
                                                      Navigator.pop(ctx);
                                                      _restoreFromDrive();
                                                    },
                                                    child: const Text('Restore Backup'),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                    icon: const Icon(Icons.cloud_download_outlined, size: 16),
                                    label: const Text('Restore Backup', maxLines: 1, overflow: TextOverflow.ellipsis),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ] else
                          const Text(
                            'Sign in with Google to enable Drive cloud backups.',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Privacy & Boundaries Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, size: 18, color: Colors.green),
                            SizedBox(width: 8),
                            Text(
                              'Privacy & Cloud Storage Bounds',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• AttendMate stores strictly one file (attendmate_cloud_backup.json) and never reads, writes, or modifies any other files in your Google Drive.\n'
                          '• Backups are private and accessible only by you.\n'
                          '• No Third-Party Tracking: Your attendance data is never sent to third-party servers.',
                          style: TextStyle(fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            if (_isLoading)
              Container(
                color: Colors.black26,
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
