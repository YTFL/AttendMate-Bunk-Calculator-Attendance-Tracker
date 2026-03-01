import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../features/attendance/attendance_model.dart';
import '../features/subject/subject_model.dart';
import 'database_service.dart';

class AttendanceAction {
  final String subjectId;
  final DateTime date;
  final AttendanceStatus status;
  final String? slotKey;

  AttendanceAction({
    required this.subjectId,
    required this.date,
    required this.status,
    this.slotKey,
  });
}

class NavigationEvent {
  final String route;

  NavigationEvent({required this.route});
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final StreamController<AttendanceAction> _actionController =
      StreamController<AttendanceAction>.broadcast();
  final StreamController<NavigationEvent> _navigationController =
      StreamController<NavigationEvent>.broadcast();
  bool _initialized = false;
  final Set<int> _scheduledNotifications = {};
  final Map<int, String> _payloadMap = {}; // Store payloads by notification ID
  static const Duration _recentEndGrace = Duration(minutes: 5);

  Stream<AttendanceAction> get actionStream => _actionController.stream;
  Stream<NavigationEvent> get navigationStream => _navigationController.stream;

  Future<void> init() async {
    if (_initialized || kIsWeb) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('icon_noti');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    await _requestAndroidPermission();
    await _configureLocalTimeZone();

    _initialized = true;
  }

  Future<void> scheduleForSubjects(List<Subject> subjects) async {
    if (kIsWeb) {
      return;
    }

    await init();
    await _plugin.cancelAll();
    _scheduledNotifications.clear();
    _payloadMap.clear();

    final scheduleMode = await _androidScheduleMode();
    
    // Load all attendance records to check what's already marked
    final existingAttendance = await DatabaseService().loadAttendance();

    for (final subject in subjects) {
      for (final slot in subject.schedule) {
        final scheduleTime = _nextInstanceOfSlot(slot);
        final notificationId = _notificationId(subject.id, slot);
        
        // Skip if already scheduled in this session
        if (_scheduledNotifications.contains(notificationId)) {
          continue;
        }
        
        // Check if attendance is already marked for this subject on the scheduled date
        final scheduleDateOnly = DateTime(scheduleTime.year, scheduleTime.month, scheduleTime.day);
        final isAlreadyMarked = existingAttendance.any((record) =>
            record.subjectId == subject.id &&
          DateTime(record.date.year, record.date.month, record.date.day) == scheduleDateOnly &&
          (record.slotKey ?? '') == slot.slotKey
        );
        
        if (isAlreadyMarked) {
          continue;
        }

        final displayName = subject.acronym ?? '';

        final payload = jsonEncode({
          'subjectId': subject.id,
          'date': scheduleDateOnly.toIso8601String(),
          'slotKey': slot.slotKey,
        });

        try {
          await _plugin.zonedSchedule(
            notificationId,
            'Mark attendance',
            'Class ended: $displayName',
            scheduleTime,
            _notificationDetails(),
            androidScheduleMode: scheduleMode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: payload,
          );
          _scheduledNotifications.add(notificationId);
          _payloadMap[notificationId] = payload; // Store payload for action handling
        } catch (e) {
          // Silently fail - notification scheduling error
        }
      }
    }
  }

