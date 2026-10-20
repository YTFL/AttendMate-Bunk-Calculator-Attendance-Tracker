import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/database_service.dart';
import '../../utils/responsive_scale.dart';
import '../attendance/attendance_model.dart';
import '../planner/planned_leave_model.dart';
import '../semester/semester_model.dart';
import '../subject/subject_model.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_overlay.dart';

class WhatIfCalculatorSheet extends StatefulWidget {
  final List<Subject> subjects;
  final Map<String, List<Attendance>> recordsBySubject;
  final Semester semester;
  final String? initialSubjectId;

  const WhatIfCalculatorSheet({
    super.key,
    required this.subjects,
    required this.recordsBySubject,
    required this.semester,
    this.initialSubjectId,
  });

  @override
  State<WhatIfCalculatorSheet> createState() => _WhatIfCalculatorSheetState();
}

class _RemainingClassesResult {
  final int remainingClasses;
  final int leaveMissedClasses;

  const _RemainingClassesResult({
    required this.remainingClasses,
    required this.leaveMissedClasses,
  });
}

class _WhatIfCalculatorSheetState extends State<WhatIfCalculatorSheet> {
  late String _selectedSubjectId; // 'all' or subject.id
  int _attendNext = 0;
  int _bunkNext = 0;
  bool _isMaxActive = false;
  DateTime? _selectedTargetDate;
  bool _considerPlannedLeave = false;
  List<PlannedLeave> _plannedLeaves = [];

