import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/snackbar_utils.dart';
import '../utils/url_launcher_utils.dart';

class BatteryOptimizationService {
  static const MethodChannel _channel =
      MethodChannel('com.attendmate.app/battery_optimization');

  static final BatteryOptimizationService _instance =
      BatteryOptimizationService._internal();

  factory BatteryOptimizationService() => _instance;

  BatteryOptimizationService._internal();

  /// Checks whether AttendMate currently has unrestricted background access (ignores battery optimizations).
  /// Always returns `true` on non-Android platforms.
  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? isIgnoring =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return isIgnoring ?? false;
    } on PlatformException catch (e) {
      debugPrint('Error checking battery optimization status: $e');
      return false;
    } catch (e) {
      debugPrint('Unexpected error checking battery optimization status: $e');
      return false;
    }
  }

  /// Requests direct OS battery optimization exemption prompt from the user.
  Future<bool> requestIgnoreBatteryOptimization() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool result =
          await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      return result;
    } on PlatformException catch (e) {
      debugPrint('Error requesting battery optimization exemption: $e');
      return await openBatteryOptimizationSettings();
    } catch (e) {
      debugPrint('Unexpected error requesting battery optimization exemption: $e');
      return await openBatteryOptimizationSettings();
    }
  }

  /// Redirects the user directly to the Android Battery Settings page for AttendMate.
  Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool result =
          await _channel.invokeMethod('openBatteryOptimizationSettings');
      return result;
    } on PlatformException catch (e) {
      debugPrint('Error opening battery optimization settings: $e');
      return false;
    } catch (e) {
      debugPrint('Unexpected error opening battery optimization settings: $e');
      return false;
    }
  }

  /// Shows a minimal dialog explaining background access, allowing the user
  /// to trigger the exemption prompt directly.
  Future<void> showBatteryOptimizationDialog(
    BuildContext context, {
    VoidCallback? onStatusChanged,
  }) async {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool isAlreadyUnrestricted = await isIgnoringBatteryOptimizations();

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withAlpha(31) : null,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(
                    isAlreadyUnrestricted
                        ? Icons.battery_charging_full_rounded
                        : Icons.battery_saver_rounded,
                    color: isAlreadyUnrestricted
                        ? Colors.green.shade700
                        : Colors.amber.shade800,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Background Access',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAlreadyUnrestricted
                          ? 'AttendMate has unrestricted background access. Class reminders, location triggers, and backups run reliably.'
                          : 'Allow AttendMate to run in the background without battery restrictions so class reminders and backups aren\'t stopped.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).textTheme.bodyMedium?.color,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDarkMode ? Colors.white24 : Colors.black12,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.phone_android_rounded,
                                size: 18,
                                color: isDarkMode ? Colors.white70 : Colors.black87,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Manufacturer Restrictions',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isDarkMode ? Colors.white : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Brands like Samsung, Xiaomi, OnePlus, and Huawei kill background apps aggressively even with standard settings.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode ? Colors.white60 : Colors.black54,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                UrlLauncherUtils.launchExternalUrl(
                                  'https://dontkillmyapp.com',
                                  context: context,
                                );
                              },
                              icon: const Icon(Icons.open_in_new_rounded, size: 16),
                              label: const Text('dontkillmyapp.com Guide'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDarkMode ? Colors.white : Colors.black87,
                                side: BorderSide(
                                  color: isDarkMode ? Colors.white38 : Colors.black26,
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(isAlreadyUnrestricted ? 'Close' : 'Cancel'),
                ),
                if (!isAlreadyUnrestricted)
                  ElevatedButton(
                    onPressed: () async {
                      await requestIgnoreBatteryOptimization();
                      if (context.mounted) {
                        final updated = await isIgnoringBatteryOptimizations();
                        setDialogState(() {
                          isAlreadyUnrestricted = updated;
                        });
                        onStatusChanged?.call();
                        if (updated && context.mounted) {
                          Navigator.of(dialogContext).pop();
                          ScaffoldMessenger.of(context).showReplacingSnackBar(
                            const SnackBar(
                              content: Text('Unrestricted background access enabled!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Get Access'),
                  ),
              ],
            );
          },
        );
      },
    );

    onStatusChanged?.call();
  }
}
