import 'package:flutter/material.dart';
import '../../utils/url_launcher_utils.dart';

class KeepAndroidOpenScreen extends StatelessWidget {
  const KeepAndroidOpenScreen({super.key});

  static const String petitionUrl =
      'https://www.change.org/p/stop-google-from-limiting-apk-file-usage/';
  static const String changeOrgUrl =
      'https://www.change.org/p/stop-google-from-limiting-apk-file-usage/';
  static const String keepAndroidOpenWebUrl = 'https://keepandroidopen.org';
  static const String fdroidUrl = 'https://f-droid.org';
  static const String freeDroidWarnUrl = 'https://github.com/woheller69/FreeDroidWarn';

  Future<void> _launch(BuildContext context, String url) async {
    final result = await UrlLauncherUtils.launchExternalUrl(url, context: context);
    if (result == LaunchResult.failed && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Keep Android Open'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Alert Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: isDark ? 0.4 : 0.6),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amber,
                    size: 32,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'January 2027 Sideloading Alert',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Google plans to restrict app sideloading on certified Android devices. Independent open-source apps like AttendMate could be blocked or delayed.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section 1: The Situation
            const Text(
              'What Is Happening?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Starting in late 2026 with a global rollout in 2027, Google is implementing a developer identity verification requirement for all apps installed on certified Android devices—even when installed outside the Google Play Store (via GitHub, direct APK downloads, or F-Droid).\n\n'
              'Apps from independent developers who do not submit government identity verification to Google will face an "advanced flow" with high-friction warning gates, mandatory 24-hour cooling off periods, and potential installation bans.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 20),

            // Section 2: Why it matters for AttendMate
            const Text(
              'Why AttendMate & FOSS Are Affected',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'AttendMate is 100% free, ad-free, local-first, and open-source under the AGPL-3.0 license. I believe in software freedom and student privacy.\n\n'
              'Mandating identity verification gives Google centralized veto power over which software runs on your device, effectively transforming Android into a walled garden like iOS and stifling open-source innovation.',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),

            // Section 3: Take Action
            const Text(
              'Take Action & Support the Movement',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // Petition Button
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit_note_rounded, color: Colors.red),
                ),
                title: const Text(
                  'Sign the Petition',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: const Text(
                  'Join thousands defending open-source app freedom on Android.',
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () => _launch(context, changeOrgUrl),
              ),
            ),
            const SizedBox(height: 10),

            // KeepAndroidOpen.org Button
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.public_rounded, color: Colors.blue),
                ),
                title: const Text(
                  'Visit KeepAndroidOpen.org',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: const Text('Read the coalition open letters and regulatory initiatives'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () => _launch(context, keepAndroidOpenWebUrl),
              ),
            ),
            const SizedBox(height: 10),

            // F-Droid Button
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.android_rounded, color: Colors.teal),
                ),
                title: const Text(
                  'Explore F-Droid',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: const Text('The Free and Open Source Android app repository'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () => _launch(context, fdroidUrl),
              ),
            ),
            const SizedBox(height: 10),

            // FreeDroidWarn Info Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.code_rounded, color: Colors.purple),
                ),
                title: const Text(
                  'FreeDroidWarn Library',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                subtitle: const Text('Open-source upgrade warning library by woheller69'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () => _launch(context, freeDroidWarnUrl),
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}
