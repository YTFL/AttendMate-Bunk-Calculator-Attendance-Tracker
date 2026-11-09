import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FileUtils {
  static const MethodChannel _channel = MethodChannel('com.attendmate.app/update');

  /// Open a file using Android's system viewer via FileProvider
  static Future<bool> openFile(String filePath) async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'openFile',
        {'filePath': filePath},
      );
      return result ?? false;
    } catch (e) {
      debugPrint('FileUtils: Error opening file: $e');
      return false;
    }
  }
}
