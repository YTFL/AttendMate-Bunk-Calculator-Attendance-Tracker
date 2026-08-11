import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'semester_share_service.dart';

class AppFileIntentListener {
  static final AppFileIntentListener _instance = AppFileIntentListener._internal();
  factory AppFileIntentListener() => _instance;
  AppFileIntentListener._internal();

  static const MethodChannel _fileChannel = MethodChannel('com.attendmate.app/file_import');
  bool _isListening = false;
  bool _isProcessing = false;
  String? _lastContentHash;
  DateTime? _lastProcessedTime;
  BuildContext? _currentContext;

  void init(BuildContext context) {
    _currentContext = context;
    if (_isListening) return;
    _isListening = true;

    // Handle method calls from native Android layer when a file is opened
    _fileChannel.setMethodCallHandler((call) async {
      if (call.method == 'onFileOpened') {
        final payload = call.arguments;
        if (payload is Map) {
          _handleFilePayload(Map<String, dynamic>.from(payload));
        }
      }
    });

    // Check for initial file opened when app launches
    checkInitialOpenedFile();
  }

  void updateContext(BuildContext context) {
    _currentContext = context;
  }

  Future<void> checkInitialOpenedFile() async {
    try {
      final payload = await _fileChannel.invokeMethod<dynamic>('getInitialOpenedFile');
      if (payload != null && payload is Map) {
        _handleFilePayload(Map<String, dynamic>.from(payload));
      }
    } catch (_) {}
  }

  void _handleFilePayload(Map<String, dynamic> payload) {
    final ctx = _currentContext;
    if (ctx == null || !ctx.mounted) return;

    final bytesDynamic = payload['bytes'];
    String? content = payload['content'] as String?;

    if (content == null && bytesDynamic != null) {
      List<int> bytes = [];
      if (bytesDynamic is Uint8List) {
        bytes = bytesDynamic.toList();
      } else if (bytesDynamic is List) {
        bytes = bytesDynamic.cast<int>();
      }

      if (bytes.isNotEmpty) {
        try {
          content = utf8.decode(bytes);
        } catch (_) {
          content = latin1.decode(bytes, allowInvalid: true);
        }
      }
    }

    if (content != null && content.trim().isNotEmpty) {
      final trimmed = content.trim();
      final now = DateTime.now();

      // Deduplicate rapid duplicate intent triggers
      if (_isProcessing) return;
      if (_lastContentHash == trimmed &&
          _lastProcessedTime != null &&
          now.difference(_lastProcessedTime!).inSeconds < 3) {
        return;
      }

      _isProcessing = true;
      _lastContentHash = trimmed;
      _lastProcessedTime = now;

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final currentCtx = _currentContext;
          if (currentCtx != null && currentCtx.mounted) {
            await SemesterShareService().processOpenedJsonContent(trimmed, currentCtx);
          }
        } finally {
          _isProcessing = false;
        }
      });
    }
  }
}
