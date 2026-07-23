import 'dart:isolate';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'features/attendance/attendance_model.dart';
import 'features/attendance/attendance_provider.dart';
import 'features/home/home_screen.dart';
import 'features/semester/semester_provider.dart';
import 'features/settings/time_format_provider.dart';
import 'features/settings/swipe_action_provider.dart';
import 'features/subject/subject_provider.dart';
import 'features/tutorial/tutorial_controller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'features/location/location_model.dart';
import 'services/database_service.dart';
import 'services/notification_service.dart';
import 'services/update_service.dart';
import 'services/backup_service.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Top-level function required by WorkManager for background tasks
/// This function runs in an isolate, so it must be a top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      // Initialize database in background context
      await DatabaseService().init();
      
      await DatabaseService().logAppEvent(
        tag: 'Workmanager',
        message: 'Task "$task" started with inputData: $inputData',
      );
      
      if (task == 'updateCheck') {
        if (kDebugMode) return true;
        // Check for updates
        final updateService = UpdateService();
        final shouldCheck = await updateService.shouldCheckForUpdate();
        if (shouldCheck) {
          await updateService.checkForUpdate();
        }
      } else if (task == 'endOfDayAttendanceCheck') {
        // Auto-mark all unmarked classes as present at end of day (or catch up previous days)
        final today = DateTime.now();
        final today0 = DateTime(today.year, today.month, today.day);
        await _performEndOfDayAttendanceMarking(today0);
      } else if (task == 'geofenceCheckTask') {
        final subjectId = inputData?['subjectId'] as String?;
        final locationId = inputData?['locationId'] as String?;
        final dateStr = inputData?['date'] as String?;
        final slotKey = inputData?['slotKey'] as String?;
        final subjectName = inputData?['subjectName'] as String?;
        final notificationId = inputData?['notificationId'] as int?;
        if (subjectId != null && locationId != null && dateStr != null) {
          final date = DateTime.parse(dateStr);
          await _performGeofenceCheck(subjectId, locationId, date, slotKey, subjectName, notificationId);
        } else {
          await DatabaseService().logAppEvent(
            tag: 'Workmanager',
            message: 'Geofence task aborted: missing subjectId, locationId, or date.',
            level: 'WARNING',
          );
        }
      } else if (task == 'dailySemesterBackup' || task == 'testBackgroundBackup' || task == 'appCloseBackupTask') {
        await BackupService().createBackup(
          showNotification: true,
          triggerReason: task == 'appCloseBackupTask'
              ? '15-minute app exit auto-backup'
              : task == 'testBackgroundBackup'
                  ? '30s Debug Test Backup'
                  : 'Daily 10 PM background backup',
          force: task == 'testBackgroundBackup',
        );
      }
      return true;
    } catch (e) {
      debugPrint('Background task failed: $e');
      try {
        await DatabaseService().logAppEvent(
          tag: 'Workmanager',
          message: 'Background task failed: $e',
          level: 'ERROR',
        );
      } catch (_) {}
      return false;
    }
  });
}

