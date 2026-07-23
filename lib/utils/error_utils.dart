import 'package:flutter/services.dart';

/// Check if an exception represents a user cancellation action (e.g. back button in file picker)
bool isUserCancellation(Object e) {
  if (e is PlatformException) {
    final code = e.code.toUpperCase();
    final message = (e.message ?? '').toLowerCase();
    if (code == 'CANCELLED' || code == 'CANCELED' || code == 'CANCEL') return true;
    if (message.contains('cancelled') || message.contains('canceled') || message.contains('user cancelled')) return true;
  }
  final errStr = e.toString().toLowerCase();
  if (errStr.contains('platformexception(cancelled') || errStr.contains('platformexception(canceled')) return true;
  return false;
}

/// Format technical exceptions into clean, human-readable error messages for UI presentation
String formatUserFriendlyErrorMessage(Object e, {String defaultPrefix = 'Operation failed'}) {
  if (e is PlatformException) {
    final code = e.code.toUpperCase();
    final message = e.message ?? '';
    if (code == 'BUSY') {
      return 'A file selection is already in progress. Please try again.';
    }
    if (code == 'PERMISSION_DENIED' || code == 'PERMISSION_ERROR') {
      return 'Storage permission was denied. Please grant permission in settings.';
    }
    if (code == 'READ_ERROR') {
      return message.isNotEmpty ? 'Could not read file: $message' : 'Unable to access or read the selected file.';
    }
    if (code == 'WRITE_ERROR') {
      return message.isNotEmpty ? 'Could not write file: $message' : 'Unable to write backup file to the selected folder.';
    }
    if (code == 'DELETE_ERROR') {
      return message.isNotEmpty ? 'Could not delete file: $message' : 'Unable to delete backup file.';
    }
    if (code == 'NOT_FOUND') {
      return 'The selected file or folder could not be found.';
    }
    if (message.isNotEmpty && !message.contains('PlatformException')) {
      return '$defaultPrefix: $message';
    }
  }

  if (e is FormatException) {
    return 'The selected file is corrupted or is not a valid JSON file.';
  }

  if (e is TypeError) {
    return 'The selected file contains an invalid data structure.';
  }

  final str = e.toString();
  if (str.startsWith('Exception: ')) {
    return str.substring('Exception: '.length);
  }

  return '$defaultPrefix: $str';
}
