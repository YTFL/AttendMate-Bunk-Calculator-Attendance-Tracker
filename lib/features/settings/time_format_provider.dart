import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/time_format_utils.dart';

/// Provider to manage user's time format preference
class TimeFormatProvider with ChangeNotifier {
  static const String _timeFormatKey = 'time_format_preference';
  
  TimeFormat _timeFormat = TimeFormat.format24Hr;
  bool _isInitialized = false;

  TimeFormat get timeFormat => _timeFormat;
  bool get isInitialized => _isInitialized;

  /// Initialize the provider by loading saved preferences
  Future<void> init(BuildContext? context) async {
    final bool? systemUses24Hour =
        context != null ? TimeFormatUtils.isSystem24HourFormat(context) : null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedFormat = prefs.getString(_timeFormatKey);
      
      if (savedFormat != null) {
        // Load saved preference
        _timeFormat = savedFormat == 'format12Hr' 
            ? TimeFormat.format12Hr 
            : TimeFormat.format24Hr;
      } else {
        // Use device's system format preference
        final uses24Hour = systemUses24Hour ?? true;
        _timeFormat = uses24Hour ? TimeFormat.format24Hr : TimeFormat.format12Hr;
        // Save the detected format
        await _savePreference();
      }
    } catch (e) {
      debugPrint('Failed to initialize TimeFormatProvider: $e');
      _timeFormat = TimeFormat.format24Hr; // Fallback to 24-hour
    }
    
    _isInitialized = true;
    notifyListeners();
  }

  /// Switch between 12-hour and 24-hour format
  Future<void> toggleTimeFormat() async {
    _timeFormat = _timeFormat == TimeFormat.format12Hr 
        ? TimeFormat.format24Hr 
        : TimeFormat.format12Hr;
    await _savePreference();
    notifyListeners();
  }

  /// Set time format to 12-hour
  Future<void> set12HourFormat() async {
    if (_timeFormat != TimeFormat.format12Hr) {
      _timeFormat = TimeFormat.format12Hr;
      await _savePreference();
      notifyListeners();
    }
  }

  /// Set time format to 24-hour
  Future<void> set24HourFormat() async {
    if (_timeFormat != TimeFormat.format24Hr) {
      _timeFormat = TimeFormat.format24Hr;
      await _savePreference();
      notifyListeners();
    }
  }

  /// Get the current format as a user-friendly string
  String get formatDisplayName {
    return _timeFormat == TimeFormat.format12Hr ? '12-hour (AM/PM)' : '24-hour';
  }

  /// Check if current format is 12-hour
  bool get is12Hour => _timeFormat == TimeFormat.format12Hr;

  /// Check if current format is 24-hour
  bool get is24Hour => _timeFormat == TimeFormat.format24Hr;

  /// Save the current preference to SharedPreferences
  Future<void> _savePreference() async {
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
}
