import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available ambient background lighting & theme modes
enum AmbientThemeMode {
  /// Cycles automatically based on local device time:
  /// Morning (5am-12pm), Afternoon (12pm-6pm), Night (6pm-5am)
  dynamicCycle,

  /// Locked to warm radiant golden dawn amber gradient
  morning,

  /// Locked to radiant sunset orange gradient
  afternoon,

  /// Locked to deep midnight sapphire dark blue gradient
  night,

  /// Turn off gradients completely for a clean, minimal, pitch-black AMOLED UI
  amoled,
}

class AmbientThemeProvider with ChangeNotifier {
  static const String _prefKey = 'ambient_theme_mode';

  AmbientThemeMode _mode = AmbientThemeMode.dynamicCycle;
  bool _isLoaded = false;

  AmbientThemeMode get mode => _mode;
  bool get isLoaded => _isLoaded;
  bool get isAmoled => _mode == AmbientThemeMode.amoled;
  bool get isDynamic => _mode == AmbientThemeMode.dynamicCycle;
  bool get isAccent =>
      _mode == AmbientThemeMode.morning ||
      _mode == AmbientThemeMode.afternoon ||
      _mode == AmbientThemeMode.night;

  AmbientThemeProvider() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt(_prefKey);
      if (savedIndex != null &&
          savedIndex >= 0 &&
          savedIndex < AmbientThemeMode.values.length) {
        _mode = AmbientThemeMode.values[savedIndex];
      }
    } catch (_) {
      // Fallback to dynamicCycle on error
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> setMode(AmbientThemeMode newMode) async {
    if (_mode == newMode) return;
    _mode = newMode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKey, newMode.index);
    } catch (_) {}
  }

  /// Cycles to next available mode in order:
  /// Dynamic -> Morning -> Afternoon/Evening -> Blue Night -> AMOLED -> Dynamic
  Future<void> cycleNextMode() async {
    final nextIndex = (_mode.index + 1) % AmbientThemeMode.values.length;
    await setMode(AmbientThemeMode.values[nextIndex]);
  }

  String get displayName {
    switch (_mode) {
      case AmbientThemeMode.dynamicCycle:
        return 'Dynamic (Time-Based)';
      case AmbientThemeMode.morning:
        return 'Morning Golden Dawn';
      case AmbientThemeMode.afternoon:
        return 'Afternoon Warm Sunset';
      case AmbientThemeMode.night:
        return 'Blue Night Twilight';
      case AmbientThemeMode.amoled:
        return 'Clean Minimal AMOLED Black';
    }
  }

  String get shortLabel {
    switch (_mode) {
      case AmbientThemeMode.dynamicCycle:
        return 'Dynamic';
      case AmbientThemeMode.morning:
        return 'Morning';
      case AmbientThemeMode.afternoon:
        return 'Afternoon';
      case AmbientThemeMode.night:
        return 'Night';
      case AmbientThemeMode.amoled:
        return 'AMOLED';
    }
  }

  IconData get icon {
    switch (_mode) {
      case AmbientThemeMode.dynamicCycle:
        return Icons.auto_mode_rounded;
      case AmbientThemeMode.morning:
        return Icons.wb_sunny_rounded;
      case AmbientThemeMode.afternoon:
        return Icons.wb_twilight_rounded;
      case AmbientThemeMode.night:
        return Icons.nights_stay_rounded;
      case AmbientThemeMode.amoled:
        return Icons.contrast_rounded;
    }
  }

  String get description {
    switch (_mode) {
      case AmbientThemeMode.dynamicCycle:
        return 'Transitions with real-time morning, sunset, and midnight cycles.';
      case AmbientThemeMode.morning:
        return 'Always bathed in vibrant amber dawn illumination.';
      case AmbientThemeMode.afternoon:
        return 'Always bathed in warm radiant sunset orange hues.';
      case AmbientThemeMode.night:
        return 'Always bathed in deep midnight sapphire dark blue tones.';
      case AmbientThemeMode.amoled:
        return 'Turns off all ambient gradients for true pitch-black AMOLED clarity.';
    }
  }
}
