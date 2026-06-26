import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/time_format_utils.dart';

enum ClockStyle { material, scroll }

/// Provider to manage user's time format preference and time picker clock style
class TimeFormatProvider with ChangeNotifier {
  static const String _timeFormatKey = 'time_format_preference';
  static const String _clockStyleKey = 'clock_style_preference';
  
  TimeFormat _timeFormat = TimeFormat.format24Hr;
  ClockStyle _clockStyle = ClockStyle.material;
  bool _isInitialized = false;

  TimeFormat get timeFormat => _timeFormat;
  ClockStyle get clockStyle => _clockStyle;
  bool get isInitialized => _isInitialized;

  /// Initialize the provider by loading saved preferences
  Future<void> init(BuildContext? context) async {
    final bool? systemUses24Hour =
        context != null ? TimeFormatUtils.isSystem24HourFormat(context) : null;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load saved time format
      final savedFormat = prefs.getString(_timeFormatKey);
      if (savedFormat != null) {
        _timeFormat = savedFormat == 'format12Hr' 
            ? TimeFormat.format12Hr 
            : TimeFormat.format24Hr;
      } else {
        final uses24Hour = systemUses24Hour ?? true;
        _timeFormat = uses24Hour ? TimeFormat.format24Hr : TimeFormat.format12Hr;
        await _saveTimeFormatPreference();
      }

      // Load saved clock style
      final savedClockStyle = prefs.getString(_clockStyleKey);
      if (savedClockStyle != null) {
        _clockStyle = savedClockStyle == 'scroll'
            ? ClockStyle.scroll
            : ClockStyle.material;
      } else {
        _clockStyle = ClockStyle.material;
        await _saveClockStylePreference();
      }
    } catch (e) {
      debugPrint('Failed to initialize TimeFormatProvider: $e');
      _timeFormat = TimeFormat.format24Hr;
      _clockStyle = ClockStyle.material;
    }
    
    _isInitialized = true;
    notifyListeners();
  }

  /// Switch between 12-hour and 24-hour format
  Future<void> toggleTimeFormat() async {
    _timeFormat = _timeFormat == TimeFormat.format12Hr 
        ? TimeFormat.format24Hr 
        : TimeFormat.format12Hr;
    await _saveTimeFormatPreference();
    notifyListeners();
  }

  /// Set time format to 12-hour
  Future<void> set12HourFormat() async {
    if (_timeFormat != TimeFormat.format12Hr) {
      _timeFormat = TimeFormat.format12Hr;
      await _saveTimeFormatPreference();
      notifyListeners();
    }
  }

  /// Set time format to 24-hour
  Future<void> set24HourFormat() async {
    if (_timeFormat != TimeFormat.format24Hr) {
      _timeFormat = TimeFormat.format24Hr;
      await _saveTimeFormatPreference();
      notifyListeners();
    }
  }

  /// Set time picker clock style
  Future<void> setClockStyle(ClockStyle style) async {
    if (_clockStyle != style) {
      _clockStyle = style;
      await _saveClockStylePreference();
      notifyListeners();
    }
  }

  /// Get the current format as a user-friendly string
  String get formatDisplayName {
    return _timeFormat == TimeFormat.format12Hr ? '12-hour (AM/PM)' : '24-hour';
  }

  /// Get the current clock style as a user-friendly string
  String get clockStyleDisplayName {
    return _clockStyle == ClockStyle.scroll ? 'Scroll Wheel' : 'Material Dialog';
  }

  /// Check if current format is 12-hour
  bool get is12Hour => _timeFormat == TimeFormat.format12Hr;

  /// Check if current format is 24-hour
  bool get is24Hour => _timeFormat == TimeFormat.format24Hr;

  /// Save the current time format preference to SharedPreferences
  Future<void> _saveTimeFormatPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final formatString = _timeFormat == TimeFormat.format12Hr 
          ? 'format12Hr' 
          : 'format24Hr';
      await prefs.setString(_timeFormatKey, formatString);
    } catch (e) {
      debugPrint('Failed to save time format preference: $e');
    }
  }

  /// Save the current clock style preference to SharedPreferences
  Future<void> _saveClockStylePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clockStyleString = _clockStyle == ClockStyle.scroll 
          ? 'scroll' 
          : 'material';
      await prefs.setString(_clockStyleKey, clockStyleString);
    } catch (e) {
      debugPrint('Failed to save clock style preference: $e');
    }
  }
}
