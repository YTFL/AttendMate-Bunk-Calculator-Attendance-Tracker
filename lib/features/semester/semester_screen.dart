import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
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
  bool _isEditingParameters = false;

  @override
  void initState() {
    super.initState();
    final semester = Provider.of<SemesterProvider>(
      context,
      listen: false,
    ).semester;
    _startDate = semester?.startDate;
    _endDate = semester?.endDate;
    _targetPercentage = semester?.targetPercentage ?? 75.0;
    _targetPercentageController = TextEditingController(
      text: _targetPercentage?.toStringAsFixed(0) ?? '75',
    );
  }

  @override
  void dispose() {
    _targetPercentageController.dispose();
    super.dispose();
  }

  bool _isEndDateAfterStart(DateTime? startDate, DateTime? endDate) {
    if (startDate == null || endDate == null) {
      return true;
    }
    return endDate.isAfter(startDate);
  }

  void _updateSemester() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      if (!_isEndDateAfterStart(_startDate, _endDate)) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(content: Text('End date must be after start date.')),
        );
        return;
      }
      if (_startDate != null && _endDate != null && _targetPercentage != null) {
        final updatedSemester = Semester(
          startDate: _startDate!,
          endDate: _endDate!,
          targetPercentage: _targetPercentage!,
        );
        Provider.of<SemesterProvider>(
          context,
          listen: false,
        ).updateSemester(updatedSemester);

        final tutorialController = Provider.of<TutorialController>(context, listen: false);
        if (tutorialController.isActive && tutorialController.currentStepIndex <= 2) {
          tutorialController.nextStep();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    tutorialController.registerKey('btn_setup_semester', _setupFormKey);

    final semesterProvider = Provider.of<SemesterProvider>(context);

    if (semesterProvider.semester == null) {
      return _buildCreateSemesterForm();
    } else {
      return _buildSemesterDetails();
    }
  }

  Widget _buildCreateSemesterForm() {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        rs.width(16),
        rs.height(12),
        rs.width(16),
        rs.height(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyedSubtree(
            key: _setupFormKey,
            child: Container(
              padding: EdgeInsets.all(rs.scale(20)),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(rs.scale(20)),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.12),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.03),
                  blurRadius: rs.scale(12),
                  offset: Offset(0, rs.scale(4)),
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
                          color: theme.colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(rs.scale(12)),
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
                              HapticFeedback.vibrate();
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
                      onPressed: _updateSemester,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(rs.scale(12)),
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
      padding: EdgeInsets.fromLTRB(
        rs.width(16),
        rs.height(8),
        rs.width(16),
        rs.height(24),
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

          // 3. Seamless Semester Parameters Section (Dates & Target %)
          _buildSemesterParametersCard(),

          // 4. Semester Ended Warning / New Semester Trigger
          if (semesterEnded) ...[
            SizedBox(height: rs.height(14)),
            _buildSemesterEndedAlert(),
          ],
        ],
      ),
    );
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
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(rs.scale(18)),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: 0.12),
          ),
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
                  style: TextStyle(
                    fontSize: rs.font(16),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: rs.height(6)),
            Text(
              '$startDateStr  →  $endDateStr',
              style: TextStyle(
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
              style: TextStyle(
                fontSize: rs.font(13),
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      );
    }

    final targetPercentage = semester.targetPercentage;
    final targetRatio = targetPercentage / 100;
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

    int futureScheduled = totalClassesInSemester - scheduledSoFar;
    if (futureScheduled < 0) futureScheduled = 0;

    // Current-state bunkable: how many classes you've "saved" or "over-spent" relative to target.
    // Positive = surplus (you could have bunked this many more and still been at target).
    // Negative = deficit (you've bunked this many too many — must make them up).
    final int bunkable = totalMarked == 0
        ? 0
        : (totalAttended - targetRatio * totalMarked).floor();

    String message;
    Color statusColor;
    IconData statusIcon;

    if (bunkable > 0) {
      message = 'You have a surplus of $bunkable classes over target';
      statusColor = const Color(0xFF4CAF50);
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (bunkable == 0) {
      message = 'Attendance is exactly at target';
      statusColor = const Color(0xFFFFA726);
      statusIcon = Icons.adjust_rounded;
    } else {
      message = 'You are ${bunkable.abs()} classes short of target';
      statusColor = const Color(0xFFEF5350);
      statusIcon = Icons.warning_amber_rounded;
    }

    final slackText =
        '${slackPercentage >= 0 ? '+' : ''}${slackPercentage.toStringAsFixed(1)}%';
    final progressRatio = (currentPercentage / 100).clamp(0.0, 1.0);

    return Container(
      padding: EdgeInsets.all(rs.scale(18)),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(rs.scale(20)),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.12),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.25 : 0.04),
            blurRadius: rs.scale(12),
            offset: Offset(0, rs.scale(4)),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Semester Span & Active Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    '$startDateStr  –  $endDateStr',
                    style: TextStyle(
                      fontSize: rs.font(12),
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: rs.width(8),
                  vertical: rs.height(3),
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(rs.scale(10)),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  slackPercentage >= 0 ? 'On Track' : 'Below Target',
                  style: TextStyle(
                    fontSize: rs.font(10),
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(14)),

          // Attendance Percentage Meter Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${currentPercentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: rs.font(36),
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: statusColor,
                ),
              ),
              SizedBox(width: rs.width(12)),
              Text(
                'Target: ${targetPercentage.toStringAsFixed(0)}%  ($slackText)',
                style: TextStyle(
                  fontSize: rs.font(13),
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(10)),

          // Linear Progress Indicator
          ClipRRect(
            borderRadius: BorderRadius.circular(rs.scale(8)),
            child: LinearProgressIndicator(
              value: progressRatio,
              minHeight: rs.height(10),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          SizedBox(height: rs.height(14)),

          // Status Alert Banner Box
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: rs.width(12),
              vertical: rs.height(10),
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: isDarkMode ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(rs.scale(12)),
              border: Border.all(color: statusColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: rs.scale(20)),
                SizedBox(width: rs.width(10)),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: rs.font(13),
                      color: statusColor,
                      fontWeight: FontWeight.bold,
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
                      color: statusColor,
                      size: rs.scale(18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSubjectAttendanceWarningDialog(BuildContext context) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rs.scale(20)),
        ),
        title: Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: theme.colorScheme.primary,
              size: rs.scale(24),
            ),
            SizedBox(width: rs.width(10)),
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildSemesterParametersCard() {
    final rs = context.rs;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(rs.scale(18)),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.12),
          width: 1.2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(rs.scale(18)),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
        initiallyExpanded: _isEditingParameters,
        onExpansionChanged: (expanded) {
          setState(() {
            _isEditingParameters = expanded;
          });
        },
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
          'Tap to modify dates or target percentage',
          style: TextStyle(
            fontSize: rs.font(11),
            color: theme.textTheme.bodySmall?.color,
          ),
        ),
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: rs.width(16),
              right: rs.width(16),
              bottom: rs.height(16),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildDatePickerField(
                          title: 'Start Date',
                          date: _startDate,
                          onPressed: _startDate == null
                              ? null
                              : () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: _startDate!,
                                    firstDate: DateTime(2000),
                                    lastDate: _endDate != null
                                        ? (_endDate!
                                                  .subtract(
                                                    const Duration(days: 1),
                                                  )
                                                  .isBefore(DateTime(2000))
                                              ? DateTime(2000)
                                              : _endDate!.subtract(
                                                  const Duration(days: 1),
                                                ))
                                        : DateTime(2100),
                                    helpText: 'Select Start Date',
                                  );
                                  if (date != null) {
                                    final bool willBeNull = _endDate == null || !_endDate!.isAfter(date);
                                    setState(() {
                                      _startDate = date;
                                      if (_endDate != null &&
                                          !_endDate!.isAfter(date)) {
                                        _endDate = null;
                                      }
                                    });
                                    _updateSemester();
                                    if (willBeNull && mounted) {
                                      final firstAllowed = date.add(
                                        const Duration(days: 1),
                                      );
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
                                        _updateSemester();
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
                          onPressed: _endDate == null
                              ? null
                              : () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: _endDate!,
                                    firstDate: _startDate != null
                                        ? _startDate!.add(
                                            const Duration(days: 1),
                                          )
                                        : DateTime(2000),
                                    lastDate: DateTime(2100),
                                    helpText: 'Select End Date',
                                  );
                                  if (date != null) {
                                    setState(() {
                                      _endDate = date;
                                    });
                                    _updateSemester();
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
                              HapticFeedback.vibrate();
                              setState(() {
                                _targetPercentage = newTarget;
                                _targetPercentageController.text = newTarget.toStringAsFixed(0);
                              });
                              _updateSemester();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

    final targetPercentage = semester.targetPercentage;
    final targetRatio = targetPercentage / 100;
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
    final currentPercentage = totalMarked == 0
        ? 100.0
        : (totalAttended / totalMarked) * 100;
    final slackPercentage = currentPercentage - targetPercentage;

    int futureScheduled = totalClassesInSemester - scheduledSoFar;
    if (futureScheduled < 0) futureScheduled = 0;

    // Current-state bunkable: attended - target × marked.
    // Positive = surplus, Negative = deficit.
    final int bunkable = totalMarked == 0
        ? 0
        : (totalAttended - targetRatio * totalMarked).floor();


    final slackText =
        '${slackPercentage >= 0 ? '+' : ''}${slackPercentage.toStringAsFixed(1)}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: rs.width(4), bottom: rs.height(8)),
          child: Row(
            children: [
              Text(
                'Semester Metrics',
                style: TextStyle(
                  fontSize: rs.font(15),
                  fontWeight: FontWeight.bold,
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
                    size: rs.scale(18),
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final spacing = rs.width(8);
            final itemWidth = (constraints.maxWidth - (spacing * 3)) / 4;
            return Column(
              children: [
                Row(
                  children: [
                    _buildSummaryStatTile('Held', totalHeld.toString(), width: itemWidth),
                    SizedBox(width: spacing),
                    _buildSummaryStatTile('Attended', totalAttended.toString(), width: itemWidth, color: const Color(0xFF4CAF50)),
                    SizedBox(width: spacing),
                    _buildSummaryStatTile('Bunked', bunkedSoFar.toString(), width: itemWidth, color: const Color(0xFFEF5350)),
                    SizedBox(width: spacing),
                    _buildSummaryStatTile('Current %', '${currentPercentage.toStringAsFixed(1)}%', width: itemWidth, color: theme.colorScheme.primary),
                  ],
                ),
                SizedBox(height: rs.height(8)),
                Row(
                  children: [
                    _buildSummaryStatTile('Target %', '${targetPercentage.toStringAsFixed(0)}%', width: itemWidth),
                    SizedBox(width: spacing),
                    _buildSummaryStatTile('Slack', slackText, width: itemWidth, color: slackPercentage >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFEF5350)),
                    SizedBox(width: spacing),
                    _buildSummaryStatTile('Remaining', futureScheduled.toString(), width: itemWidth),
                    SizedBox(width: spacing),
                    _buildSummaryStatTile(
                      'Bunkable',
                      '${bunkable >= 0 ? '' : '-'}${bunkable.abs()}',
                      width: itemWidth,
                      color: bunkable > 0
                          ? const Color(0xFF4CAF50)
                          : bunkable < 0
                              ? const Color(0xFFEF5350)
                              : null,
                    ),
                  ],
                ),
              ],
            );
          },
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
                  barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
                  builder: (ctx) => AlertDialog(
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
                            barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
                            builder: (confirmCtx) => AlertDialog(
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

  Widget _buildSummaryStatTile(
    String title,
    String value, {
    required double width,
    Color? color,
  }) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final valueColor = color ?? theme.colorScheme.onSurface;

    return Container(
      width: width,
      padding: EdgeInsets.symmetric(
        horizontal: rs.width(4),
        vertical: rs.height(10),
      ),
      decoration: BoxDecoration(
        color: isDarkMode
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(rs.scale(14)),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: rs.font(11),
              color: theme.textTheme.bodySmall?.color,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: rs.height(4)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: rs.font(14),
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
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
          borderRadius: BorderRadius.circular(rs.scale(12)),
          child: Opacity(
            opacity: onPressed == null ? 0.5 : 1.0,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: rs.width(12),
                vertical: rs.height(12),
              ),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
                    : theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(rs.scale(12)),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.12),
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
