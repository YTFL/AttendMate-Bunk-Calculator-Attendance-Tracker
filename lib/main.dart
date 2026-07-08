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
import 'features/settings/setup_guide_screen.dart';
import 'features/settings/time_format_provider.dart';
import 'features/settings/swipe_action_provider.dart';
import 'features/subject/subject_provider.dart';
import 'services/database_service.dart';
import 'services/notification_service.dart';
import 'services/update_service.dart';

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
      }
      return true;
    } catch (e) {
      debugPrint('Background task failed: $e');
      return false;
    }
  });
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
      await databaseService.saveAttendance(mutableRecords);
    }
  } catch (e) {
    debugPrint('Background attendance marking failed: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
    await Workmanager().initialize(
      callbackDispatcher,
    );
    
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
        _showFirstLaunchPrompt();
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

  Future<void> _showFirstLaunchPrompt() async {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: isDarkMode
          ? Colors.white.withValues(alpha: 0.12)
          : null,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Welcome to AttendMate'),
          content: const Text(
            'Do you want to check the Setup Guide first, or start using the app directly?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SetupGuideScreen(),
                  ),
                );
              },
              child: const Text('Check Setup Guide'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Start Using App'),
            ),
          ],
        );
      },
    );
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
