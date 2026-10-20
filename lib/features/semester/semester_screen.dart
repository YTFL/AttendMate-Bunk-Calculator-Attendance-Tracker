import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/database_service.dart';
import '../../services/semester_share_service.dart';
import '../../utils/attendance_math.dart';
import '../../utils/error_utils.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../planner/planned_leave_model.dart';
import '../planner/projected_attendance_calculator.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';
import 'semester_model.dart';
import 'semester_provider.dart';
import '../tutorial/tutorial_controller.dart';

class SemesterScreen extends StatefulWidget {
  const SemesterScreen({super.key});

  @override
  State<SemesterScreen> createState() => _SemesterScreenState();
}

class _SemesterScreenState extends State<SemesterScreen> {
  final _formKey = GlobalKey<FormState>();
  final GlobalKey _setupFormKey = GlobalKey();
  DateTime? _startDate;
  DateTime? _endDate;
  double? _targetPercentage;
  late TextEditingController _targetPercentageController;
  List<PlannedLeave> _plannedLeaves = [];

  @override
  void initState() {
    super.initState();
    _targetPercentage = 75.0;
    _targetPercentageController = TextEditingController(text: '75');
    _loadPlannedLeaves();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final semester = Provider.of<SemesterProvider>(context, listen: false).semester;
    if (semester != null) {
      _startDate = semester.startDate;
      _endDate = semester.endDate;
      _targetPercentage = semester.targetPercentage;
      _targetPercentageController.text = semester.targetPercentage.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _targetPercentageController.dispose();
    super.dispose();
  }

  Future<void> _loadPlannedLeaves() async {
    final leaves = await DatabaseService().loadPlannedLeaves();
    if (mounted) {
      setState(() {
        _plannedLeaves = leaves;
      });
    }
  }

  Future<void> _saveSemesterParameters({
    required DateTime startDate,
    required DateTime endDate,
    required double targetPercentage,
  }) async {
    if (!endDate.isAfter(startDate)) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(content: Text('End date must be after start date.')),
      );
      return;
    }
    final updatedSemester = Semester(
      startDate: startDate,
      endDate: endDate,
      targetPercentage: targetPercentage,
    );
    try {
      await Provider.of<SemesterProvider>(
        context,
        listen: false,
      ).updateSemester(updatedSemester);
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(
          context,
          'Failed to update semester: ${formatUserFriendlyErrorMessage(e)}',
        );
      }
    }
  }

  Future<void> _createSemesterFromSetup() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(content: Text('Please select both start date and end date.')),
      );
      return;
    }
    if (!_endDate!.isAfter(_startDate!)) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(content: Text('End date must be after start date.')),
      );
      return;
    }
    final target = _targetPercentage ?? 75.0;
    final newSemester = Semester(
      startDate: _startDate!,
      endDate: _endDate!,
      targetPercentage: target,
    );
    try {
      await Provider.of<SemesterProvider>(
        context,
        listen: false,
      ).createNewSemester(newSemester);

      if (!mounted) return;
      final tutorialController = Provider.of<TutorialController>(context, listen: false);
      if (tutorialController.isActive && tutorialController.currentStepIndex <= 2) {
        tutorialController.nextStep();
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(
          context,
          'Failed to create semester: ${formatUserFriendlyErrorMessage(e)}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    tutorialController.registerKey('btn_setup_semester', _setupFormKey);

    final semesterProvider = Provider.of<SemesterProvider>(context);

    Widget content;
    if (semesterProvider.isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (semesterProvider.semester == null) {
      content = _buildCreateSemesterForm();
    } else {
      content = _buildSemesterDetails();
    }

    return content;
  }

  Widget _buildCreateSemesterForm() {
    final rs = context.rs;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        left: rs.width(16),
        right: rs.width(16),
        top: rs.height(12),
        bottom: rs.height(100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyedSubtree(
            key: _setupFormKey,
            child: Container(
              padding: EdgeInsets.all(rs.scale(20)),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? const Color(0xFF14141A)
                    : Colors.white,
                borderRadius: BorderRadius.circular(rs.scale(26)),
                border: Border.all(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.30 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: rs.scale(46),
                        height: rs.scale(46),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(rs.scale(16)),
                        ),
                        child: Icon(
                          Icons.school_rounded,
                          size: rs.scale(26),
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      SizedBox(width: rs.width(12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Setup Semester',
                              style: TextStyle(
                                fontSize: rs.font(20),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: rs.height(2)),
                            Text(
                              'Enter dates and target percentage',
                              style: TextStyle(
                                fontSize: rs.font(12),
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: rs.height(20)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildDatePickerField(
                          title: 'Start Date',
                          date: _startDate,
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                              helpText: 'Select Start Date',
                            );
                            if (date != null) {
                              final bool willBeNull = _endDate == null || !_endDate!.isAfter(date);
                              setState(() {
                                _startDate = date;
                                if (_endDate != null && !_endDate!.isAfter(date)) {
                                  _endDate = null;
                                }
                              });
                              if (willBeNull && mounted) {
                                final firstAllowed = date.add(const Duration(days: 1));
                                final endDate = await showDatePicker(
                                  context: context,
                                  initialDate: firstAllowed,
                                  firstDate: firstAllowed,
                                  lastDate: DateTime(2100),
                                  helpText: 'Select End Date',
                                );
                                if (endDate != null) {
                                  setState(() {
                                    _endDate = endDate;
                                  });
                                }
                              }
                            }
                          },
                        ),
                      ),
                      SizedBox(width: rs.width(12)),
                      Expanded(
                        child: _buildDatePickerField(
                          title: 'End Date',
                          date: _endDate,
                          onPressed: _startDate == null
                              ? null
                              : () async {
                                  final firstAllowed = _startDate!.add(
                                    const Duration(days: 1),
                                  );
                                  final initial =
                                      _endDate != null && _endDate!.isAfter(_startDate!)
                                      ? _endDate!
                                      : firstAllowed;
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: initial,
                                    firstDate: firstAllowed,
                                    lastDate: DateTime(2100),
                                    helpText: 'Select End Date',
                                  );
                                  if (date != null) {
                                    setState(() {
                                      _endDate = date;
                                    });
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: rs.height(16)),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: rs.width(16),
                      vertical: rs.height(12),
                    ),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                          : theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(rs.scale(18)),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.track_changes_rounded,
                                  size: rs.scale(20),
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                                SizedBox(width: rs.width(12)),
                                Text(
                                  'Target Percentage',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: rs.font(14),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: rs.width(10),
                                vertical: rs.height(4),
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(rs.scale(14)),
                              ),
                              child: Text(
                                '${(_targetPercentage ?? 75).round()}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: rs.font(14),
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: (_targetPercentage ?? 75).clamp(50.0, 100.0),
                          min: 50,
                          max: 100,
                          divisions: 50,
                          label: '${(_targetPercentage ?? 75).round()}%',
                          onChanged: (val) {
                            final newTarget = val.roundToDouble();
                            if (newTarget != _targetPercentage) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _targetPercentage = newTarget;
                                _targetPercentageController.text = newTarget.toStringAsFixed(0);
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: rs.height(20)),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _createSemesterFromSetup,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(rs.scale(24)),
                        ),
                        padding: EdgeInsets.symmetric(vertical: rs.height(14)),
                      ),
                      child: Text(
                        'Create Semester',
                        style: TextStyle(
                          fontSize: rs.font(15),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: rs.height(12)),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _importSharedSemesterFile(context),
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('Import Classmate\'s Semester'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(rs.scale(24)),
                        ),
                        side: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.14),
                          width: 0.9,
                        ),
                        padding: EdgeInsets.symmetric(vertical: rs.height(14)),
                      ),
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSemesterDetails() {
    final rs = context.rs;
    final semesterProvider = Provider.of<SemesterProvider>(
      context,
      listen: false,
    );
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final attendanceProvider = Provider.of<AttendanceProvider>(context);
    final bool semesterEnded = semesterProvider.hasSemesterEnded;
    final semester = semesterProvider.semester!;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(
        left: rs.width(16),
        right: rs.width(16),
        top: rs.height(8),
        bottom: rs.height(100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [


          // 1. Unified Hero Header Card (Fills from the top)
          _buildHeroHeader(
            semester: semester,
            semesterProvider: semesterProvider,
            subjectProvider: subjectProvider,
            attendanceProvider: attendanceProvider,
          ),
          SizedBox(height: rs.height(14)),

          // 2. Integrated Metrics Grid (8 Stat Tiles)
          _buildMetricsGrid(
            semester: semester,
            semesterProvider: semesterProvider,
            subjectProvider: subjectProvider,
            attendanceProvider: attendanceProvider,
          ),
          SizedBox(height: rs.height(14)),

          // 4. Seamless Semester Parameters Section (Dates & Target %)
          _buildSemesterParametersCard(semester),

          // 5. Semester Ended Warning / New Semester Trigger
          if (semesterEnded) ...[
            SizedBox(height: rs.height(14)),
            _buildSemesterEndedAlert(),
          ],
        ],
      ),
    );
  }



  Future<void> _importSharedSemesterFile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await const MethodChannel('com.attendmate.app/file_import').invokeMethod<dynamic>('pickImportFile');
      if (result == null) return;
      if (result is! Map) {
        throw Exception('Invalid file picker response.');
      }

      final bytesDynamic = result['bytes'];
      List<int> bytes = [];
      if (bytesDynamic is Uint8List) {
        bytes = bytesDynamic.toList();
      } else if (bytesDynamic is List) {
        bytes = bytesDynamic.cast<int>();
      }

      if (bytes.isEmpty) {
        throw Exception('Selected file is empty.');
      }

      String content;
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        content = latin1.decode(bytes, allowInvalid: true);
      }

      if (!context.mounted) return;
      await SemesterShareService().processOpenedJsonContent(content, context);
    } catch (e) {
      if (!context.mounted) return;
      if (isUserCancellation(e)) return;
      messenger.showReplacingSnackBar(
        SnackBar(
          content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to import file')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildHeroHeader({
    required Semester semester,
    required SemesterProvider semesterProvider,
    required SubjectProvider subjectProvider,
    required AttendanceProvider attendanceProvider,
  }) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final subjects = subjectProvider.subjects;

    final startDateStr = DateFormat.yMMMd().format(semester.startDate);
    final endDateStr = DateFormat.yMMMd().format(semester.endDate);

    if (!semesterProvider.hasSemesterStarted || subjects.isEmpty) {
      return Container(
        padding: EdgeInsets.all(rs.scale(18)),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF14141C).withValues(alpha: 0.65)
              : Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(rs.scale(18)),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.60),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDarkMode ? 0.30 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.school_rounded,
                      color: theme.colorScheme.primary,
                      size: rs.scale(20),
                    ),
                    SizedBox(width: rs.width(8)),
                    Text(
                      'Semester Duration',
                      style: GoogleFonts.inter(
                        fontSize: rs.font(16),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: rs.height(6)),
                Text(
                  '$startDateStr  →  $endDateStr',
                  style: GoogleFonts.inter(
                    fontSize: rs.font(13),
                    color: theme.textTheme.bodySmall?.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: rs.height(10)),
                Text(
                  !semesterProvider.hasSemesterStarted
                      ? 'Semester has not started yet. Summary will be calculated once it begins.'
                      : 'No subjects added yet. Add subjects to view overall analytics.',
                  style: GoogleFonts.inter(
                    fontSize: rs.font(13),
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          );
    }

    final targetPercentage = semester.targetPercentage;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDate = today.isAfter(semester.endDate) ? semester.endDate : today;

    int totalClassesInSemester = 0;
    int scheduledSoFar = 0;
    int totalMarked = 0;
    int totalAttended = 0;

    for (final subject in subjects) {
      final snapshot = _buildSemesterSubjectSnapshot(
        subject: subject,
        attendanceProvider: attendanceProvider,
        semester: semester,
        endDate: endDate,
      );

      totalClassesInSemester += snapshot.totalClassesInWindow;
      scheduledSoFar += snapshot.scheduledSoFarInWindow;
      totalMarked += snapshot.markedClasses;
      totalAttended += snapshot.attendedClasses;
    }

    final currentPercentage = totalMarked == 0
        ? 100.0
        : (totalAttended / totalMarked) * 100;
    final slackPercentage = currentPercentage - targetPercentage;

    final semesterProjection = ProjectedAttendanceCalculator.calculateForSemester(
      subjects: subjects,
      attendanceRecords: attendanceProvider.attendanceRecords,
      semester: semester,
      plannedLeaves: _plannedLeaves,
    );

    int futureScheduled = totalClassesInSemester - scheduledSoFar;
    if (futureScheduled < 0) futureScheduled = 0;

    // Current-state bunkable: how many classes can be safely bunked (surplus)
    // or how many classes must be attended to recover target (deficit).
    final int bunkable = AttendanceMath.calculateBunkableDeficitOrSurplus(
      attended: totalAttended,
      marked: totalMarked,
      targetPercentage: targetPercentage,
    );

    String message;
    IconData statusIcon;

    if (bunkable > 0) {
      message = 'You have a surplus of $bunkable classes over target';
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (bunkable == 0) {
      if (currentPercentage > targetPercentage) {
        message = 'Attendance is above target (0 bunkable classes)';
        statusIcon = Icons.check_circle_outline_rounded;
      } else {
        message = 'Attendance is exactly at target';
        statusIcon = Icons.adjust_rounded;
      }
    } else {
      message = 'You are ${bunkable.abs()} classes short of target';
      statusIcon = Icons.warning_amber_rounded;
    }

    final slackText =
        '${slackPercentage >= 0 ? '+' : ''}${slackPercentage.toStringAsFixed(1)}%';
    final progressRatio = (currentPercentage / 100).clamp(0.0, 1.0);

    final targetRatio = (targetPercentage / 100).clamp(0.0, 1.0);

    return Container(
      padding: EdgeInsets.all(rs.scale(18)),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF14141C).withValues(alpha: 0.65)
            : Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(rs.scale(20)),
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.60),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.30 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Semester Span & High-contrast Status Pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                        size: rs.scale(14),
                      ),
                      SizedBox(width: rs.width(7)),
                      Text(
                        '$startDateStr  –  $endDateStr',
                        style: GoogleFonts.inter(
                          fontSize: rs.font(11.5),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: rs.width(9),
                      vertical: rs.height(4),
                    ),
                    decoration: BoxDecoration(
                      color: slackPercentage >= 0
                          ? (isDarkMode ? Colors.white : Colors.black)
                          : (isDarkMode ? const Color(0xFF2C1517) : const Color(0xFFFDEDED)),
                      borderRadius: BorderRadius.circular(rs.scale(100)),
                      border: Border.all(
                        color: slackPercentage >= 0
                            ? (isDarkMode ? Colors.white : Colors.black)
                            : (isDarkMode ? const Color(0xFFEF5350).withValues(alpha: 0.4) : const Color(0xFFEF5350).withValues(alpha: 0.3)),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      slackPercentage >= 0 ? 'ON TRACK' : 'BELOW TARGET',
                      style: GoogleFonts.inter(
                        fontSize: rs.font(9.5),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: slackPercentage >= 0
                            ? (isDarkMode ? Colors.black : Colors.white)
                            : (isDarkMode ? const Color(0xFFFF8A80) : const Color(0xFFD32F2F)),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: rs.height(16)),

              // Hero Charge Meter Value & Target Caption
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${currentPercentage.toStringAsFixed(1)}%',
                    style: GoogleFonts.inter(
                      fontSize: rs.font(42),
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                  SizedBox(width: rs.width(10)),
                  Text(
                    'Target ${targetPercentage.toStringAsFixed(0)}%  ($slackText)',
                    style: GoogleFonts.inter(
                      fontSize: rs.font(12.5),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
                      color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                    ),
                  ),
                ],
              ),
              SizedBox(height: rs.height(14)),

              // Tesla Car Charging Bar with Target Tick Marker (Sleek Minimalist)
              LayoutBuilder(
                builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;
                  final fillWidth = trackWidth * progressRatio;
                  final targetX = trackWidth * targetRatio;

                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerLeft,
                    children: [
                      // Track background
                      Container(
                        height: rs.height(6),
                        width: trackWidth,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(rs.scale(3)),
                        ),
                      ),
                      // Current level fill (Solid Monotone)
                      Container(
                        height: rs.height(6),
                        width: fillWidth,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white : Colors.black,
                          borderRadius: BorderRadius.circular(rs.scale(3)),
                        ),
                      ),
                      // Target limit tick pin (Tesla slider style)
                      Positioned(
                        left: (targetX - rs.scale(1.5)).clamp(0.0, trackWidth - rs.scale(3)),
                        top: -rs.scale(2.5),
                        bottom: -rs.scale(2.5),
                        child: Container(
                          width: rs.scale(3),
                          decoration: BoxDecoration(
                            color: isDarkMode ? const Color(0xFFAAAAAA) : const Color(0xFF444444),
                            borderRadius: BorderRadius.circular(rs.scale(1.5)),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              SizedBox(height: rs.height(14)),

              // Minimalist Unboxed Status Summary Row
              Row(
                children: [
                  Icon(
                    statusIcon,
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                    size: rs.scale(16),
                  ),
                  SizedBox(width: rs.width(8)),
                  Expanded(
                    child: Text(
                      message,
                      style: GoogleFonts.inter(
                        fontSize: rs.font(12.5),
                        color: isDarkMode ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => _showSubjectAttendanceWarningDialog(context),
                    borderRadius: BorderRadius.circular(rs.scale(12)),
                    child: Padding(
                      padding: EdgeInsets.all(rs.scale(4)),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                        size: rs.scale(16),
                      ),
                    ),
                  ),
                ],
              ),
              if (semesterProjection.hasActivePlannedLeave) ...[
                SizedBox(height: rs.height(10)),
                InkWell(
                  borderRadius: BorderRadius.circular(rs.scale(12)),
                  onTap: () => _showProjectedAttendanceDetailDialog(
                    context: context,
                    semester: semester,
                    semesterProjection: semesterProjection,
                    subjects: subjects,
                  ),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: rs.width(12),
                      vertical: rs.height(10),
                    ),
                    decoration: BoxDecoration(
                      color: isDarkMode ? const Color(0xFF19191D) : const Color(0xFFEDEDF0),
                      borderRadius: BorderRadius.circular(rs.scale(12)),
                      border: Border.all(
                        color: isDarkMode ? const Color(0xFF27272D) : const Color(0xFFDDDDDE),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_available_outlined,
                          color: isDarkMode ? Colors.white : Colors.black,
                          size: rs.scale(18),
                        ),
                        SizedBox(width: rs.width(8)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Projected (After Leave): ${semesterProjection.projectedPercentage.toStringAsFixed(1)}%',
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(12.5),
                                  fontWeight: FontWeight.w700,
                                  color: isDarkMode ? Colors.white : Colors.black87,
                                ),
                              ),
                              if (semesterProjection.latestLeaveEndDate != null) ...[
                                SizedBox(height: rs.height(2)),
                                Text(
                                  'Projected date: ${DateFormat('d MMM yyyy').format(semesterProjection.latestLeaveEndDate!)}',
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(11),
                                    fontWeight: FontWeight.w500,
                                    color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: rs.scale(18),
                          color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
  }

  void _showProjectedAttendanceDetailDialog({
    required BuildContext context,
    required Semester semester,
    required SemesterProjectedAttendance semesterProjection,
    required List<Subject> subjects,
  }) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final latestLeaveEnd = semesterProjection.latestLeaveEndDate ?? DateTime.now();
    final formattedProjectedDate = DateFormat('d MMM yyyy').format(latestLeaveEnd);

    final recoveryResult = ProjectedAttendanceCalculator.calculateClassesNeededAfterLeave(
      subjects: subjects,
      semester: semester,
      projectedAttended: semesterProjection.totalAttended,
      projectedMarked: semesterProjection.totalMarked,
      leaveEndDate: latestLeaveEnd,
      targetPercentage: semester.targetPercentage,
    );

    final isBelowTarget = semesterProjection.projectedSlack < 0;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.65 : 0.45),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, anim, secondaryAnim) => Dialog(
        backgroundColor: isDarkMode ? const Color(0xFF16161A) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rs.scale(22)),
          side: BorderSide(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        insetPadding: EdgeInsets.symmetric(
          horizontal: rs.width(20),
          vertical: rs.height(24),
        ),
        child: Padding(
          padding: EdgeInsets.all(rs.scale(20)),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(rs.scale(8)),
                      decoration: BoxDecoration(
                        color: (isBelowTarget ? Colors.red : Colors.green).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.event_available_rounded,
                        color: isBelowTarget ? Colors.red : Colors.green,
                        size: rs.scale(22),
                      ),
                    ),
                    SizedBox(width: rs.width(10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Projected Leave Overview',
                            style: TextStyle(
                              fontSize: rs.font(16),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: rs.height(2)),
                          Text(
                            'Projected as of $formattedProjectedDate',
                            style: TextStyle(
                              fontSize: rs.font(12),
                              fontWeight: FontWeight.w500,
                              color: isBelowTarget
                                  ? (isDarkMode ? Colors.red.shade300 : Colors.red.shade700)
                                  : (isDarkMode ? Colors.green.shade300 : Colors.green.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: rs.height(16)),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(rs.scale(12)),
                  decoration: BoxDecoration(
                    color: (isBelowTarget ? Colors.red : Colors.green).withValues(alpha: isDarkMode ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(rs.scale(12)),
                    border: Border.all(
                      color: (isBelowTarget ? Colors.red : Colors.green).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${semesterProjection.projectedPercentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: rs.font(24),
                          fontWeight: FontWeight.bold,
                          color: isBelowTarget ? Colors.red : Colors.green,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Target: ${semester.targetPercentage.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: rs.font(12),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: rs.height(2)),
                          Text(
                            '${semesterProjection.projectedSlack >= 0 ? '+' : ''}${semesterProjection.projectedSlack.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: rs.font(12),
                              fontWeight: FontWeight.bold,
                              color: isBelowTarget ? Colors.red : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: rs.height(14)),
                _buildDetailRow(
                  rs: rs,
                  theme: theme,
                  icon: Icons.event_busy_rounded,
                  iconColor: Colors.red,
                  label: 'Classes Missed During Leave',
                  value: '${semesterProjection.totalPlannedMissed} classes',
                ),
                SizedBox(height: rs.height(6)),
                _buildDetailRow(
                  rs: rs,
                  theme: theme,
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: Colors.green,
                  label: 'Upcoming Assumed Present',
                  value: '${semesterProjection.totalAssumedPresent} classes',
                ),

                SizedBox(height: rs.height(14)),
                const Divider(),
                SizedBox(height: rs.height(10)),

                Text(
                  'After Planned Leave Requirements',
                  style: TextStyle(
                    fontSize: rs.font(13),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: rs.height(8)),

                if (isBelowTarget) ...[
                  Container(
                    padding: EdgeInsets.all(rs.scale(12)),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: isDarkMode ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(rs.scale(12)),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amber.shade800,
                              size: rs.scale(20),
                            ),
                            SizedBox(width: rs.width(8)),
                            Expanded(
                              child: Text(
                                recoveryResult.isAchievable
                                    ? 'Must attend next ${recoveryResult.classesNeeded} classes continuously after leave'
                                    : 'Target unreachable after leave (Max: ${recoveryResult.maxAchievablePercentage.toStringAsFixed(1)}%)',
                                style: TextStyle(
                                  fontSize: rs.font(13),
                                  fontWeight: FontWeight.bold,
                                  color: isDarkMode ? Colors.amber.shade200 : Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: rs.height(8)),
                        Text(
                          recoveryResult.isAchievable
                              ? 'Your attendance is projected to drop to ${semesterProjection.projectedPercentage.toStringAsFixed(1)}% (${semesterProjection.projectedSlack.abs().toStringAsFixed(1)}% below target).\n\nAttending ${recoveryResult.classesNeeded} classes continuously after leave will restore your overall attendance to the ${semester.targetPercentage.toStringAsFixed(0)}% target${recoveryResult.targetRecoveryDate != null ? ' by ${DateFormat('d MMM yyyy').format(recoveryResult.targetRecoveryDate!)}' : ''}.'
                              : 'Your attendance is projected to drop to ${semesterProjection.projectedPercentage.toStringAsFixed(1)}% (${semesterProjection.projectedSlack.abs().toStringAsFixed(1)}% below target).\n\nEven attending all ${recoveryResult.remainingAfterLeave} remaining classes after leave will only reach ${recoveryResult.maxAchievablePercentage.toStringAsFixed(1)}%.',
                          style: TextStyle(
                            fontSize: rs.font(12),
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                        if (recoveryResult.isAchievable && recoveryResult.targetRecoveryDate != null) ...[
                          SizedBox(height: rs.height(8)),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: rs.width(8),
                              vertical: rs.height(6),
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(rs.scale(8)),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.event_available_rounded,
                                  size: rs.scale(15),
                                  color: Colors.amber.shade800,
                                ),
                                SizedBox(width: rs.width(6)),
                                Expanded(
                                  child: Text(
                                    'Target Recovery Date: ${DateFormat('d MMM yyyy').format(recoveryResult.targetRecoveryDate!)}',
                                    style: TextStyle(
                                      fontSize: rs.font(11),
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode ? Colors.amber.shade200 : Colors.amber.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  Builder(
                    builder: (context) {
                      final bunkableAfterLeave = AttendanceMath.calculateBunkableClasses(
                        attended: semesterProjection.totalAttended,
                        marked: semesterProjection.totalMarked,
                        targetPercentage: semester.targetPercentage,
                      );

                      return Container(
                        padding: EdgeInsets.all(rs.scale(12)),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: isDarkMode ? 0.15 : 0.08),
                          borderRadius: BorderRadius.circular(rs.scale(12)),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.green,
                                  size: rs.scale(20),
                                ),
                                SizedBox(width: rs.width(8)),
                                Expanded(
                                  child: Text(
                                    'On Track',
                                    style: TextStyle(
                                      fontSize: rs.font(13),
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode ? Colors.green.shade200 : Colors.green.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: rs.height(8)),
                            Text(
                              'Your attendance is projected to be ${semesterProjection.projectedPercentage.toStringAsFixed(1)}% (+${semesterProjection.projectedSlack.toStringAsFixed(1)}% above your ${semester.targetPercentage.toStringAsFixed(0)}% target).\n\n${bunkableAfterLeave > 0 ? 'You will still have a buffer of $bunkableAfterLeave class${bunkableAfterLeave > 1 ? 'es' : ''} to safely bunk after leave while remaining on or above target.' : 'You will be right at target with no extra classes to bunk after leave.'}',
                              style: TextStyle(
                                fontSize: rs.font(12),
                                color: theme.textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
                SizedBox(height: rs.height(16)),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(rs.scale(12)),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: rs.width(20),
                        vertical: rs.height(10),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required ResponsiveScale rs,
    required ThemeData theme,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: rs.scale(16), color: iconColor),
        SizedBox(width: rs.width(8)),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: rs.font(12),
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: rs.font(12),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _showSubjectAttendanceWarningDialog(BuildContext context) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.65 : 0.45),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (context, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: curved,
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, anim, secondaryAnim) => Dialog(
        backgroundColor: isDarkMode ? const Color(0xFF16161A) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rs.scale(22)),
          side: BorderSide(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.black.withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        insetPadding: EdgeInsets.symmetric(
          horizontal: rs.width(20),
          vertical: rs.height(24),
        ),
        child: Padding(
          padding: EdgeInsets.all(rs.scale(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(rs.scale(8)),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: theme.colorScheme.primary,
                      size: rs.scale(22),
                    ),
                  ),
                  SizedBox(width: rs.width(12)),
                  Expanded(
                    child: Text(
                      'Attendance Calculation Note',
                      style: TextStyle(
                        fontSize: rs.font(16),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: rs.height(16)),
              Text(
                'Overall semester metrics aggregate all subjects combined.',
                style: TextStyle(
                  fontSize: rs.font(13),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: rs.height(10)),
              Container(
                padding: EdgeInsets.all(rs.scale(12)),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: isDarkMode ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(rs.scale(12)),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber.shade800,
                      size: rs.scale(20),
                    ),
                    SizedBox(width: rs.width(8)),
                    Expanded(
                      child: Text(
                        'Your total overall percentage may be higher than required, but attendance for an individual subject may still fall below your target.',
                        style: TextStyle(
                          fontSize: rs.font(12),
                          color: isDarkMode ? Colors.amber.shade200 : Colors.amber.shade900,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: rs.height(12)),
              Text(
                'Tip: Always review individual subject attendance on the Subjects or Bunk Meter screen before skipping classes.',
                style: TextStyle(
                  fontSize: rs.font(12),
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
              SizedBox(height: rs.height(16)),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(rs.scale(12)),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: rs.width(20),
                      vertical: rs.height(10),
                    ),
                  ),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSemesterParametersCard(Semester semester) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final effectiveStartDate = _startDate ?? semester.startDate;
    final effectiveEndDate = _endDate ?? semester.endDate;
    final effectiveTarget = _targetPercentage ?? semester.targetPercentage;

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF14141C).withValues(alpha: 0.65)
              : Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(rs.scale(18)),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.60),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDarkMode ? 0.30 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(rs.scale(18)),
          child: ExpansionTile(
            maintainState: true,
            expansionAnimationStyle: const AnimationStyle(
              duration: Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
              shape: const Border(),
              collapsedShape: const Border(),
              initiallyExpanded: false,
              tilePadding: EdgeInsets.symmetric(
                horizontal: rs.width(16),
                vertical: rs.height(4),
              ),
          leading: Icon(
            Icons.tune_rounded,
            color: theme.colorScheme.primary,
            size: rs.scale(20),
          ),
          title: Text(
            'Semester Parameters',
            style: TextStyle(
              fontSize: rs.font(15),
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            '${DateFormat.yMMMd().format(effectiveStartDate)} – ${DateFormat.yMMMd().format(effectiveEndDate)}\n${effectiveTarget.round()}% Target',
            style: TextStyle(
              fontSize: rs.font(12),
              color: theme.textTheme.bodySmall?.color,
              fontWeight: FontWeight.w500,
            ),
          ),
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: rs.width(16),
                right: rs.width(16),
                bottom: rs.height(16),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildDatePickerField(
                          title: 'Start Date',
                          date: effectiveStartDate,
                          onPressed: () async {
                            final maxStart = effectiveEndDate.subtract(const Duration(days: 1));
                            final initial = effectiveStartDate.isBefore(maxStart)
                                ? effectiveStartDate
                                : maxStart;
                            final date = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: DateTime(2000),
                              lastDate: maxStart.isBefore(DateTime(2000)) ? DateTime(2000) : maxStart,
                              helpText: 'Select Start Date',
                            );
                            if (date != null) {
                              setState(() {
                                _startDate = date;
                              });
                              _saveSemesterParameters(
                                startDate: date,
                                endDate: effectiveEndDate,
                                targetPercentage: effectiveTarget,
                              );
                            }
                          },
                        ),
                      ),
                      SizedBox(width: rs.width(12)),
                      Expanded(
                        child: _buildDatePickerField(
                          title: 'End Date',
                          date: effectiveEndDate,
                          onPressed: () async {
                            final firstAllowed = effectiveStartDate.add(const Duration(days: 1));
                            final initial = effectiveEndDate.isAfter(firstAllowed)
                                ? effectiveEndDate
                                : firstAllowed;
                            final date = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: firstAllowed,
                              lastDate: DateTime(2100),
                              helpText: 'Select End Date',
                            );
                            if (date != null) {
                              setState(() {
                                _endDate = date;
                              });
                              _saveSemesterParameters(
                                startDate: effectiveStartDate,
                                endDate: date,
                                targetPercentage: effectiveTarget,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: rs.height(14)),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: rs.width(16),
                      vertical: rs.height(12),
                    ),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
                          : theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(rs.scale(16)),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.track_changes_rounded,
                                  size: rs.scale(20),
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                                SizedBox(width: rs.width(12)),
                                Text(
                                  'Target Percentage',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: rs.font(14),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: rs.width(10),
                                vertical: rs.height(4),
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(rs.scale(12)),
                              ),
                              child: Text(
                                '${effectiveTarget.round()}%',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: rs.font(14),
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: effectiveTarget.clamp(50.0, 100.0),
                          min: 50,
                          max: 100,
                          divisions: 50,
                          label: '${effectiveTarget.round()}%',
                          onChanged: (val) {
                            final newTarget = val.roundToDouble();
                            if (newTarget != effectiveTarget) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _targetPercentage = newTarget;
                                _targetPercentageController.text = newTarget.toStringAsFixed(0);
                              });
                            }
                          },
                          onChangeEnd: (val) {
                            final newTarget = val.roundToDouble();
                            _saveSemesterParameters(
                              startDate: effectiveStartDate,
                              endDate: effectiveEndDate,
                              targetPercentage: newTarget,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildMetricsGrid({
    required Semester semester,
    required SemesterProvider semesterProvider,
    required SubjectProvider subjectProvider,
    required AttendanceProvider attendanceProvider,
  }) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final subjects = subjectProvider.subjects;

    if (!semesterProvider.hasSemesterStarted || subjects.isEmpty) {
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDate = today.isAfter(semester.endDate) ? semester.endDate : today;

    int totalClassesInSemester = 0;
    int scheduledSoFar = 0;
    int totalHeld = 0;
    int totalMarked = 0;
    int totalAttended = 0;

    for (final subject in subjects) {
      final snapshot = _buildSemesterSubjectSnapshot(
        subject: subject,
        attendanceProvider: attendanceProvider,
        semester: semester,
        endDate: endDate,
      );

      totalClassesInSemester += snapshot.totalClassesInWindow;
      scheduledSoFar += snapshot.scheduledSoFarInWindow;
      totalHeld += snapshot.classesHeldSoFar;
      totalMarked += snapshot.markedClasses;
      totalAttended += snapshot.attendedClasses;
    }

    final bunkedSoFar = totalMarked > 0 ? (totalMarked - totalAttended) : 0;
    int futureScheduled = totalClassesInSemester - scheduledSoFar;
    if (futureScheduled < 0) futureScheduled = 0;

    final isDarkMode = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: rs.width(4), bottom: rs.height(10)),
          child: Row(
            children: [
              Text(
                'SEMESTER TELEMETRY',
                style: GoogleFonts.inter(
                  fontSize: rs.font(12),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                ),
              ),
              SizedBox(width: rs.width(6)),
              InkWell(
                onTap: () => _showSubjectAttendanceWarningDialog(context),
                borderRadius: BorderRadius.circular(rs.scale(12)),
                child: Padding(
                  padding: EdgeInsets.all(rs.scale(4)),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: rs.scale(16),
                    color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: rs.width(4),
            vertical: rs.height(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildTelemetryCell(
                  isDarkMode,
                  label: 'ATTENDED',
                  value: totalAttended.toString(),
                ),
              ),
              _buildTelemetryDivider(isDarkMode, vertical: true),
              Expanded(
                child: _buildTelemetryCell(
                  isDarkMode,
                  label: 'HELD',
                  value: totalHeld.toString(),
                ),
              ),
              _buildTelemetryDivider(isDarkMode, vertical: true),
              Expanded(
                child: _buildTelemetryCell(
                  isDarkMode,
                  label: 'BUNKED',
                  value: bunkedSoFar.toString(),
                ),
              ),
              _buildTelemetryDivider(isDarkMode, vertical: true),
              Expanded(
                child: _buildTelemetryCell(
                  isDarkMode,
                  label: 'REMAINING',
                  value: futureScheduled.toString(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSemesterEndedAlert() {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(rs.scale(16)),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: isDarkMode ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(rs.scale(16)),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(rs.scale(8)),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.info_outline_rounded,
                  color: Colors.amber.shade800,
                  size: rs.scale(22),
                ),
              ),
              SizedBox(width: rs.width(12)),
              Expanded(
                child: Text(
                  'Semester has ended. You can view past data or start a brand new semester.',
                  style: TextStyle(
                    color: isDarkMode ? Colors.amber.shade200 : Colors.amber.shade900,
                    fontWeight: FontWeight.w600,
                    fontSize: rs.font(13),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(14)),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                DateTime? newStartDate;
                DateTime? newEndDate;
                double? newTargetPercentage;

                showDialog(
                  context: context,
                  barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.65 : 0.45),
                  builder: (ctx) => AlertDialog(
                    backgroundColor: isDarkMode ? const Color(0xFF16161A) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(rs.scale(20)),
                    ),
                    title: const Text('Start New Semester'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Create a new semester with new dates and settings. This will clear all previous data.',
                            style: TextStyle(fontSize: rs.font(14)),
                          ),
                          SizedBox(height: rs.height(16)),
                          StatefulBuilder(
                            builder: (context, setDialogState) => Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildDatePickerField(
                                  title: 'Semester Start Date',
                                  date: newStartDate,
                                  onPressed: () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                      helpText: 'Select Start Date',
                                    );
                                    if (date != null) {
                                      final bool willBeNull = newEndDate == null || !newEndDate!.isAfter(date);
                                      setDialogState(() {
                                        newStartDate = date;
                                        if (newEndDate != null &&
                                            !newEndDate!.isAfter(date)) {
                                          newEndDate = null;
                                        }
                                      });
                                      if (willBeNull && context.mounted) {
                                        final firstAllowed = date.add(const Duration(days: 1));
                                        final endDate = await showDatePicker(
                                          context: context,
                                          initialDate: firstAllowed,
                                          firstDate: firstAllowed,
                                          lastDate: DateTime(2100),
                                          helpText: 'Select End Date',
                                        );
                                        if (endDate != null) {
                                          setDialogState(() {
                                            newEndDate = endDate;
                                          });
                                        }
                                      }
                                    }
                                  },
                                ),
                                SizedBox(height: rs.height(12)),
                                _buildDatePickerField(
                                  title: 'Semester End Date',
                                  date: newEndDate,
                                  onPressed: newStartDate == null
                                      ? null
                                      : () async {
                                          final firstAllowed =
                                              newStartDate!.add(
                                                const Duration(days: 1),
                                              );
                                          final initial =
                                              newEndDate != null &&
                                                  newEndDate!.isAfter(
                                                    newStartDate!,
                                                  )
                                              ? newEndDate!
                                              : firstAllowed;
                                          final date =
                                              await showDatePicker(
                                                context: context,
                                                initialDate: initial,
                                                firstDate: firstAllowed,
                                                lastDate: DateTime(2100),
                                                helpText: 'Select End Date',
                                              );
                                          if (date != null) {
                                            setDialogState(() {
                                              newEndDate = date;
                                            });
                                          }
                                        },
                                ),
                                SizedBox(height: rs.height(16)),
                                TextFormField(
                                  decoration: InputDecoration(
                                    labelText: 'Target Percentage',
                                    hintText: 'e.g. 75',
                                    prefixIcon: const Icon(Icons.percent_rounded),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(rs.scale(12)),
                                    ),
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (value) {
                                    if (value.isNotEmpty) {
                                      newTargetPercentage =
                                          double.tryParse(value);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          if (newStartDate == null ||
                              newEndDate == null ||
                              newTargetPercentage == null) {
                            ScaffoldMessenger.of(
                              context,
                            ).showReplacingSnackBar(
                              const SnackBar(
                                content: Text('Please fill all fields'),
                              ),
                            );
                            return;
                          }
                          if (!newEndDate!.isAfter(newStartDate!)) {
                            ScaffoldMessenger.of(
                              context,
                            ).showReplacingSnackBar(
                              const SnackBar(
                                content: Text(
                                  'End date must be after start date.',
                                ),
                              ),
                            );
                            return;
                          }

                          Navigator.of(ctx).pop();

                          if (!mounted) return;

                          final newSemester = Semester(
                            startDate: newStartDate!,
                            endDate: newEndDate!,
                            targetPercentage: newTargetPercentage!,
                          );

                          final confirmed = await showDialog<bool>(
                            context: context,
                            barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.65 : 0.45),
                            builder: (confirmCtx) => AlertDialog(
                              backgroundColor: isDarkMode ? const Color(0xFF16161A) : Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(rs.scale(20)),
                              ),
                              title: const Text('Confirm'),
                              content: const Text(
                                'This will clear all subjects and attendance data from the previous semester. This action cannot be undone. Do you want to continue?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(confirmCtx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      Navigator.of(confirmCtx).pop(true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  child: const Text('Clear Data & Start'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed != true) return;
                          if (!mounted) return;

                          await Provider.of<SemesterProvider>(
                            context,
                            listen: false,
                          ).createNewSemester(newSemester);

                          if (!mounted) return;

                          await Provider.of<SubjectProvider>(
                            context,
                            listen: false,
                          ).reloadSubjects();

                          if (!mounted) return;

                          await Provider.of<AttendanceProvider>(
                            context,
                            listen: false,
                          ).reloadAttendance();

                          if (mounted) {
                            setState(() {
                              _startDate = newSemester.startDate;
                              _endDate = newSemester.endDate;
                              _targetPercentage =
                                  newSemester.targetPercentage;
                              _targetPercentageController.text =
                                  newSemester.targetPercentage.toString();
                            });

                            ScaffoldMessenger.of(
                              context,
                            ).showReplacingSnackBar(
                              const SnackBar(
                                content: Text(
                                  'New semester created successfully!',
                                ),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Create & Clear Data'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('Start New Semester'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(rs.scale(12)),
                ),
                padding: EdgeInsets.symmetric(vertical: rs.height(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryCell(
    bool isDarkMode, {
    required String label,
    required String value,
  }) {
    final rs = context.rs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: rs.font(9.5),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
          ),
        ),
        SizedBox(height: rs.height(5)),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: rs.font(17),
            fontWeight: FontWeight.w700,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryDivider(bool isDarkMode, {required bool vertical}) {
    final rs = context.rs;
    final dividerColor = isDarkMode ? const Color(0xFF222227) : const Color(0xFFE5E5EB);
    if (vertical) {
      return Container(
        width: 1,
        height: rs.height(30),
        color: dividerColor,
      );
    } else {
      return Container(
        width: double.infinity,
        height: 1,
        color: dividerColor,
      );
    }
  }

  _SemesterSubjectSnapshot _buildSemesterSubjectSnapshot({
    required Subject subject,
    required AttendanceProvider attendanceProvider,
    required Semester semester,
    required DateTime endDate,
  }) {
    final manualOverride = subject.manualAttendanceOverride;
    DateTime countingStart =
        manualOverride?.effectiveFrom ?? semester.startDate;
    if (countingStart.isBefore(semester.startDate)) {
      countingStart = semester.startDate;
    }

    final recordsForSubject = attendanceProvider.attendanceRecords.where((
      record,
    ) {
      if (record.subjectId != subject.id) {
        return false;
      }
      if (record.date.isAfter(endDate)) {
        return false;
      }
      if (record.date.isBefore(countingStart)) {
        return false;
      }
      return true;
    }).toList();

    final attendedPostOverride = recordsForSubject
        .where((record) => record.status == AttendanceStatus.attended)
        .length;
    final absentPostOverride = recordsForSubject
        .where((record) => record.status == AttendanceStatus.absent)
        .length;
    final cancelledPostOverride = recordsForSubject
        .where((record) => record.status == AttendanceStatus.cancelled)
        .length;

    final scheduledSoFarInWindow = countingStart.isAfter(endDate)
        ? 0
        : subject.getTotalScheduledClasses(countingStart, endDate);
    final totalClassesInWindow = countingStart.isAfter(semester.endDate)
        ? 0
        : subject.getTotalScheduledClasses(countingStart, semester.endDate);

    int heldPostOverride = scheduledSoFarInWindow - cancelledPostOverride;
    if (heldPostOverride < 0) {
      heldPostOverride = 0;
    }

    final baselineHeld = manualOverride?.classesHeld ?? 0;
    final baselineAttended = manualOverride?.classesAttended ?? 0;
    final baselineAbsent = manualOverride?.classesAbsent ?? 0;

    return _SemesterSubjectSnapshot(
      totalClassesInWindow: totalClassesInWindow,
      scheduledSoFarInWindow: scheduledSoFarInWindow,
      classesHeldSoFar: baselineHeld + heldPostOverride,
      attendedClasses: baselineAttended + attendedPostOverride,
      absentClasses: baselineAbsent + absentPostOverride,
      markedClasses: baselineHeld + attendedPostOverride + absentPostOverride,
    );
  }

  Widget _buildDatePickerField({
    required String title,
    required DateTime? date,
    required VoidCallback? onPressed,
  }) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: rs.width(4)),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: rs.font(12),
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
        SizedBox(height: rs.height(6)),
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(rs.scale(16)),
          child: Opacity(
            opacity: onPressed == null ? 0.5 : 1.0,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: rs.width(14),
                vertical: rs.height(12),
              ),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                    : theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(rs.scale(16)),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.08),
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: rs.scale(16),
                    color: theme.colorScheme.primary,
                  ),
                  SizedBox(width: rs.width(10)),
                  Expanded(
                    child: Text(
                      date != null ? DateFormat.yMMMd().format(date) : 'Select Date',
                      style: TextStyle(
                        fontSize: rs.font(13),
                        fontWeight: date != null ? FontWeight.bold : FontWeight.normal,
                        color: date != null
                            ? theme.colorScheme.onSurface
                            : theme.textTheme.bodySmall?.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SemesterSubjectSnapshot {
  final int totalClassesInWindow;
  final int scheduledSoFarInWindow;
  final int classesHeldSoFar;
  final int attendedClasses;
  final int absentClasses;
  final int markedClasses;

  const _SemesterSubjectSnapshot({
    required this.totalClassesInWindow,
    required this.scheduledSoFarInWindow,
    required this.classesHeldSoFar,
    required this.attendedClasses,
    required this.absentClasses,
    required this.markedClasses,
  });
}
