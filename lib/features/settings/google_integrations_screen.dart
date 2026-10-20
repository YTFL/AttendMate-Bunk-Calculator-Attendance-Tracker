import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/calendar_service.dart';
import '../../services/google_auth_service.dart';
import '../../services/google_drive_backup_service.dart';
import '../semester/semester_provider.dart';
import '../subject/subject_provider.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/day_cycle_background.dart';
import '../../widgets/glass_dialog.dart';
import 'google_calendar_sync_screen.dart';

class GoogleIntegrationsScreen extends StatefulWidget {
  const GoogleIntegrationsScreen({super.key});

  @override
  State<GoogleIntegrationsScreen> createState() => _GoogleIntegrationsScreenState();
}

class _GoogleIntegrationsScreenState extends State<GoogleIntegrationsScreen> {
  final _authService = GoogleAuthService.instance;
  final _driveService = GoogleDriveBackupService();

  bool _isDriveBackupEnabled = GoogleDriveBackupService.isBackupEnabledSync;
  bool _isCalendarSyncEnabled = CalendarService.isGoogleCalendarSyncEnabledSync;
  DateTime? _lastDriveBackupTime = GoogleDriveBackupService.lastBackupTimeSync;
  DriveBackupFileInfo? _existingDriveBackup = GoogleDriveBackupService.cachedExistingBackup;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _authService.addListener(_onAuthStateChanged);
    _loadIntegrationSettings();
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthStateChanged);
    super.dispose();
  }

  void _onAuthStateChanged() {
    if (mounted) {
      _loadIntegrationSettings();
    }
  }

  Future<void> _loadIntegrationSettings() async {
    final driveEnabled = await _driveService.isBackupEnabled();
    final lastBackup = await _driveService.getLastBackupTime();
    final calendarEnabled = await CalendarService.isGoogleCalendarSyncEnabled();

    if (mounted) {
      setState(() {
        _isDriveBackupEnabled = driveEnabled;
        _isCalendarSyncEnabled = calendarEnabled;
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      barrierColor: isDarkMode ? Colors.black.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.3),
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Out from Google?'),
        content: const Text(
          'Logging out will disable Google Calendar sync and Google Drive cloud backups until you sign in again.',
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
      await CalendarService.setGoogleCalendarSyncEnabled(false);
      setState(() {
        _isDriveBackupEnabled = false;
        _isCalendarSyncEnabled = false;
        _isLoading = false;
        _existingDriveBackup = null;
      });
      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(context, 'Logged out from Google Account.');
      }
    }
  }

  Future<void> _toggleCalendarSync(bool enabled) async {
    await CalendarService.setGoogleCalendarSyncEnabled(enabled);
    if (!mounted) return;
    setState(() => _isCalendarSyncEnabled = enabled);

    if (enabled) {
      await _forceCalendarSync();
    } else {
      final semester = Provider.of<SemesterProvider>(context, listen: false).semester;
      setState(() => _isLoading = true);
      await CalendarService.deleteAllSyncedEvents(semester, force: true);
      if (!mounted) return;
      setState(() => _isLoading = false);
      SnackbarUtils.showSuccessSnackBar(context, 'Google Calendar sync disabled. Synced events cleared.');
    }
  }

  Future<void> _checkExistingCloudBackup() async {
    final backup = await _driveService.checkForExistingBackup();
    setState(() => _existingDriveBackup = backup);

    if (backup != null && mounted) {
      final formattedDate = DateFormat.yMMMd().add_jm().format(backup.modifiedTime);
      final sizeKb = (backup.sizeBytes / 1024).toStringAsFixed(1);

      showGlassDialog(
        context: context,
        builder: (ctx) => GlassDialog(
          icon: const Icon(Icons.cloud_download_outlined, size: 28, color: Colors.blue),
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
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
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
    await _loadIntegrationSettings();
    setState(() => _isLoading = false);

    if (mounted) {
      if (success) {
        SnackbarUtils.showSuccessSnackBar(context, 'Google Drive backup completed successfully.');
      } else {
        SnackbarUtils.showErrorSnackBar(context, 'Failed to backup database to Google Drive.');
      }
    }
  }

  Future<void> _forceCalendarSync() async {
    final semester = Provider.of<SemesterProvider>(context, listen: false).semester;
    final subjects = Provider.of<SubjectProvider>(context, listen: false).subjects;

    if (semester == null) {
      SnackbarUtils.showErrorSnackBar(context, 'Please set up a semester before syncing.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);

      await CalendarService.syncFullTimetable(
        subjects: subjects,
        semester: semester,
        isHoliday: subjectProvider.isHoliday,
      );

      if (mounted) {
        SnackbarUtils.showSuccessSnackBar(context, 'Google Calendar synchronized successfully.');
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Calendar sync failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;

    return DayCycleBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Google Integrations'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // ── 1. User Profile or Connect Account Hero Card ─────────
              if (user != null)
                _buildConnectedUserCard(user, colorScheme, isDarkMode)
              else
                _buildConnectGoogleCard(colorScheme, isDarkMode),

              const SizedBox(height: 24),

              // Section Header
              Text(
                'CONNECTED CLOUD SERVICES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: colorScheme.primary,
                ),
              ),

              const SizedBox(height: 12),

              // ── 2. Google Calendar Sync Card ────────────────────────
              _buildCalendarSyncCard(user != null, colorScheme, isDarkMode),

              const SizedBox(height: 14),

              // ── 3. Google Drive Cloud Backup Card ───────────────────
              _buildDriveBackupCard(user != null, colorScheme, isDarkMode),

              const SizedBox(height: 24),

              // ── 4. Privacy & Trust Strip ─────────────────────────────
              _buildPrivacyTrustCard(colorScheme, isDarkMode),

              const SizedBox(height: 40),
            ],
          ),

          // ── Frosted Loading Overlay ──────────────────────────────────
          if (_isLoading)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: SingleChildScrollView(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF14141E).withValues(alpha: 0.90)
                                : Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDarkMode ? Colors.white12 : Colors.black12,
                            ),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(strokeWidth: 3),
                              SizedBox(height: 18),
                              Text(
                                'Syncing with Google...',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                      ),
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

  // ── Connected User Hero Card ──────────────────────────────────────────
  Widget _buildConnectedUserCard(dynamic user, ColorScheme colorScheme, bool isDarkMode) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF0F0F16).withValues(alpha: 0.60)
                : Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.08),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // User Avatar with ring
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundImage: user.photoUrl != null
                          ? ResizeImage(
                              NetworkImage(user.photoUrl!),
                              width: 160,
                              height: 160,
                            )
                          : null,
                      backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
                      child: user.photoUrl == null
                          ? Text(
                              (user.displayName?.isNotEmpty == true
                                      ? user.displayName![0]
                                      : user.email[0])
                                  .toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Name & Email
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName ?? 'Google User',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Connected status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.green, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Connected',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Bottom Row with Logout
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Active Google Cloud Session',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _handleSignOut,
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 15),
                    label: const Text('Disconnect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Connect Google Account Hero Card ──────────────────────────────────
  Widget _buildConnectGoogleCard(ColorScheme colorScheme, bool isDarkMode) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF0F0F16).withValues(alpha: 0.60)
                : Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.08),
              width: 1.0,
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.hub_outlined,
                  size: 40,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Connect Google Account',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to synchronize your weekly class timetable with Google Calendar and back up attendance securely to Google Drive.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _isLoading ? null : _handleSignIn,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Sign in with Google', style: TextStyle(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Google Calendar Sync Glass Card ───────────────────────────────────
  Widget _buildCalendarSyncCard(bool isSignedIn, ColorScheme colorScheme, bool isDarkMode) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF13131B).withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.11)
                  : Colors.black.withValues(alpha: 0.07),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.calendar_month_rounded, color: colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google Calendar Sync',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Sync class schedule to primary calendar',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isSignedIn && _isCalendarSyncEnabled,
                    onChanged: !isSignedIn
                        ? null
                        : (val) async {
                            await _toggleCalendarSync(val);
                          },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),

              if (isSignedIn) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const GoogleCalendarSyncScreen()),
                          );
                        },
                        icon: const Icon(Icons.settings_outlined, size: 16),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Sync Settings', style: TextStyle(fontSize: 12.5)),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_isLoading || !_isCalendarSyncEnabled) ? null : _forceCalendarSync,
                        icon: const Icon(Icons.sync_rounded, size: 16),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Force Sync'),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 15, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sign in with Google above to enable calendar synchronization.',
                        style: TextStyle(fontSize: 11.5, color: Colors.orange.shade700),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Google Drive Cloud Backup Glass Card ──────────────────────────────
  Widget _buildDriveBackupCard(bool isSignedIn, ColorScheme colorScheme, bool isDarkMode) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF13131B).withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.11)
                  : Colors.black.withValues(alpha: 0.07),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.cloud_upload_outlined, color: colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google Drive Cloud Backup',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Automatic daily backup at midnight',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isSignedIn && _isDriveBackupEnabled,
                    onChanged: !isSignedIn
                        ? null
                        : (val) async {
                            setState(() => _isDriveBackupEnabled = val);
                            await _driveService.setBackupEnabled(val);
                            if (!mounted) return;
                            if (val) {
                              SnackbarUtils.showSuccessSnackBar(
                                context,
                                'Google Drive midnight backup enabled.',
                              );
                            }
                          },
                  ),
                ],
              ),

              // Snapshot metadata pill
              if (_lastDriveBackupTime != null || _existingDriveBackup != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDarkMode ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.history_rounded, size: 15, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lastDriveBackupTime != null
                              ? 'Last Cloud Snapshot: ${DateFormat.yMMMd().add_jm().format(_lastDriveBackupTime!)}'
                              : 'Cloud Snapshot Available',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface.withValues(alpha: 0.85),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),

              if (isSignedIn) ...[
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _isLoading ? null : _forceDriveBackup,
                        icon: const Icon(Icons.backup_outlined, size: 16),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Backup Now'),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    if (_existingDriveBackup != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  showGlassDialog(
                                    context: context,
                                    builder: (ctx) => GlassDialog(
                                      icon: const Icon(Icons.cloud_download_outlined, size: 28, color: Colors.blue),
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
                          label: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Restore Backup'),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ] else
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 15, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sign in with Google above to enable Drive cloud backups.',
                        style: TextStyle(fontSize: 11.5, color: Colors.orange.shade700),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Privacy & Trust Strip ─────────────────────────────────────────────
  Widget _buildPrivacyTrustCard(ColorScheme colorScheme, bool isDarkMode) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF13131B).withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.60),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_outlined, size: 16, color: Colors.green),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Privacy & Data Guarantees',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '• Restricted Storage: AttendMate only accesses its private appDataFolder on Google Drive and never inspects personal files.\n'
                '• Semester Scope: Calendar synchronization strictly operates within your configured active semester bounds.\n'
                '• Zero Telemetry: No third-party servers, tracking cookies, or external analytics.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

