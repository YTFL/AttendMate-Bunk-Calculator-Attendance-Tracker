import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../models/app_update_model.dart';
import '../../services/update_service.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/url_launcher_utils.dart';
import '../home/update_dialog.dart';
import 'setup_guide_screen.dart';
import 'time_format_provider.dart';
import 'whats_new_screen.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final UpdateService _updateService = UpdateService();

  late Future<PackageInfo> _packageInfoFuture;
  late Future<DateTime?> _currentVersionReleaseDateFuture;
  AppUpdate? _availableUpdate;
  bool _isCheckingForUpdate = false;
  bool _hasCheckedForUpdate = false;

  static const String _issuesUrl =
      'https://github.com/YTFL/AttendMate-Bunk-Calculator-Attendance-Tracker/issues';
  static final String _repoUrl = _issuesUrl.replaceFirst('/issues', '');

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
    _currentVersionReleaseDateFuture = _loadBundledReleaseDate();
  }

  Future<DateTime?> _loadBundledReleaseDate() async {
    try {
      final releaseNotes = await rootBundle.loadString('git_public/RELEASE_NOTES.md');
      final lines = releaseNotes.replaceAll('\r\n', '\n').split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('**Release Date:**')) {
          final dateText = trimmed.replaceFirst('**Release Date:**', '').trim();
          return DateFormat('MMMM d, y').parseStrict(dateText);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<AppUpdate?> _checkForUpdateManually() async {
    setState(() {
      _isCheckingForUpdate = true;
    });

    final update = await _updateService.checkForUpdate(respectDeferral: false);
    if (!mounted) return null;

    setState(() {
      _isCheckingForUpdate = false;
      _hasCheckedForUpdate = true;
      _availableUpdate = update;
    });

    return update;
  }

  Future<void> _onUpdateTileTap() async {
    if (_isCheckingForUpdate) return;

    final update = await _checkForUpdateManually();
    if (!mounted) return;

    if (update == null) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(content: Text('You are already on the latest version.')),
      );
      return;
    }

    await _showUpdateDialog(update);
    if (!mounted) return;

    setState(() {
      _availableUpdate = update;
      _hasCheckedForUpdate = true;
    });
  }

  Future<void> _showUpdateDialog(AppUpdate update) async {
    var isDownloading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, dialogSetState) => FutureBuilder<PackageInfo>(
          future: _packageInfoFuture,
          builder: (dialogContext, snapshot) {
            final currentVersion = snapshot.data?.version ?? '1.0.1';
            return UpdateDialog(
              update: update,
              currentVersion: currentVersion,
              isDownloading: isDownloading,
              onInstallNow: () async {
                dialogSetState(() {
                  isDownloading = true;
                });

                final navigator = Navigator.of(dialogContext);
                final messenger = ScaffoldMessenger.of(context);

                try {
                  final apkFile = await _updateService.downloadAPK(update.version);
                  if (apkFile != null && mounted) {
                    final installResult = await _updateService.installAPK(apkFile);
                    if (!mounted) return;
                    switch (installResult) {
                      case InstallResult.installerStarted:
                        navigator.pop();
                        messenger.showReplacingSnackBar(
                          const SnackBar(
                            content: Text('Installer opened. Complete the update to continue.'),
                          ),
                        );
                        break;
                      case InstallResult.permissionRequired:
                        messenger.showReplacingSnackBar(
                          const SnackBar(
                            content: Text(
                              'Allow installs from this source, then tap Install Now again.',
                            ),
                          ),
                        );
                        break;
                      case InstallResult.installerUnavailable:
                        messenger.showReplacingSnackBar(
                          const SnackBar(
                            content: Text('No installer found to open the APK on this device.'),
                          ),
                        );
                        break;
                      case InstallResult.failed:
                        messenger.showReplacingSnackBar(
                          const SnackBar(
                            content: Text('Failed to launch installer. APK saved for retry.'),
                          ),
                        );
                        break;
                    }
                  } else if (mounted) {
                    messenger.showReplacingSnackBar(
                      const SnackBar(content: Text('Failed to download update')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showReplacingSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                } finally {
                  if (mounted) {
                    dialogSetState(() {
                      isDownloading = false;
                    });
                  }
                }
              },
              onRemindLater: () async {
                try {
                  await _updateService.deferUpdate();
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                } catch (e) {
                  debugPrint('Error deferring update: $e');
                }
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);

    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('Use 24-hour format'),
          subtitle: Text(
            timeFormatProvider.is24Hour ? 'Currently: 24-hour' : 'Currently: 12-hour (AM/PM)',
          ),
          trailing: Switch(
            value: timeFormatProvider.is24Hour,
            onChanged: (value) {
              if (value) {
                timeFormatProvider.set24HourFormat();
              } else {
                timeFormatProvider.set12HourFormat();
              }
            },
          ),
          onTap: () {
            if (timeFormatProvider.is24Hour) {
              timeFormatProvider.set12HourFormat();
            } else {
              timeFormatProvider.set24HourFormat();
            }
          },
        ),
        FutureBuilder<PackageInfo>(
          future: _packageInfoFuture,
          builder: (context, snapshot) {
            final version = snapshot.data?.version ?? 'Loading...';

            return ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('App version'),
              subtitle: Text(version),
            );
          },
        ),
        FutureBuilder<PackageInfo>(
          future: _packageInfoFuture,
          builder: (context, snapshot) {
            final buildNumber = snapshot.data?.buildNumber ?? 'Loading...';

            return ListTile(
              leading: const Icon(Icons.tag_outlined),
              title: const Text('Build number'),
              subtitle: Text(buildNumber),
            );
          },
        ),
        ListTile(
          leading: Icon(
            _availableUpdate != null
                ? Icons.system_update_alt_outlined
                : Icons.system_update_outlined,
          ),
          title: const Text('App updates'),
          subtitle: Text(
            _isCheckingForUpdate
                ? 'Checking for updates...'
                : _availableUpdate != null
                    ? 'Update to v${_availableUpdate!.version}'
                    : _hasCheckedForUpdate
                        ? 'You are on the latest version'
                        : 'Tap to check for updates',
          ),
          trailing: _isCheckingForUpdate
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _availableUpdate != null
                  ? const _UpdateAvailableBadge()
                  : const Icon(Icons.chevron_right),
          onTap: _isCheckingForUpdate ? null : _onUpdateTileTap,
        ),
        FutureBuilder<PackageInfo>(
          future: _packageInfoFuture,
          builder: (context, snapshot) {
            final version = snapshot.data?.version;

            return ListTile(
              leading: const Icon(Icons.new_releases_outlined),
              title: const Text('What\'s New'),
              subtitle: Text(
                version == null
                    ? 'See updates in your installed version'
                    : 'See updates in v$version',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const WhatsNewScreen()),
                );
              },
            );
          },
        ),
        FutureBuilder<DateTime?>(
          future: _currentVersionReleaseDateFuture,
          builder: (context, snapshot) {
            final releaseDate = snapshot.data;
            final subtitle = releaseDate != null
                ? DateFormat.yMMMd().format(releaseDate)
                : (snapshot.connectionState == ConnectionState.waiting
                    ? 'Loading...'
                    : 'Unavailable');

            return ListTile(
              leading: const Icon(Icons.update_outlined),
              title: const Text('Current version release date'),
              subtitle: Text(subtitle),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Setup Guide'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SetupGuideScreen()),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.favorite_border_outlined),
          title: const Text('Support me'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final isDarkMode = Theme.of(context).brightness == Brightness.dark;
            showDialog(
              context: context,
              barrierColor: isDarkMode
                  ? Colors.white.withValues(alpha: 0.12)
                  : null,
              builder: (dialogContext) {
                return AlertDialog(
                  title: const Text('Support Me'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Please consider starring my GitHub repository to support me.'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        final launched = await UrlLauncherUtils.launchExternalUrl(_repoUrl);
                        if (!context.mounted) return;
                        if (!launched) {
                          ScaffoldMessenger.of(context).showReplacingSnackBar(
                            const SnackBar(content: Text('Could not open the repository page.')),
                          );
                        }
                      },
                      child: const Text('Open GitHub Repo'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                );
              },
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Request feature / Report bug'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final isDarkMode = Theme.of(context).brightness == Brightness.dark;
            showDialog(
              context: context,
              barrierColor: isDarkMode
                  ? Colors.white.withValues(alpha: 0.12)
                  : null,
              builder: (dialogContext) {
                return AlertDialog(
                  title: const Text('Request Feature or Report Bug'),
                  content: const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Please create a new issue on my GitHub Issues page.'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        final launched = await UrlLauncherUtils.launchExternalUrl(_issuesUrl);
                        if (!context.mounted) return;
                        if (!launched) {
                          ScaffoldMessenger.of(context).showReplacingSnackBar(
                            const SnackBar(content: Text('Could not open the issues page.')),
                          );
                        }
                      },
                      child: const Text('Open Issues Page'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _UpdateAvailableBadge extends StatelessWidget {
  const _UpdateAvailableBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Update available',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}