@pragma('vm:entry-point')
Future<void> _performGeofenceCheck(
  String subjectId,
  String locationId,
  DateTime date,
  String? slotKey,
  String? subjectName,
  int? notificationId,
) async {
  final db = DatabaseService();
  try {
    await db.logAppEvent(
      tag: 'Geofence',
      message: 'Starting check for subject: $subjectName ($subjectId), locationId: $locationId',
    );

    // Load the specific location configuration
    final locations = await db.loadLocations();
    LocationConfig? targetLocation;
    for (final loc in locations) {
      if (loc.id == locationId) {
        targetLocation = loc;
        break;
      }
    }
    
    if (targetLocation == null) {
      await db.logAppEvent(
        tag: 'Geofence',
        message: 'Aborted: Target location configuration not found in DB.',
        level: 'ERROR',
      );
      return;
    }

    if (targetLocation.latitude == null || targetLocation.longitude == null) {
      await db.logAppEvent(
        tag: 'Geofence',
        message: 'Aborted: Location "${targetLocation.name}" has no coordinates configured.',
        level: 'ERROR',
      );
      return;
    }

    await db.logAppEvent(
      tag: 'Geofence',
      message: 'Target location: "${targetLocation.name}" at (${targetLocation.latitude}, ${targetLocation.longitude})',
    );

    // Check location permission before fetching GPS
    final permission = await Geolocator.checkPermission();
    await db.logAppEvent(
      tag: 'Geofence',
      message: 'Current background permission level: $permission',
    );

    if (permission != LocationPermission.always) {
      await db.logAppEvent(
        tag: 'Geofence',
        message: 'Aborted: Background location permission ("Allow all the time") is required (current: $permission).',
        level: 'ERROR',
      );
      return;
    }

    // Fetch current coordinates
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      await db.logAppEvent(
        tag: 'Geofence',
        message: 'Retrieved GPS: (${position.latitude}, ${position.longitude}) with accuracy ${position.accuracy}m',
      );
    } catch (e) {
      await db.logAppEvent(
        tag: 'Geofence',
        message: 'Failed to fetch current GPS coordinates: $e. Attempting last known position...',
        level: 'WARNING',
      );
      
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown == null) {
        await db.logAppEvent(
          tag: 'Geofence',
          message: 'Aborted: Last known position was also null.',
          level: 'ERROR',
        );
        return;
      }
      position = lastKnown;
      await db.logAppEvent(
        tag: 'Geofence',
        message: 'Using last known GPS: (${position.latitude}, ${position.longitude})',
      );
    }

    // Calculate distance
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      targetLocation.latitude!,
      targetLocation.longitude!,
    );

    await db.logAppEvent(
      tag: 'Geofence',
      message: 'Distance to class location is ${distance.toStringAsFixed(2)} meters.',
    );

    // 25m radius — accounts for room-level proximity
    if (distance <= 25.0) {
      final records = await db.loadAttendance();
      final normDate = DateTime(date.year, date.month, date.day);

      // Check if already marked
      final alreadyMarked = records.any((r) {
        final rNorm = DateTime(r.date.year, r.date.month, r.date.day);
        return r.subjectId == subjectId &&
            rNorm == normDate &&
            (r.slotKey ?? '') == (slotKey ?? '');
      });

      if (alreadyMarked) {
        await db.logAppEvent(
          tag: 'Geofence',
          message: 'Attendance already marked for today/slot. Skipping auto-marking.',
        );
        return;
      }

      final newRecord = Attendance(
        subjectId: subjectId,
        date: date,
        status: AttendanceStatus.attended,
        slotKey: slotKey,
      );
      await db.saveSingleAttendance(newRecord);
      await db.logAppEvent(
        tag: 'Geofence',
        message: 'Auto-marked subject "$subjectName" as ATTENDED.',
      );

      // Notify main isolate if active (no-op if app is closed)
      final actionPort = IsolateNameServer.lookupPortByName(
          NotificationService.actionPortName);
      if (actionPort != null) {
        actionPort.send({
          'type': 'attendance_marked',
          'subjectId': subjectId,
          'date': date.toIso8601String(),
          'slotKey': slotKey,
          'notificationId': notificationId,
          'status': AttendanceStatus.attended.index,
        });
        await db.logAppEvent(
          tag: 'Geofence',
          message: 'Sent attendance_marked event to main isolate.',
        );
      } else {
        await db.logAppEvent(
          tag: 'Geofence',
          message: 'Main isolate not running (app closed). Notification not sent via port.',
        );
      }

      // Initialize notification plugin in the background isolate
      const androidSettings = AndroidInitializationSettings('icon_noti');
      const initSettings = InitializationSettings(android: androidSettings);
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(settings: initSettings);

      // Cancel the end-of-class "mark attendance" reminder
      if (notificationId != null) {
        await plugin.cancel(id: notificationId);
        await db.logAppEvent(
          tag: 'Geofence',
          message: 'Cancelled original end-of-class reminder notification (ID: $notificationId).',
        );
      }

      // Show confirmation notification
      const confirmationDetails = NotificationDetails(
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
      
      await plugin.show(
        id: notificationId ?? 999999,
        title: 'Auto-Attendance Marked ✓',
        body: '${subjectName ?? "Class"} marked Present (you were nearby)',
        notificationDetails: confirmationDetails,
      );
      await db.logAppEvent(
        tag: 'Geofence',
        message: 'Displayed Auto-Attendance confirmation notification.',
      );
    } else {
      await db.logAppEvent(
        tag: 'Geofence',
        message: 'You are outside the 25-meter range (${distance.toStringAsFixed(2)}m). Auto-marking skipped.',
      );
    }
  } catch (e) {
    await db.logAppEvent(
      tag: 'Geofence',
      message: 'Uncaught error in geofence check: $e',
      level: 'ERROR',
    );
  }
}