  NotificationDetails _notificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      'attendance_reminders',
      'Attendance reminders',
      channelDescription: 'Reminders to mark attendance after class ends',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'icon_noti',
      enableVibration: true,
      enableLights: true,
      playSound: true,
      actions: [
        AndroidNotificationAction(
          'mark_present',
          'Mark present',
          showsUserInterface: true,
          cancelNotification: false,
        ),
        AndroidNotificationAction(
          'mark_absent',
          'Mark absent',
          showsUserInterface: true,
          cancelNotification: false,
        ),
      ],
    );

    return const NotificationDetails(android: androidDetails);
  }

  tz.TZDateTime _nextInstanceOfSlot(TimeSlot slot) {
    final now = tz.TZDateTime.now(tz.local);
    final targetWeekday = slot.day.index + 1;

    if (now.weekday == targetWeekday) {
      final todayEnd = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        slot.endTime.hour,
        slot.endTime.minute,
      );
      
      if (!now.isAfter(todayEnd)) {
        return todayEnd;
      }
      
      final difference = now.difference(todayEnd);
      
      if (difference <= _recentEndGrace) {
        final immediate = now.add(const Duration(seconds: 5));
        return immediate;
      }
    }

    var daysToAdd = (targetWeekday - now.weekday) % 7;
    if (daysToAdd == 0) {
      daysToAdd = 7;
    }

    final nextDate = now.add(Duration(days: daysToAdd));
    final result = tz.TZDateTime(
      tz.local,
      nextDate.year,
      nextDate.month,
      nextDate.day,
      slot.endTime.hour,
      slot.endTime.minute,
    );
    return result;
  }

  int _notificationId(String subjectId, TimeSlot slot) {
    final key =
        '$subjectId-${slot.day.index}-${slot.startTime.hour}-${slot.startTime.minute}-${slot.endTime.hour}-${slot.endTime.minute}';
    return _stableId(key);
  }

  int _stableId(String input) {
    const int fnvPrime = 16777619;
    int hash = 2166136261;

    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * fnvPrime) & 0x7fffffff;
    }

    return hash;
  }

  Future<void> _configureLocalTimeZone() async {
    tz.initializeTimeZones();
    final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
    
    // Handle legacy timezone names
    var identifier = timeZoneInfo.identifier;
    if (identifier == 'Asia/Calcutta') {
      identifier = 'Asia/Kolkata';
    }
    
    tz.setLocalLocation(tz.getLocation(identifier));
  }

  Future<void> _requestAndroidPermission() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.requestNotificationsPermission();
    try {
      await androidPlugin?.requestExactAlarmsPermission();
    } catch (e) {
      // Silently fail - exact alarm permission is optional
    }
  }

  Future<AndroidScheduleMode> _androidScheduleMode() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final canScheduleExact = await androidPlugin?.canScheduleExactNotifications() ?? false;
    if (canScheduleExact) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    var payload = response.payload;
    
    // Handle notification tap (no action button pressed)
    if (response.actionId == null || response.actionId!.isEmpty) {
      _navigationController.add(NavigationEvent(route: '/today'));
      return;
    }
    
    // Handle action button taps
    if (response.actionId != 'mark_present' && response.actionId != 'mark_absent') {
      return;
    }

    // Try to get payload from stored map if not in response
    if ((payload == null || payload.isEmpty) && response.id != null) {
      payload = _payloadMap[response.id];
    }

    if (payload == null || payload.isEmpty) {
      return;
    }

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final subjectId = data['subjectId'] as String?;
      final dateString = data['date'] as String?;
      final slotKey = data['slotKey'] as String?;

      if (subjectId == null || dateString == null) {
        return;
      }

      final status = response.actionId == 'mark_present'
          ? AttendanceStatus.attended
          : AttendanceStatus.absent;

      final date = DateTime.parse(dateString);
      
      // Show confirmation notification
      final statusText = status == AttendanceStatus.attended ? 'Marked as Present' : 'Marked as Absent';
      _showConfirmationNotification(response.id ?? 0, statusText);
      
      // Emit action to mark attendance
      _actionController.add(
        AttendanceAction(
          subjectId: subjectId,
          date: date,
          status: status,
          slotKey: slotKey,
        ),
      );
      
      // Clean up payload from map
      if (response.id != null) {
        _payloadMap.remove(response.id);
      }
    } catch (e) {
      // Clean up even if there was an error
      if (response.id != null) {
        _payloadMap.remove(response.id);
      }
    }
  }

  Future<void> _showConfirmationNotification(int notificationId, String statusText) async {
    final confirmationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'attendance_reminders',
        'Attendance reminders',
        channelDescription: 'Reminders to mark attendance after class ends',
        importance: Importance.max,
        priority: Priority.high,
        icon: 'icon_noti',
        enableVibration: true,
        autoCancel: true,
      ),
    );

    try {
      await _plugin.show(
        notificationId,
        'Attendance',
        statusText,
        confirmationDetails,
      );
      
      // Auto-dismiss after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        _plugin.cancel(notificationId);
      });
    } catch (e) {
      // Silently fail - confirmation notification error
    }
  }
}