  final GlobalKey _bunkCalculatorCardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectedSubjectId = widget.initialSubjectId ?? 'all';
    _selectedTargetDate = widget.semester.endDate;
    _loadPlannedLeaves();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final tutorialController = Provider.of<TutorialController>(context, listen: false);
        tutorialController.addListener(_onTutorialStepChanged);
      }
    });
  }

  Future<void> _loadPlannedLeaves() async {
    final leaves = await DatabaseService().loadPlannedLeaves();
    if (mounted) {
      setState(() {
        _plannedLeaves = leaves;
      });
    }
  }

  void _onTutorialStepChanged() {
    if (!mounted) return;
    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    if (tutorialController.isActive && (tutorialController.currentStepIndex < 21 || tutorialController.currentStepIndex >= 22)) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    try {
      final tutorialController = Provider.of<TutorialController>(context, listen: false);
      tutorialController.removeListener(_onTutorialStepChanged);
    } catch (_) {}
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  int _calculateClassesHeldForSubject({
    required Subject subject,
    required List<Attendance> subjectRecords,
    required Semester semester,
    required DateTime endDate,
  }) {
    final manualOverride = subject.manualAttendanceOverride;
    DateTime countingStart = manualOverride?.effectiveFrom ?? semester.startDate;
    if (countingStart.isBefore(semester.startDate)) {
      countingStart = semester.startDate;
    }

    final recordsForSubject = subjectRecords.where((record) {
      if (record.date.isAfter(endDate)) return false;
      if (record.date.isBefore(countingStart)) return false;
      return true;
    }).toList();

    final cancelledPostOverride = recordsForSubject
        .where((record) => record.status == AttendanceStatus.cancelled)
        .length;

    final scheduledSoFarInWindow = countingStart.isAfter(endDate)
        ? 0
        : subject.getTotalScheduledClasses(countingStart, endDate);

    int heldPostOverride = scheduledSoFarInWindow - cancelledPostOverride;
    if (heldPostOverride < 0) {
      heldPostOverride = 0;
    }

    final baselineHeld = manualOverride?.classesHeld ?? 0;
    return baselineHeld + heldPostOverride;
  }

  int _calculateAttendedForSubject({
    required Subject subject,
    required List<Attendance> subjectRecords,
    required Semester semester,
    required DateTime endDate,
  }) {
    final manualOverride = subject.manualAttendanceOverride;
    DateTime countingStart = manualOverride?.effectiveFrom ?? semester.startDate;
    if (countingStart.isBefore(semester.startDate)) {
      countingStart = semester.startDate;
    }

    final recordsForSubject = subjectRecords.where((record) {
      if (record.date.isAfter(endDate)) return false;
      if (record.date.isBefore(countingStart)) return false;
      return true;
    }).toList();

    final attendedPostOverride = recordsForSubject
        .where((record) => record.status == AttendanceStatus.attended)
        .length;

    final baselineAttended = manualOverride?.classesAttended ?? 0;
    return baselineAttended + attendedPostOverride;
  }

  _RemainingClassesResult _countClassesUpToDate(Subject subject, DateTime targetDate, bool considerLeave) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final horizonDate = targetDate.isAfter(widget.semester.endDate) ? widget.semester.endDate : targetDate;
    final horizonDay = DateTime(horizonDate.year, horizonDate.month, horizonDate.day, 23, 59, 59);

    if (today.isAfter(horizonDay)) {
      return const _RemainingClassesResult(remainingClasses: 0, leaveMissedClasses: 0);
    }

    final manualOverride = subject.manualAttendanceOverride;
    DateTime countingStart = manualOverride?.effectiveFrom ?? widget.semester.startDate;
    if (countingStart.isBefore(widget.semester.startDate)) {
      countingStart = widget.semester.startDate;
    }
    final countingStartDay = DateTime(countingStart.year, countingStart.month, countingStart.day);

    final tomorrow = today.add(const Duration(days: 1));
    final startDay = tomorrow.isBefore(countingStartDay) ? countingStartDay : tomorrow;

    final activeLeaves = considerLeave
        ? _plannedLeaves.where((leave) {
            final leaveEndDay = DateTime(leave.endDate.year, leave.endDate.month, leave.endDate.day);
            if (leaveEndDay.isBefore(startDay)) return false;
            if (leave.affectedSubjectIds.isNotEmpty && !leave.affectedSubjectIds.contains(subject.id)) {
              return false;
            }
            return true;
          }).toList()
        : const <PlannedLeave>[];

    int remaining = 0;
    int leaveMissed = 0;

    DateTime cur = startDay;
    while (!cur.isAfter(horizonDay)) {
      for (final slot in subject.schedule) {
        if (slot.occursOnDate(cur)) {
          final slotStart = DateTime(cur.year, cur.month, cur.day, slot.startTime.hour, slot.startTime.minute);
          final slotEnd = DateTime(cur.year, cur.month, cur.day, slot.endTime.hour, slot.endTime.minute);

          if (slotStart.isAfter(horizonDate)) continue;

          final isCoveredByLeave = activeLeaves.any((leave) =>
            slotStart.isBefore(leave.endDate) && slotEnd.isAfter(leave.startDate));

          if (isCoveredByLeave) {
            leaveMissed++;
          } else {
            remaining++;
          }
        }
      }
      cur = cur.add(const Duration(days: 1));
    }

    return _RemainingClassesResult(
      remainingClasses: remaining,
      leaveMissedClasses: leaveMissed,
    );
  }

  Future<DateTime?> _pickDateWithGlassTheme({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select Horizon End Date',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? const ColorScheme.dark(
                    primary: Color(0xFF6C63FF),
                    onPrimary: Colors.white,
                    surface: Color(0xFF14141A),
                    onSurface: Colors.white,
                  )
                : const ColorScheme.light(
                    primary: Color(0xFF6C63FF),
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Color(0xFF1C1C1E),
                  ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
          child: child!,
        );
      },
    );
  }

  void _applyMaxTargetSimulation(int mustAttend, int canBunk) {
    setState(() {
      _isMaxActive = true;
      _attendNext = mustAttend;
      _bunkNext = canBunk;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDate = today.isAfter(widget.semester.endDate) ? widget.semester.endDate : today;

    // Calculate current totals matching the semester details screen
    int currentAttended = 0;
    int currentHeld = 0;
    int leaveMissedTotal = 0;
    int totalRemaining = 0;

    final targetHorizon = _selectedTargetDate ?? widget.semester.endDate;
    Subject? selectedSubject;

    if (_selectedSubjectId == 'all') {
      for (final subject in widget.subjects) {
        final records = widget.recordsBySubject[subject.id] ?? const [];
        currentHeld += _calculateClassesHeldForSubject(
          subject: subject,
          subjectRecords: records,
          semester: widget.semester,
          endDate: endDate,
        );
        currentAttended += _calculateAttendedForSubject(
          subject: subject,
          subjectRecords: records,
          semester: widget.semester,
          endDate: endDate,
        );

        final res = _countClassesUpToDate(subject, targetHorizon, _considerPlannedLeave);
        totalRemaining += res.remainingClasses;
        leaveMissedTotal += res.leaveMissedClasses;
      }
    } else {
      selectedSubject = widget.subjects.firstWhere(
        (s) => s.id == _selectedSubjectId,
        orElse: () => widget.subjects.first,
      );
      final records = widget.recordsBySubject[selectedSubject.id] ?? const [];
      currentHeld = _calculateClassesHeldForSubject(
        subject: selectedSubject,
        subjectRecords: records,
        semester: widget.semester,
        endDate: endDate,
      );
      currentAttended = _calculateAttendedForSubject(
        subject: selectedSubject,
        subjectRecords: records,
        semester: widget.semester,
        endDate: endDate,
      );

      final res = _countClassesUpToDate(selectedSubject, targetHorizon, _considerPlannedLeave);
      totalRemaining = res.remainingClasses;
      leaveMissedTotal = res.leaveMissedClasses;
    }

    final double targetPercentage = selectedSubject != null
        ? selectedSubject.targetAttendance.toDouble()
        : widget.semester.targetPercentage;
    final double targetRatio = targetPercentage / 100.0;

    // Target breakdown calculations up to selected horizon
    final int effectiveCurrentHeld = currentHeld + leaveMissedTotal;
    final int endHorizonTotalHeld = effectiveCurrentHeld + totalRemaining;
    final int targetAttendedNeeded = (targetRatio * endHorizonTotalHeld).ceil();
    final int mustAttend = (targetAttendedNeeded - currentAttended).clamp(0, totalRemaining);
    final int canBunk = (totalRemaining - mustAttend).clamp(0, totalRemaining);

    // Auto-adjust values if MAX is active or if total simulated exceeds total remaining
    if (_isMaxActive) {
      _attendNext = mustAttend;
      _bunkNext = canBunk;
    } else if ((_attendNext + _bunkNext) > totalRemaining) {
      _attendNext = _attendNext.clamp(0, totalRemaining);
      _bunkNext = _bunkNext.clamp(0, totalRemaining - _attendNext);
    }

    final bool canIncrementMore = (_attendNext + _bunkNext) < totalRemaining;

    // Simulated totals
    final int simulatedAttended = currentAttended + _attendNext;
    final int simulatedHeld = effectiveCurrentHeld + _attendNext + _bunkNext;

    final double currentRatio = effectiveCurrentHeld > 0 ? (currentAttended / effectiveCurrentHeld) * 100 : 100.0;
    final double simulatedRatio = simulatedHeld > 0 ? (simulatedAttended / simulatedHeld) * 100 : 100.0;
    final double delta = simulatedRatio - currentRatio;

    final bool isAboveTarget = simulatedRatio >= targetPercentage;

    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    tutorialController.registerKey('key_bunk_calculator_card', _bunkCalculatorCardKey);

    return TutorialOverlay(
      child: KeyedSubtree(
        key: _bunkCalculatorCardKey,
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(rs.scale(28))),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF121218).withValues(alpha: 0.72)
                    : Colors.white.withValues(alpha: 0.78),
                borderRadius: BorderRadius.vertical(top: Radius.circular(rs.scale(28))),
                border: Border(
                  top: BorderSide(
                    color: isDarkMode
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.60),
                    width: 1.0,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.45 : 0.12),
                    blurRadius: 32,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              padding: EdgeInsets.fromLTRB(
                rs.scale(20),
                rs.scale(12),
                rs.scale(20),
                MediaQuery.of(context).viewInsets.bottom + rs.scale(24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag Handle
                    Center(
                      child: Container(
                        width: rs.width(40),
                        height: rs.height(4.5),
                        margin: EdgeInsets.only(bottom: rs.height(14)),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.22)
                              : Colors.black.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(rs.scale(3)),
                        ),
                      ),
                    ),

                    // Header Row with Reset & Close Triggers
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(rs.scale(10)),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(alpha: 0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Icon(
                            Icons.calculate_rounded,
                            color: theme.colorScheme.primary,
                            size: rs.scale(20),
                          ),
                        ),
                        SizedBox(width: rs.width(10)),
                        Text(
                          'Bunk Calculator',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(18),
                            fontWeight: FontWeight.w800,
                            color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const Spacer(),
                        if (_attendNext > 0 || _bunkNext > 0)
                          Container(
                            margin: EdgeInsets.only(right: rs.width(6)),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.04),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDarkMode
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.06),
                                width: 0.8,
                              ),
                            ),
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints.tightFor(
                                width: rs.scale(34),
                                height: rs.scale(34),
                              ),
                              tooltip: 'Reset Simulation',
                              icon: Icon(
                                Icons.refresh_rounded,
                                size: rs.scale(18),
                                color: isDarkMode ? Colors.white70 : Colors.black87,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isMaxActive = false;
                                  _attendNext = 0;
                                  _bunkNext = 0;
                                });
                              },
                            ),
                          ),
                        Container(
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.black.withValues(alpha: 0.06),
                              width: 0.8,
                            ),
                          ),
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints.tightFor(
                              width: rs.scale(34),
                              height: rs.scale(34),
                            ),
                            icon: Icon(
                              Icons.close_rounded,
                              size: rs.scale(18),
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(14)),

                    // 1. HERO SIMULATION DISPLAY CONSOLE (The focal projection cockpit)
                    Container(
                      padding: rs.insetsAll(16),
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.white.withValues(alpha: 0.60),
                        borderRadius: BorderRadius.circular(rs.scale(22)),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 0.8,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PROJECTED ATTENDANCE',
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(9.5),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                      color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                                    ),
                                  ),
                                  SizedBox(height: rs.height(3)),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        '${simulatedRatio.toStringAsFixed(1)}%',
                                        style: GoogleFonts.inter(
                                          fontSize: rs.font(28),
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.6,
                                          color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                                        ),
                                      ),
                                      SizedBox(width: rs.width(8)),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: rs.width(7), vertical: rs.height(2.5)),
                                        decoration: BoxDecoration(
                                          color: delta.abs() < 0.05
                                              ? (isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04))
                                              : (delta > 0
                                                  ? const Color(0xFF34C759).withValues(alpha: 0.10)
                                                  : const Color(0xFFFF453A).withValues(alpha: 0.10)),
                                          borderRadius: BorderRadius.circular(rs.scale(8)),
                                        ),
                                        child: Text(
                                          '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}%',
                                          style: GoogleFonts.inter(
                                            fontSize: rs.font(11.5),
                                            fontWeight: FontWeight.w700,
                                            color: delta.abs() < 0.05
                                                ? (isDarkMode ? Colors.white70 : Colors.black54)
                                                : (delta > 0
                                                    ? const Color(0xFF34C759)
                                                    : const Color(0xFFFF453A)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: rs.width(9), vertical: rs.height(4)),
                                decoration: BoxDecoration(
                                  color: isAboveTarget
                                      ? const Color(0xFF34C759).withValues(alpha: 0.08)
                                      : const Color(0xFFFF453A).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(rs.scale(10)),
                                  border: Border.all(
                                    color: isAboveTarget
                                        ? const Color(0xFF34C759).withValues(alpha: 0.18)
                                        : const Color(0xFFFF453A).withValues(alpha: 0.18),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isAboveTarget ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                      size: rs.scale(12),
                                      color: isAboveTarget ? const Color(0xFF34C759) : const Color(0xFFFF453A),
                                    ),
                                    SizedBox(width: rs.width(5)),
                                    Text(
                                      isAboveTarget ? 'ON TARGET' : 'BELOW TARGET',
                                      style: GoogleFonts.inter(
                                        color: isAboveTarget ? const Color(0xFF34C759) : const Color(0xFFFF453A),
                                        fontSize: rs.font(10),
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: rs.height(13)),
                          // Flat Single Color Progress Bar with Target Needle
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              final clampedSimPct = (simulatedRatio / 100.0).clamp(0.0, 1.0);
                              final targetPos = (targetPercentage / 100.0).clamp(0.0, 1.0) * width;
                              final barHeight = rs.height(8.0);

                              return SizedBox(
                                height: barHeight,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    Container(
                                      width: width,
                                      height: barHeight,
                                      decoration: BoxDecoration(
                                        color: isDarkMode
                                            ? Colors.white.withValues(alpha: 0.10)
                                            : Colors.black.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(rs.scale(4)),
                                      ),
                                    ),
                                    Container(
                                      width: width * clampedSimPct,
                                      height: barHeight,
                                      decoration: BoxDecoration(
                                        color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                                        borderRadius: BorderRadius.circular(rs.scale(4)),
                                      ),
                                    ),
                                    Positioned(
                                      left: (targetPos - rs.scale(1.2)).clamp(0.0, width - rs.scale(2.4)),
                                      top: -rs.scale(2.5),
                                      bottom: -rs.scale(2.5),
                                      child: Container(
                                        width: rs.scale(2.4),
                                        decoration: BoxDecoration(
                                          color: isDarkMode ? Colors.white : Colors.black,
                                          borderRadius: BorderRadius.circular(rs.scale(1.2)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          SizedBox(height: rs.height(11)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Simulated: $simulatedAttended / $simulatedHeld',
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(11),
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                                ),
                              ),
                              Text(
                                'Current: ${currentRatio.toStringAsFixed(1)}%',
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(11),
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                                ),
                              ),
                              Text(
                                'Target: ${targetPercentage.toStringAsFixed(0)}%',
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(11),
                                  fontWeight: FontWeight.w700,
                                  color: isDarkMode ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: rs.height(12)),

                    // 2. CONTEXT SELECTORS (Subject & Horizon Controls)
                    Row(
                      children: [
                        // Subject Selector Capsule
                        Expanded(
                          child: Container(
                            height: rs.height(46),
                            padding: rs.insetsSymmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(rs.scale(16)),
                              border: Border.all(
                                color: isDarkMode
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.black.withValues(alpha: 0.08),
                                width: 0.8,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedSubjectId,
                                isExpanded: true,
                                icon: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: isDarkMode ? Colors.white70 : Colors.black87,
                                  size: rs.scale(18),
                                ),
                                dropdownColor: isDarkMode ? const Color(0xFF16161E) : Colors.white,
                                borderRadius: BorderRadius.circular(rs.scale(16)),
                                items: [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text(
                                      'All Subjects',
                                      style: GoogleFonts.inter(
                                        fontSize: rs.font(12.5),
                                        fontWeight: FontWeight.w600,
                                        color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                                      ),
                                    ),
                                  ),
                                  ...widget.subjects.map(
                                    (s) => DropdownMenuItem(
                                      value: s.id,
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: s.color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          SizedBox(width: rs.width(6)),
                                          Expanded(
                                            child: Text(
                                              s.acronym ?? s.name,
                                              style: GoogleFonts.inter(
                                                fontSize: rs.font(12.5),
                                                fontWeight: FontWeight.w600,
                                                color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedSubjectId = val;
                                      _isMaxActive = false;
                                      _attendNext = 0;
                                      _bunkNext = 0;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: rs.width(8)),
                        // Horizon End Date Picker Capsule
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final today = DateTime(now.year, now.month, now.day);
                              final picked = await _pickDateWithGlassTheme(
                                context: context,
                                initialDate: _selectedTargetDate ?? widget.semester.endDate,
                                firstDate: today,
                                lastDate: widget.semester.endDate,
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedTargetDate = picked;
                                  if (!_isMaxActive) {
                                    _attendNext = 0;
                                    _bunkNext = 0;
                                  }
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(rs.scale(16)),
                            child: Container(
                              height: rs.height(46),
                              padding: rs.insetsSymmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: isDarkMode
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(rs.scale(16)),
                                border: Border.all(
                                  color: isDarkMode
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : Colors.black.withValues(alpha: 0.08),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: rs.scale(13),
                                    color: theme.colorScheme.primary,
                                  ),
                                  SizedBox(width: rs.width(6)),
                                  Expanded(
                                    child: Text(
                                      _selectedTargetDate == null ||
                                              _isSameDay(_selectedTargetDate!, widget.semester.endDate)
                                          ? 'Semester End'
                                          : DateFormat.MMMd().format(_selectedTargetDate!),
                                      style: GoogleFonts.inter(
                                        fontSize: rs.font(12.5),
                                        fontWeight: FontWeight.w600,
                                        color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (_selectedTargetDate != null &&
                                      !_isSameDay(_selectedTargetDate!, widget.semester.endDate))
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedTargetDate = widget.semester.endDate;
                                          if (!_isMaxActive) {
                                            _attendNext = 0;
                                            _bunkNext = 0;
                                          }
                                        });
                                      },
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: rs.scale(14),
                                        color: isDarkMode ? Colors.white70 : Colors.black87,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: rs.height(8)),

                    // Horizon Controls: Planned Leave Toggle & MAX Quick Trigger
                    Row(
                      children: [
                        // Planned Leave Toggle Chip
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _considerPlannedLeave = !_considerPlannedLeave;
                              });
                            },
                            borderRadius: BorderRadius.circular(rs.scale(12)),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: rs.width(10), vertical: rs.height(7)),
                              decoration: BoxDecoration(
                                color: _considerPlannedLeave
                                    ? theme.colorScheme.primary.withValues(alpha: 0.12)
                                    : (isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
                                borderRadius: BorderRadius.circular(rs.scale(12)),
                                border: Border.all(
                                  color: _considerPlannedLeave
                                      ? theme.colorScheme.primary.withValues(alpha: 0.35)
                                      : Colors.transparent,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _considerPlannedLeave ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                    size: rs.scale(16),
                                    color: _considerPlannedLeave ? theme.colorScheme.primary : (isDarkMode ? Colors.white54 : Colors.black45),
                                  ),
                                  SizedBox(width: rs.width(6)),
                                  Expanded(
                                    child: Text(
                                      'Include Planned Leaves',
                                      style: GoogleFonts.inter(
                                        fontSize: rs.font(11.5),
                                        fontWeight: FontWeight.w600,
                                        color: _considerPlannedLeave
                                            ? (isDarkMode ? Colors.white : const Color(0xFF1C1C1E))
                                            : (isDarkMode ? Colors.white60 : Colors.black54),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: rs.width(8)),
                        // MAX Simulation Quick Button
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(rs.scale(12)),
                            onTap: () => _applyMaxTargetSimulation(mustAttend, canBunk),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: EdgeInsets.symmetric(horizontal: rs.width(12), vertical: rs.height(7)),
                              decoration: BoxDecoration(
                                color: _isMaxActive
                                    ? const Color(0xFFFF9F0A).withValues(alpha: 0.18)
                                    : (isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
                                borderRadius: BorderRadius.circular(rs.scale(12)),
                                border: Border.all(
                                  color: _isMaxActive
                                      ? const Color(0xFFFF9F0A).withValues(alpha: 0.5)
                                      : (isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08)),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.bolt_rounded,
                                    size: rs.scale(16),
                                    color: _isMaxActive
                                        ? const Color(0xFFFF9F0A)
                                        : (isDarkMode ? Colors.white70 : Colors.black87),
                                  ),
                                  SizedBox(width: rs.width(4)),
                                  Text(
                                    'MAX',
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(11.5),
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.4,
                                      color: _isMaxActive
                                          ? const Color(0xFFFF9F0A)
                                          : (isDarkMode ? Colors.white : const Color(0xFF1C1C1E)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: rs.height(14)),

                    // 3. DECISION CARDS: MUST ATTEND vs CAN BUNK
                    Row(
                      children: [
                        // Must Attend Card
                        Expanded(
                          child: Container(
                            padding: rs.insetsAll(13),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(rs.scale(18)),
                              border: Border.all(
                                color: isDarkMode
                                    ? Colors.white.withValues(alpha: 0.10)
                                    : Colors.black.withValues(alpha: 0.08),
                                width: 0.8,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.task_alt_rounded,
                                      size: rs.scale(14),
                                      color: const Color(0xFF34C759),
                                    ),
                                    SizedBox(width: rs.width(5)),
                                    Text(
                                      'MUST ATTEND',
                                      style: GoogleFonts.inter(
                                        fontSize: rs.font(10),
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                        color: const Color(0xFF34C759),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: rs.height(4)),
                                Text(
                                  '$mustAttend',
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(24),
                                    fontWeight: FontWeight.w900,
                                    color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                                  ),
                                ),
                                SizedBox(height: rs.height(2)),
                                Text(
                                  'to maintain ${targetPercentage.toStringAsFixed(0)}%',
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(10.5),
                                    color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: rs.width(10)),
                        // Can Bunk Card
                        Expanded(
                          child: Container(
                            padding: rs.insetsAll(13),
                            decoration: BoxDecoration(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(rs.scale(18)),
                              border: Border.all(
                                color: isDarkMode
                                    ? Colors.white.withValues(alpha: 0.10)
                                    : Colors.black.withValues(alpha: 0.08),
                                width: 0.8,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.beach_access_rounded,
                                      size: rs.scale(14),
                                      color: const Color(0xFFFF9F0A),
                                    ),
                                    SizedBox(width: rs.width(5)),
                                    Text(
                                      'CAN BUNK',
                                      style: GoogleFonts.inter(
                                        fontSize: rs.font(10),
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.4,
                                        color: const Color(0xFFFF9F0A),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: rs.height(4)),
                                Text(
                                  '$canBunk',
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(24),
                                    fontWeight: FontWeight.w900,
                                    color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                                  ),
                                ),
                                SizedBox(height: rs.height(2)),
                                Text(
                                  'safe absences left',
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(10.5),
                                    color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: rs.height(8)),

                    // Subtle telemetry context text
                    Padding(
                      padding: rs.insetsSymmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Conducted: $currentHeld classes',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(11),
                              fontWeight: FontWeight.w500,
                              color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                            ),
                          ),
                          Text(
                            'Remaining: $totalRemaining classes',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(11),
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_considerPlannedLeave && leaveMissedTotal > 0)
                      Padding(
                        padding: EdgeInsets.only(top: rs.height(4), left: rs.width(4)),
                        child: Text(
                          '• Includes $leaveMissedTotal planned leave class${leaveMissedTotal == 1 ? '' : 'es'} (marked missed)',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(10.5),
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFFFF9F0A),
                          ),
                        ),
                      ),

                    SizedBox(height: rs.height(14)),

                    // 4. DUAL TACTILE STEPPERS
                    Row(
                      children: [
                        Expanded(
                          child: _buildStepperCard(
                            context: context,
                            rs: rs,
                            title: 'Attend Next',
                            value: _attendNext,
                            color: const Color(0xFF34C759),
                            icon: Icons.add_task_rounded,
                            onIncrement: canIncrementMore
                                ? () => setState(() {
                                      _isMaxActive = false;
                                      _attendNext++;
                                    })
                                : null,
                            onDecrement: _attendNext > 0
                                ? () => setState(() {
                                      _isMaxActive = false;
                                      _attendNext--;
                                    })
                                : null,
                          ),
                        ),
                        SizedBox(width: rs.width(10)),
                        Expanded(
                          child: _buildStepperCard(
                            context: context,
                            rs: rs,
                            title: 'Bunk Next',
                            value: _bunkNext,
                            color: const Color(0xFFFF453A),
                            icon: Icons.event_busy_rounded,
                            onIncrement: canIncrementMore
                                ? () => setState(() {
                                      _isMaxActive = false;
                                      _bunkNext++;
                                    })
                                : null,
                            onDecrement: _bunkNext > 0
                                ? () => setState(() {
                                      _isMaxActive = false;
                                      _bunkNext--;
                                    })
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepperCard({
    required BuildContext context,
    required ResponsiveScale rs,
    required String title,
    required int value,
    required Color color,
    required IconData icon,
    required VoidCallback? onIncrement,
    required VoidCallback? onDecrement,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: rs.insetsAll(14),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(rs.scale(18)),
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: rs.scale(13), color: color),
              SizedBox(width: rs.width(5)),
              Text(
                title.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: rs.font(10.5),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(10)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onDecrement,
                  borderRadius: BorderRadius.circular(rs.scale(12)),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(rs.scale(10)),
                      border: Border.all(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      Icons.remove_rounded,
                      size: rs.scale(18),
                      color: onDecrement != null
                          ? (isDarkMode ? Colors.white : Colors.black87)
                          : (isDarkMode ? Colors.white24 : Colors.black26),
                    ),
                  ),
                ),
              ),
              Text(
                '$value',
                style: GoogleFonts.inter(
                  fontSize: rs.font(24),
                  fontWeight: FontWeight.w800,
                  color: value > 0
                      ? color
                      : (isDarkMode ? Colors.white : const Color(0xFF1C1C1E)),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onIncrement,
                  borderRadius: BorderRadius.circular(rs.scale(12)),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(rs.scale(10)),
                      border: Border.all(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: rs.scale(18),
                      color: onIncrement != null
                          ? (isDarkMode ? Colors.white : Colors.black87)
                          : (isDarkMode ? Colors.white24 : Colors.black26),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