/// Helper function to perform end-of-day attendance marking
/// This is a top-level function so it can be called from the callback dispatcher
@pragma('vm:entry-point')
Future<void> _performEndOfDayAttendanceMarking(DateTime todayDate) async {
  try {
    final databaseService = DatabaseService();
    final semester = await databaseService.loadSemester();
    if (semester == null) return;

    final subjects = await databaseService.loadSubjects();
    if (subjects.isEmpty) return;

    final records = await databaseService.loadAttendance();
    final mutableRecords = List<Attendance>.from(records);

    // Index records by composite key: subjectId_dateEpoch_slotKey
    final Map<String, Attendance> indexedRecords = {};
    // Index records by date to check isHoliday in O(1)
    final Map<DateTime, List<Attendance>> recordsByDate = {};

    for (final record in mutableRecords) {
      final normDate = DateTime(record.date.year, record.date.month, record.date.day);
      final key = '${record.subjectId}_${normDate.millisecondsSinceEpoch}_${record.slotKey ?? ""}';
      indexedRecords[key] = record;
      recordsByDate.putIfAbsent(normDate, () => []).add(record);
    }

    bool changed = false;

    // 1. First, check and mark all past days (from semester start up to yesterday)
    DateTime checkFromDate = DateTime(semester.startDate.year, semester.startDate.month, semester.startDate.day);
    for (DateTime date = checkFromDate;
        date.isBefore(todayDate);
        date = date.add(const Duration(days: 1))) {
      
      // Skip if holiday
      final recordsForDay = recordsByDate[date];
      if (recordsForDay != null && recordsForDay.isNotEmpty && recordsForDay.every((r) => r.status == AttendanceStatus.cancelled)) {
        continue;
      }

      for (final subject in subjects) {
        final slotsForDay = subject.schedule.where((slot) => slot.occursOnDate(date)).toList();
        for (final slot in slotsForDay) {
          final key = '${subject.id}_${date.millisecondsSinceEpoch}_${slot.slotKey}';
          if (!indexedRecords.containsKey(key)) {
            final newRecord = Attendance(
              subjectId: subject.id,
              date: date,
              status: AttendanceStatus.attended,
              slotKey: slot.slotKey,
            );
            mutableRecords.add(newRecord);
            indexedRecords[key] = newRecord;
            recordsByDate.putIfAbsent(date, () => []).add(newRecord);
            changed = true;
          }
        }
      }
    }

    // 2. Secondly, if today is late enough (after 10 PM), check and mark today as well
    final now = DateTime.now();
    if (now.hour >= 22) {
      final recordsForDay = recordsByDate[todayDate];
      final isHoliday = recordsForDay != null && recordsForDay.isNotEmpty && recordsForDay.every((r) => r.status == AttendanceStatus.cancelled);
      
      if (!isHoliday) {
        for (final subject in subjects) {
          final slotsForDay = subject.schedule.where((slot) => slot.occursOnDate(todayDate)).toList();
          for (final slot in slotsForDay) {
            final key = '${subject.id}_${todayDate.millisecondsSinceEpoch}_${slot.slotKey}';
            if (!indexedRecords.containsKey(key)) {
              final newRecord = Attendance(
                subjectId: subject.id,
                date: todayDate,
                status: AttendanceStatus.attended,
                slotKey: slot.slotKey,
              );
              mutableRecords.add(newRecord);
              indexedRecords[key] = newRecord;
              recordsByDate.putIfAbsent(todayDate, () => []).add(newRecord);
              changed = true;
            }
          }
        }
      }
    }

    if (changed) {
      final originalKeys = records.map((r) {
        final normDate = DateTime(r.date.year, r.date.month, r.date.day);
        return '${r.subjectId}_${normDate.millisecondsSinceEpoch}_${r.slotKey ?? ""}';
      }).toSet();

      final newRecords = mutableRecords.where((r) {
        final normDate = DateTime(r.date.year, r.date.month, r.date.day);
        final key = '${r.subjectId}_${normDate.millisecondsSinceEpoch}_${r.slotKey ?? ""}';
        return !originalKeys.contains(key);
      }).toList();

      if (newRecords.isNotEmpty) {
        await databaseService.saveMultipleAttendanceIncremental(newRecords);
      }
    }
  } catch (e) {
    debugPrint('Background attendance marking failed: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Android Google Maps Renderer Surface
  try {
    final GoogleMapsFlutterPlatform mapsImplementation = GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is GoogleMapsFlutterAndroid) {
      mapsImplementation.useAndroidViewSurface = true;
      mapsImplementation.initializeWithRenderer(AndroidMapRenderer.latest);
    }
  } catch (e) {
    debugPrint('Google Maps renderer initialization note: $e');
  }
  
  // Global error handler to catch any unhandled exceptions
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('Flutter Error: ${details.exception}');
    debugPrintStack(stackTrace: details.stack);
  };
  
  // Initialize SQLite database with error handling
  bool databaseInitialized = false;
  String? databaseErrorMessage;
  
  try {
    await DatabaseService().init();
    databaseInitialized = true;
  } catch (e) {
    debugPrint('Database initialization failed: $e');
    databaseErrorMessage = e.toString();
  }

  // Initialize WorkManager for background update checks
  try {
    await Workmanager().initialize(callbackDispatcher);
    
    // Register periodic task: check for updates once daily
    if (!kDebugMode) {
      await Workmanager().registerPeriodicTask(
        'app_update_check',
        'updateCheck',
        frequency: const Duration(days: 1),
        initialDelay: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        constraints: Constraints(
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          networkType: NetworkType.connected,
        ),
      );
    }

    // Register periodic task: auto-mark unmarked classes at end of day
    await Workmanager().registerPeriodicTask(
      'end_of_day_attendance_check',
      'endOfDayAttendanceCheck',
      frequency: const Duration(days: 1),
      initialDelay: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        networkType: NetworkType.notRequired,
      ),
    );

    // Register periodic task: daily semester backup at 10:00 PM
    final now = DateTime.now();
    var backupTargetTime = DateTime(now.year, now.month, now.day, 22, 0, 0);
    if (now.isAfter(backupTargetTime)) {
      backupTargetTime = backupTargetTime.add(const Duration(days: 1));
    }
    final backupInitialDelay = backupTargetTime.difference(now);

    await Workmanager().registerPeriodicTask(
      'daily_semester_backup',
      'dailySemesterBackup',
      frequency: const Duration(days: 1),
      initialDelay: backupInitialDelay,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        networkType: NetworkType.notRequired,
      ),
    );
  } catch (e) {
    debugPrint('WorkManager initialization failed: $e');
  }

  // Track database initialization status
  if (!databaseInitialized) {
    // Show error screen if database failed to initialize
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 24),
                  const Text(
                    'Unable to Start App',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'The database failed to initialize. Please try the following:\n\n'
                    '1. Uninstall the app completely\n'
                    '2. Restart your phone\n'
                    '3. Reinstall the app from Google Play Store\n\n'
                    'If this error persists, please contact support.',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Error Details: $databaseErrorMessage',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  // Only create providers if database is initialized
  final attendanceProvider = AttendanceProvider();
  final timeFormatProvider = TimeFormatProvider();
  final swipeActionProvider = SwipeActionProvider();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => timeFormatProvider),
        ChangeNotifierProvider(create: (context) => swipeActionProvider),
        ChangeNotifierProvider(create: (context) => SemesterProvider()),
        ChangeNotifierProvider(create: (context) => attendanceProvider),
        ChangeNotifierProvider(
          create: (context) => SubjectProvider(attendanceProvider),
        ),
        ChangeNotifierProvider(create: (context) => TutorialController()),
      ],
      child: MyApp(
        timeFormatProvider: timeFormatProvider,
        swipeActionProvider: swipeActionProvider,
      ),
    ),
  );

  unawaited(
    () async {
      try {
        final notificationService = NotificationService();
        await notificationService.init();

        final receivePort = ReceivePort();
        IsolateNameServer.removePortNameMapping(NotificationService.actionPortName);
        IsolateNameServer.registerPortWithName(
          receivePort.sendPort,
          NotificationService.actionPortName,
        );

        receivePort.listen((message) async {
          if (message is! Map) {
            return;
          }

          final data = message.cast<String, dynamic>();
          if (data['type'] != 'attendance_marked') {
            return;
          }

          await attendanceProvider.reloadAttendance();
        });
        
        // Listen for attendance action button taps
        notificationService.actionStream.listen((action) async {
          try {
            await attendanceProvider
                .markAttendance(
                  action.subjectId,
                  action.date,
                  action.status,
                  slotKey: action.slotKey,
                );

            if (action.notificationId != null) {
              await notificationService.showAttendanceMarkedNotification(
                notificationId: action.notificationId!,
                subjectId: action.subjectId,
                status: action.status,
              );
            }
          } catch (e) {
            // Silently fail - navigation error
          }
        });
        
        // Listen for notification taps
        notificationService.navigationStream.listen((navigationEvent) {
          final navigatorState = navigatorKey.currentState;
          if (navigatorState == null || !navigatorState.mounted) {
            return;
          }
          if (navigationEvent.route == '/today') {
            // Navigate to HomeScreen with Today page (index 0)
            navigatorState.pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => const HomeScreen(initialPageIndex: 0),
              ),
              (route) => false,
            );
          }
        });
      } catch (e) {
        // Silently fail - notification service initialization error
      }
    }(),
  );
}

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }
    _themeMode = mode;
    notifyListeners();
  }

  void toggleTheme() {
    setThemeMode(_themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);
  }

  void setSystemTheme() {
    setThemeMode(ThemeMode.system);
  }
}

