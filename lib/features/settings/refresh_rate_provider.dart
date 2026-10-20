import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available screen refresh rate preferences
enum RefreshRateOption {
  /// Follows native device display policy / system adaptive refresh rate
  deviceDefault,

  /// Locked to 60 Hz (maximum battery preservation)
  hz60,

  /// Locked to 90 Hz (balanced smoothness)
  hz90,

  /// Locked to 120 Hz (ultra-fluid, maximum responsiveness)
  hz120,
}

extension RefreshRateOptionExtension on RefreshRateOption {
  int? get targetHz {
    switch (this) {
      case RefreshRateOption.deviceDefault:
        return null;
      case RefreshRateOption.hz60:
        return 60;
      case RefreshRateOption.hz90:
        return 90;
      case RefreshRateOption.hz120:
        return 120;
    }
  }

  String get label {
    switch (this) {
      case RefreshRateOption.deviceDefault:
        return 'Default';
      case RefreshRateOption.hz60:
        return '60 Hz';
      case RefreshRateOption.hz90:
        return '90 Hz';
      case RefreshRateOption.hz120:
        return '120 Hz';
    }
  }

  String get title {
    switch (this) {
      case RefreshRateOption.deviceDefault:
        return 'Device Default';
      case RefreshRateOption.hz60:
        return '60 Hz (Standard)';
      case RefreshRateOption.hz90:
        return '90 Hz (Smooth)';
      case RefreshRateOption.hz120:
        return '120 Hz (Ultra Fluid)';
    }
  }

  String get description {
    switch (this) {
      case RefreshRateOption.deviceDefault:
        return 'Uses the native device display setting and system adaptive refresh rate.';
      case RefreshRateOption.hz60:
        return 'Locks display to 60 Hz to maximize battery life.';
      case RefreshRateOption.hz90:
        return 'Locks display to 90 Hz for smooth scrolling while saving power.';
      case RefreshRateOption.hz120:
        return 'Locks display to 120 Hz for silky-smooth animations and responsiveness.';
    }
  }
}

/// Provider managing the screen refresh rate and device display modes
class RefreshRateProvider with ChangeNotifier {
  static const String _prefKey = 'screen_refresh_rate_preference';

  RefreshRateOption _selectedOption = RefreshRateOption.deviceDefault;
  List<DisplayMode> _supportedModes = const [];
  DisplayMode? _activeMode;
  bool _isSupportedOnPlatform = false;
  bool _isInitialized = false;

  RefreshRateOption get selectedOption => _selectedOption;
  List<DisplayMode> get supportedModes => _supportedModes;
  DisplayMode? get activeMode => _activeMode;
  bool get isSupportedOnPlatform => _isSupportedOnPlatform;
  bool get isInitialized => _isInitialized;

  RefreshRateProvider() {
    _checkPlatform();
  }

