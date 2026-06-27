import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
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
  final int? notificationId;

  AttendanceAction({
    required this.subjectId,
    required this.date,
    required this.status,
    this.slotKey,
    this.notificationId,
  });
}

class NavigationEvent {
  final String route;

  NavigationEvent({required this.route});
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  static const String actionPortName = 'attendance_action_port';

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

  Stream<AttendanceAction> get actionStream => _actionController.stream;
  Stream<NavigationEvent> get navigationStream => _navigationController.stream;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('icon_noti');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    await _requestAndroidPermission();
    await _configureLocalTimeZone();

    _initialized = true;
  }

  Future<void> scheduleForSubjects(List<Subject> subjects) async {
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
        if (scheduleTime == null) {
          continue;
        }
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
            id: notificationId,
            title: 'Mark attendance',
            body: 'Class ended: $displayName',
            scheduledDate: scheduleTime,
            notificationDetails: _notificationDetails(),
            androidScheduleMode: scheduleMode,
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
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'mark_absent',
          'Mark absent',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    return const NotificationDetails(android: androidDetails);
  }

  tz.TZDateTime? _nextInstanceOfSlot(TimeSlot slot) {
    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);

    if (slot.specificDate != null) {
      final scheduledDate = normalizeDate(slot.specificDate)!;
      if (scheduledDate.isBefore(today)) {
        return null;
      }

      final scheduledEnd = tz.TZDateTime(
        tz.local,
        scheduledDate.year,
        scheduledDate.month,
        scheduledDate.day,
        slot.endTime.hour,
        slot.endTime.minute,
      );

      if (now.isAfter(scheduledEnd)) {
        return null;
      }

      return scheduledEnd;
    }

    for (int dayOffset = 0; dayOffset <= 370; dayOffset++) {
      final candidateDateTime = now.add(Duration(days: dayOffset));
      final candidateDate = DateTime(
        candidateDateTime.year,
        candidateDateTime.month,
        candidateDateTime.day,
      );

      if (!slot.occursOnDate(candidateDate)) {
        continue;
      }

      final candidateEnd = tz.TZDateTime(
        tz.local,
        candidateDate.year,
        candidateDate.month,
        candidateDate.day,
        slot.endTime.hour,
        slot.endTime.minute,
      );

      if (dayOffset == 0 && now.isAfter(candidateEnd)) {
        continue;
      }

      return candidateEnd;
    }

    return null;
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

  Future<void> _handleNotificationResponse(NotificationResponse response) async {
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

      if (response.id != null) {
        await _plugin.cancel(id: response.id!);
      }
      
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
          notificationId: response.id,
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

  Future<void> showAttendanceMarkedNotification({
    required int notificationId,
    required AttendanceStatus status,
  }) async {
    final statusText = status == AttendanceStatus.attended ? 'Marked as Present' : 'Marked as Absent';
    await _showConfirmationNotification(notificationId, statusText);
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
        id: notificationId,
        title: 'Attendance',
        body: statusText,
        notificationDetails: confirmationDetails,
      );
      
      // Auto-dismiss after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        _plugin.cancel(id: notificationId);
      });
    } catch (e) {
      // Silently fail - confirmation notification error
    }
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  
  final payload = response.payload;
  if (payload == null || payload.isEmpty) {
    return;
  }

  if (response.actionId != 'mark_present' && response.actionId != 'mark_absent') {
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

    // Save attendance directly using DatabaseService
    final databaseService = DatabaseService();
    await databaseService.init();

    final records = await databaseService.loadAttendance();
    final mutableRecords = List<Attendance>.from(records);

    final normDate = DateTime(date.year, date.month, date.day);

    // Index existing records to find duplicates
    int matchIndex = -1;
    for (int i = 0; i < mutableRecords.length; i++) {
      final r = mutableRecords[i];
      final rNormDate = DateTime(r.date.year, r.date.month, r.date.day);
      if (r.subjectId == subjectId &&
          rNormDate == normDate &&
          (r.slotKey ?? '') == (slotKey ?? '')) {
        matchIndex = i;
        break;
      }
    }

    final newRecord = Attendance(
      subjectId: subjectId,
      date: date,
      status: status,
      slotKey: slotKey,
    );

    if (matchIndex != -1) {
      mutableRecords[matchIndex] = newRecord;
    } else {
      mutableRecords.add(newRecord);
    }

    await databaseService.saveAttendance(mutableRecords);

    final actionPort = IsolateNameServer.lookupPortByName(NotificationService.actionPortName);
    actionPort?.send({
      'type': 'attendance_marked',
      'subjectId': subjectId,
      'date': date.toIso8601String(),
      'slotKey': slotKey,
      'notificationId': response.id,
      'status': status.index,
    });

    // Dismiss the original notification
    final plugin = FlutterLocalNotificationsPlugin();
    if (response.id != null) {
      await plugin.cancel(id: response.id!);
    }

    // Show a confirmation notification
    final statusText = status == AttendanceStatus.attended ? 'Marked as Present' : 'Marked as Absent';
    
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

    if (response.id != null) {
      await plugin.show(
        id: response.id!,
        title: 'Attendance',
        body: statusText,
        notificationDetails: confirmationDetails,
      );
      
      // Auto-dismiss after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        plugin.cancel(id: response.id!);
      });
    }
  } catch (e) {
    debugPrint('Error in notificationTapBackground: $e');
  }
}