class FirstLaunchGate extends StatefulWidget {
  const FirstLaunchGate({super.key});

  @override
  State<FirstLaunchGate> createState() => _FirstLaunchGateState();
}

class _FirstLaunchGateState extends State<FirstLaunchGate> {
  static const String _hasSeenSetupPromptKey = 'has_seen_setup_prompt';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initFirstLaunchFlow();
  }

  Future<void> _initFirstLaunchFlow() async {
    bool shouldShowPrompt = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenPrompt = prefs.getBool(_hasSeenSetupPromptKey) ?? false;

      if (!hasSeenPrompt) {
        if (!kDebugMode) {
          shouldShowPrompt = true;
          await prefs.setBool(_hasSeenSetupPromptKey, true);
        }
      }

      // Mark previous days' attendance as present (fallback for missed end-of-day markings)
      await _markPreviousDaysAttendance();
    } catch (_) {
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
    });

    if (shouldShowPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        Provider.of<TutorialController>(context, listen: false).startTutorial();
      });
    }
  }

  /// Mark attendance for previous unmarked days as a fallback
  /// This runs when the app starts to handle cases where end-of-day marking didn't work
  Future<void> _markPreviousDaysAttendance() async {
    try {
      // Wait a moment for providers to be initialized
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) {
        return;
      }

      // Get providers from context
      final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
      final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
      final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);

      // Only run if semester is set and has started
      if (semesterProvider.semester == null || !semesterProvider.hasSemesterStarted) {
        return;
      }

      // Wait for subjects to load
      int attempts = 0;
      while (subjectProvider.isLoading && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      // Mark previous days' attendance
      await attendanceProvider.markPreviousDaysAttendanceAsPresent(
        semesterStartDate: semesterProvider.semester!.startDate,
        subjects: subjectProvider.subjects,
      );

      debugPrint('Previous days attendance marked successfully');
    } catch (e) {
      debugPrint('Error in fallback attendance marking: $e');
      // Silently fail - this is a non-critical operation
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return const HomeScreen(initialPageIndex: 0);
  }
}