  void _checkPlatform() {
    // flutter_displaymode is an Android-specific API that configures WindowManager.LayoutParams
    _isSupportedOnPlatform = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  /// Initialize the provider, load saved preference, and apply the display mode
  Future<void> init() async {
    _checkPlatform();
    await _loadFromPrefs();

    if (_isSupportedOnPlatform) {
      await refreshDisplayModes();
      await _applyOptionToDisplay(_selectedOption);
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Refreshes the cached list of supported and active display modes
  Future<void> refreshDisplayModes() async {
    if (!_isSupportedOnPlatform) return;

    try {
      final modes = await FlutterDisplayMode.supported;
      _supportedModes = modes;
      _activeMode = await FlutterDisplayMode.active;
      notifyListeners();
    } catch (e) {
      debugPrint('RefreshRateProvider: Failed to query display modes: $e');
    }
  }

  /// Check if a specific target Hz is physically supported by the device screen
  bool isHzSupported(int targetHz) {
    if (!_isSupportedOnPlatform) return false;
    return _supportedModes.any(
      (m) =>
          (m.refreshRate.round() == targetHz) ||
          (m.refreshRate - targetHz).abs() < 2.0,
    );
  }

  /// Check if an option is supported on this device
  bool isOptionSupported(RefreshRateOption option) {
    if (option == RefreshRateOption.deviceDefault) return true;
    final hz = option.targetHz;
    if (hz == null) return true;
    return isHzSupported(hz);
  }

  /// Get list of all distinct refresh rates supported by the device (e.g. [60, 90, 120])
  List<int> get availableRefreshRates {
    if (!_isSupportedOnPlatform || _supportedModes.isEmpty) return const [];
    final rates = <int>{};
    for (final mode in _supportedModes) {
      if (mode.refreshRate > 0) {
        rates.add(mode.refreshRate.round());
      }
    }
    final sorted = rates.toList()..sort();
    return sorted;
  }

  /// Set the refresh rate preference, save to persistent storage, and apply to display
  Future<bool> setOption(RefreshRateOption option) async {
    _selectedOption = option;
    notifyListeners();

    // Persist choice to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, option.name);
    } catch (e) {
      debugPrint('RefreshRateProvider: Failed to save preference: $e');
    }

    // Apply the display mode to window
    final success = await _applyOptionToDisplay(option);
    return success;
  }

  /// Applies the selected option to the Android Window
  Future<bool> _applyOptionToDisplay(RefreshRateOption option) async {
    if (!_isSupportedOnPlatform) return true;

    try {
      switch (option) {
        case RefreshRateOption.deviceDefault:
          // DisplayMode.auto sets preferredDisplayModeId = 0, letting Android OS use native default
          await FlutterDisplayMode.setPreferredMode(DisplayMode.auto);
          break;

        case RefreshRateOption.hz60:
        case RefreshRateOption.hz90:
        case RefreshRateOption.hz120:
          final targetHz = option.targetHz!;
          final matchingMode = _findMatchingMode(targetHz);
          if (matchingMode != null) {
            await FlutterDisplayMode.setPreferredMode(matchingMode);
          } else {
            debugPrint(
              'RefreshRateProvider: Mode for ${targetHz}Hz not found in supported modes; falling back to auto.',
            );
            await FlutterDisplayMode.setPreferredMode(DisplayMode.auto);
            return false;
          }
          break;
      }

      // Update current active mode after switching
      try {
        _activeMode = await FlutterDisplayMode.active;
      } catch (_) {}

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('RefreshRateProvider: Error setting display mode: $e');
      return false;
    }
  }

  /// Finds the best matching display mode for a target refresh rate
  DisplayMode? _findMatchingMode(int targetHz) {
    if (_supportedModes.isEmpty) return null;

    final candidates = _supportedModes.where(
      (m) =>
          (m.refreshRate.round() == targetHz) ||
          (m.refreshRate - targetHz).abs() < 2.0,
    ).toList();

    if (candidates.isEmpty) return null;

    // Prefer matching current resolution (width x height)
    if (_activeMode != null && _activeMode!.width > 0 && _activeMode!.height > 0) {
      for (final mode in candidates) {
        if (mode.width == _activeMode!.width && mode.height == _activeMode!.height) {
          return mode;
        }
      }
    }

    // Otherwise choose the highest resolution candidate
    candidates.sort((a, b) {
      final resA = a.width * a.height;
      final resB = b.width * b.height;
      return resB.compareTo(resA);
    });

    return candidates.first;
  }

  /// Load preference from SharedPreferences
  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null) {
        for (final option in RefreshRateOption.values) {
          if (option.name == saved) {
            _selectedOption = option;
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('RefreshRateProvider: Error loading preferences: $e');
    }
    // Default to deviceDefault
    _selectedOption = RefreshRateOption.deviceDefault;
  }

  /// Formatted subtitle describing current state
  String get statusSubtitle {
    if (!_isSupportedOnPlatform) {
      return 'Managed automatically by OS display compositor';
    }

    final activeHz = _activeMode?.refreshRate;
    final activeText = activeHz != null && activeHz > 0
        ? ' (Active: ${activeHz.round()} Hz)'
        : '';

    switch (_selectedOption) {
      case RefreshRateOption.deviceDefault:
        return 'Device Default$activeText';
      case RefreshRateOption.hz60:
        return 'Locked to 60 Hz$activeText';
      case RefreshRateOption.hz90:
        return 'Locked to 90 Hz$activeText';
      case RefreshRateOption.hz120:
        return 'Locked to 120 Hz$activeText';
    }
  }
}
