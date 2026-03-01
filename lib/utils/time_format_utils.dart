import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Enum to represent time format preferences
enum TimeFormat {
  /// 12-hour format with AM/PM (e.g., 2:30 PM)
  format12Hr,

  /// 24-hour format (e.g., 14:30)
  format24Hr,
}

/// Utility class for time formatting operations
class TimeFormatUtils {
  /// Convert a TimeOfDay to a formatted string based on the format preference
  ///
  /// [timeOfDay] - The time to format
  /// [format] - The desired format (12hr or 24hr)
  /// [context] - BuildContext needed for locale-aware formatting (optional)
  ///
  /// Returns a formatted time string
  static String formatTime(
    TimeOfDay timeOfDay,
    TimeFormat format, {
    BuildContext? context,
  }) {
    final hour = timeOfDay.hour;
    final minute = timeOfDay.minute;

    if (format == TimeFormat.format24Hr) {
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    } else {
      // 12-hour format
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      final period = hour < 12 ? 'AM' : 'PM';
      return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    }
  }

  /// Format a time range (start time - end time)
  ///
  /// [startTime] - Start time
  /// [endTime] - End time
  /// [format] - The desired format
  /// [context] - BuildContext for locale-aware formatting (optional)
  ///
  /// Returns formatted time range string
  static String formatTimeRange(
    TimeOfDay startTime,
    TimeOfDay endTime,
    TimeFormat format, {
    BuildContext? context,
  }) {
    final start = formatTime(startTime, format, context: context);
    final end = formatTime(endTime, format, context: context);
    return '$start - $end';
  }

  /// Detect the device's system time format preference
  ///
  /// On Android/iOS, this checks the device's locale settings.
  /// Returns true if the system uses 24-hour format, false if 12-hour
  static bool isSystem24HourFormat(BuildContext context) {
    try {
      final mediaQuery = MediaQuery.maybeOf(context);
      if (mediaQuery != null) {
        return mediaQuery.alwaysUse24HourFormat;
      }

      // Try to detect from locale
      final locale = Localizations.localeOf(context);
      
      // Check if the locale uses 24-hour format
      // Most locales use 24-hour format except for some like en_US, en_AU, etc.
      final dateFormat = DateFormat('', locale.toString());
      final pattern = dateFormat.pattern ?? '';
      
      // If pattern contains 'a' or 'A', it uses 12-hour format
      if (pattern.contains('a') || pattern.contains('A')) {
        return false;
      }
      
      // Default check: Most English locales use 12-hour, others use 24-hour
      final languageCode = locale.languageCode;
      
      // Known 12-hour format locales
      const twelveHourLocales = ['en', 'es', 'pt', 'hi'];
      
      return !twelveHourLocales.contains(languageCode);
    } catch (e) {
      return true;
    }
  }

  /// Convert a TimeOfDay (24-hour internal format) to 12-hour display format
  ///
  /// This is useful when only needing to convert to 12-hour format
  static String to12HourFormat(TimeOfDay time) {
    final hour = time.hour;
    final minute = time.minute;
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final period = hour < 12 ? 'AM' : 'PM';
    return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
  }

  /// Convert a TimeOfDay to 24-hour display format
  static String to24HourFormat(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