class MyApp extends StatelessWidget {
  final TimeFormatProvider timeFormatProvider;
  final SwipeActionProvider swipeActionProvider;

  const MyApp({
    super.key,
    required this.timeFormatProvider,
    required this.swipeActionProvider,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme appTextTheme = TextTheme(
      displayLarge: GoogleFonts.oswald(fontSize: 57, fontWeight: FontWeight.bold),
      titleLarge: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.w500),
      bodyMedium: GoogleFonts.openSans(fontSize: 14),
    ).apply(bodyColor: Colors.black, displayColor: Colors.black);

    final ThemeData lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: Colors.black,
        onPrimary: Colors.white,
        secondary: Colors.black,
        onSecondary: Colors.white,
        error: Colors.red,
        onError: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
      ),
      textTheme: appTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.oswald(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: GoogleFonts.roboto(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.grey,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        elevation: 6,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        headerBackgroundColor: Colors.black,
        headerForegroundColor: Colors.white,
        headerHeadlineStyle: GoogleFonts.roboto(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        headerHelpStyle: GoogleFonts.roboto(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white70,
        ),
        weekdayStyle: GoogleFonts.roboto(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
        dayStyle: GoogleFonts.roboto(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        dayShape: WidgetStateProperty.all<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.black;
          }
          return null;
        }),
        dayForegroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          if (states.contains(WidgetState.disabled)) {
            return Colors.grey.shade400;
          }
          return Colors.black;
        }),
        todayBackgroundColor: WidgetStateProperty.all(Colors.transparent),
        todayForegroundColor: WidgetStateProperty.all(Colors.black),
        todayBorder: const BorderSide(color: Colors.black, width: 1.8),
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: Colors.grey.shade700,
          textStyle: GoogleFonts.roboto(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: Colors.black,
          textStyle: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );

