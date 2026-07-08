import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SwipeAction {
  present,
  absent;

  String get displayName {
    switch (this) {
      case SwipeAction.present:
        return 'Mark Present';
      case SwipeAction.absent:
        return 'Mark Absent';
    }
  }

  String get shortName {
    switch (this) {
      case SwipeAction.present:
        return 'Present';
      case SwipeAction.absent:
        return 'Absent';
    }
  }
}

class SwipeActionProvider with ChangeNotifier {
  static const String _leftActionKey = 'swipe_left_action';
  static const String _rightActionKey = 'swipe_right_action';

  SwipeAction _leftAction = SwipeAction.absent; // Default: Swipe Left to mark absent
  SwipeAction _rightAction = SwipeAction.present; // Default: Swipe Right to mark present
  bool _isInitialized = false;

  SwipeAction get leftAction => _leftAction;
  SwipeAction get rightAction => _rightAction;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final savedLeft = prefs.getString(_leftActionKey);
      if (savedLeft != null) {
        _leftAction = SwipeAction.values.firstWhere(
          (e) => e.name == savedLeft,
          orElse: () => SwipeAction.absent,
        );
      }

      final savedRight = prefs.getString(_rightActionKey);
      if (savedRight != null) {
        _rightAction = SwipeAction.values.firstWhere(
          (e) => e.name == savedRight,
          orElse: () => SwipeAction.present,
        );
      }
    } catch (e) {
      debugPrint('Failed to initialize SwipeActionProvider: $e');
    }
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setLeftAction(SwipeAction action) async {
    if (_leftAction == action) return;

    _leftAction = action;
    // Swap because they must be different
    _rightAction = action == SwipeAction.present ? SwipeAction.absent : SwipeAction.present;
    
    await _saveActionPreference(_leftActionKey, _leftAction);
    await _saveActionPreference(_rightActionKey, _rightAction);
    notifyListeners();
  }

  Future<void> setRightAction(SwipeAction action) async {
    if (_rightAction == action) return;

    _rightAction = action;
    // Swap because they must be different
    _leftAction = action == SwipeAction.present ? SwipeAction.absent : SwipeAction.present;

    await _saveActionPreference(_leftActionKey, _leftAction);
    await _saveActionPreference(_rightActionKey, _rightAction);
    notifyListeners();
  }

  Future<void> _saveActionPreference(String key, SwipeAction action) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, action.name);
    } catch (e) {
      debugPrint('Failed to save swipe action preference: $e');
    }
  }
}
