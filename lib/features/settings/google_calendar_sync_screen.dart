import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/calendar_service.dart';
import '../../utils/snackbar_utils.dart';
import '../semester/semester_provider.dart';
import '../subject/subject_provider.dart';

class GoogleCalendarSyncScreen extends StatefulWidget {
  const GoogleCalendarSyncScreen({super.key});

  @override
  State<GoogleCalendarSyncScreen> createState() => _GoogleCalendarSyncScreenState();
}

class _GoogleCalendarSyncScreenState extends State<GoogleCalendarSyncScreen> {
  bool _isConnected = false;
  String? _userEmail;
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final signedIn = await CalendarService.isUserSignedIn();
      String? email;
      if (signedIn) {
        email = await CalendarService.getSignedInUserEmail();
      }
      setState(() {
        _isConnected = signedIn;
        _userEmail = email;
      });
    } catch (e) {
      debugPrint("Error checking connection status: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _connect() async {
    setState(() {
      _isSyncing = true;
    });
    try {
      await CalendarService.syncFullTimetable(
        subjects: [], // Dry run to establish auth connection
        semester: Provider.of<SemesterProvider>(context, listen: false).semester!,
        isHoliday: Provider.of<SubjectProvider>(context, listen: false).isHoliday,
      );
      await _checkStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('Successfully connected to Google Calendar!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await CalendarService.signOut();
      setState(() {
        _isConnected = false;
        _userEmail = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('Disconnected Google Calendar account.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text('Error signing out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sync() async {
    final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);

    if (semesterProvider.semester == null) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('Please set up your semester dates first in "Semester Details".'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (subjectProvider.subjects.isEmpty) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('No subjects/schedule to sync.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      await CalendarService.syncFullTimetable(
        subjects: subjectProvider.subjects,
        semester: semesterProvider.semester!,
        isHoliday: subjectProvider.isHoliday,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('Timetable successfully synced to Google Calendar!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text('Google Calendar Sync Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  String _formatDate(DateTime date) {
    return "${date.day} ${_getMonthName(date.month)} ${date.year}";
  }

  @override
  Widget build(BuildContext context) {
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final hasSemester = semesterProvider.semester != null;
    final semester = semesterProvider.semester;
    final subjectCount = subjectProvider.subjects.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Calendar Sync'),
        elevation: 0,
        actions: [
          if (_isConnected && !_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Check Status',
              onPressed: _checkStatus,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Status Dashboard Box
                      _buildStatusCard(hasSemester),
                      const SizedBox(height: 24),
                      
                      // Active Sync Configuration
                      if (_isConnected && hasSemester) ...[
                        _buildScopeOverviewCard(semester!, subjectCount),
                        const SizedBox(height: 24),
                      ],
                      
                      // Title section
                      Text(
                        'Integration Capabilities',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                      ),
                      const SizedBox(height: 12),

                      // List of features
                      _buildInfoTile(
                        Icons.cached_rounded,
                        'One-Click Overwrite',
                        'Updating timetables or slots in the app and syncing again overwrites existing Google Calendar events. No duplicates are created.',
                      ),
                      _buildInfoTile(
                        Icons.cleaning_services_rounded,
                        'Auto Clean Up',
                        'Syncing automatically removes past calendar events of subjects or specific classes that you delete from the app.',
                      ),
                      _buildInfoTile(
                        Icons.event_busy_rounded,
                        'Holiday & Cancellation Exclusion',
                        'Fully automated. Classes falling on declared holidays or individually marked as cancelled are automatically excluded (using EXDATE exception rules) from the Google Calendar.',
                      ),
                      _buildInfoTile(
                        Icons.palette_rounded,
                        'Color Syncing',
                        'Automatically maps your customized subject colors inside AttendMate to the nearest matching official Google Calendar color palette.',
                      ),

                      if (!hasSemester) ...[
                        const SizedBox(height: 20),
                        _buildWarningCard(
                          'Semester dates must be configured in "Semester Details" before calendar synchronization can be initialized.',
                        ),
                      ],
                      const SizedBox(height: 24),
                      const Divider(),
                      const SizedBox(height: 16),
                      _buildPrivacyLinks(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                
                // Loading Overlay with Backdrop Filter
                if (_isSyncing)
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        child: Center(
                          child: Card(
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            color: Theme.of(context).colorScheme.surface,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 32.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    height: 48,
                                    width: 48,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 4,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    'Syncing Calendar...',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Updating events and exclusions...',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildStatusCard(bool hasSemester) {
    if (_isConnected) {
      final initialLetter = (_userEmail != null && _userEmail!.isNotEmpty)
          ? _userEmail![0].toUpperCase()
          : 'G';

      final isDarkMode = Theme.of(context).brightness == Brightness.dark;
      
      // Dynamic Colors
      final cardBgColor = isDarkMode ? Colors.black : Colors.white;
      final cardTextColor = isDarkMode ? Colors.white : Colors.black;
      final cardBorderColor = isDarkMode ? Colors.white24 : Colors.grey.shade300;
      
      // Button Colors (Gray buttons)
      final syncBtnBgColor = isDarkMode ? Colors.grey.shade900 : Colors.grey.shade100;
      final syncBtnTextColor = isDarkMode ? Colors.white : Colors.black;
      
      // Disconnect button
      final discBtnBgColor = isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200;
      final discIconColor = isDarkMode ? Colors.white : Colors.black;

      // Connected badge
      final badgeBgColor = isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade100;
      final badgeTextColor = isDarkMode ? Colors.white70 : Colors.black87;
      final badgeIconColor = isDarkMode ? Colors.white70 : Colors.black87;

      return Container(
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cardBorderColor,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDarkMode ? 0.3 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
                    child: Text(
                      initialLetter,
                      style: TextStyle(
                        color: cardTextColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeBgColor,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: isDarkMode ? Colors.white10 : Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, color: badgeIconColor, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                'Connected',
                                style: TextStyle(
                                  color: badgeTextColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _userEmail ?? 'Google Calendar Account',
                          style: TextStyle(
                            color: cardTextColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.sync_rounded, color: syncBtnTextColor),
                      label: Text(
                        'Sync Now',
                        style: TextStyle(fontWeight: FontWeight.bold, color: syncBtnTextColor),
                      ),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: syncBtnTextColor,
                        backgroundColor: syncBtnBgColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                      ),
                      onPressed: _sync,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: Icon(Icons.power_settings_new_rounded, color: discIconColor),
                    tooltip: 'Disconnect Account',
                    style: IconButton.styleFrom(
                      backgroundColor: discBtnBgColor,
                      padding: const EdgeInsets.all(14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                    ),
                    onPressed: _disconnect,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.calendar_today_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Google Calendar Sync',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect your account to write your timetable classes directly to Google Calendar.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              icon: const Icon(Icons.login_rounded),
              label: const Text(
                'Connect Google Calendar',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 2,
              ),
              onPressed: hasSemester ? _connect : null,
            ),
          ],
        ),
      );
    }
  }

  Widget _buildScopeOverviewCard(dynamic semester, int count) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.security_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Sync Bounds (Semester Only)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildScopeRow(Icons.calendar_month_rounded, 'Active Semester', "Active (${semester.targetPercentage.toInt()}% Target)"),
          const SizedBox(height: 10),
          _buildScopeRow(
            Icons.date_range_rounded,
            'Sync Scope',
            '${_formatDate(semester.startDate)}  —  ${_formatDate(semester.endDate)}',
          ),
          const SizedBox(height: 10),
          _buildScopeRow(
            Icons.subject_rounded,
            'Selected Subjects',
            '$count subject${count == 1 ? '' : 's'} to export',
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 6),
          Text(
            'Important Notice: Only calendar events falling within the dates above will be managed or cleaned up. All other calendar details remain untouched.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
        const SizedBox(width: 10),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildWarningCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () async {
            final url = Uri.parse('https://attend-mate.netlify.app/privacy.html');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          child: Text(
            'Privacy Policy',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(width: 24),
        GestureDetector(
          onTap: () async {
            final url = Uri.parse('https://attend-mate.netlify.app/terms.html');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          child: Text(
            'Terms of Service',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}