    final ThemeData darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: Colors.white,
        onPrimary: Colors.black,
        secondary: Colors.white,
        onSecondary: Colors.black,
        error: Colors.red,
        onError: Colors.black,
        surface: Colors.black,
        onSurface: Colors.white,
      ),
      textTheme: appTextTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.oswald(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.black,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: GoogleFonts.roboto(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.black,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey,
      ),
      dialogTheme: DialogThemeData(
        barrierColor: Colors.white.withValues(alpha: 0.12),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
        ),
        headerBackgroundColor: Colors.black,
        headerForegroundColor: Colors.white,
        headerHeadlineStyle: GoogleFonts.roboto(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        headerHelpStyle: GoogleFonts.roboto(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white70,
        ),
        weekdayStyle: GoogleFonts.roboto(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.white70,
        ),
        dayStyle: GoogleFonts.roboto(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        dayShape: WidgetStateProperty.all<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return null;
        }),
        dayForegroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.black;
          }
          if (states.contains(WidgetState.disabled)) {
            return Colors.white24;
          }
          return Colors.white;
        }),
        todayBackgroundColor: WidgetStateProperty.all(Colors.transparent),
        todayForegroundColor: WidgetStateProperty.all(Colors.white),
        todayBorder: const BorderSide(color: Colors.white, width: 1.8),
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: Colors.grey.shade400,
          textStyle: GoogleFonts.roboto(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        // Initialize TimeFormatProvider and SwipeActionProvider on first build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!timeFormatProvider.isInitialized) {
            timeFormatProvider.init(context);
          }
          if (!swipeActionProvider.isInitialized) {
            swipeActionProvider.init();
          }
        });

        return MaterialApp(
          title: 'AttendMate',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeProvider.themeMode,
          navigatorKey: navigatorKey,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final systemScale = mediaQuery.textScaler.scale(1.0);
            final clampedScale = systemScale.clamp(0.9, 1.25);

            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(clampedScale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const FirstLaunchGate(),
        );
      },
    );
  }
}
