import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../utils/attendance_math.dart';
import '../../utils/responsive_scale.dart';
import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';
import '../semester/semester_model.dart';
import '../semester/semester_provider.dart';
import '../../utils/string_extension.dart';
import '../../services/database_service.dart';
import '../planner/planned_leave_model.dart';
import '../planner/projected_attendance_calculator.dart';
import '../planner/leave_planner_screen.dart';
import '../calendar/calendar_screen.dart';
import '../tutorial/tutorial_controller.dart';
import 'what_if_calculator_sheet.dart';

class BunkMeterScreen extends StatefulWidget {
  const BunkMeterScreen({super.key});

  @override
  State<BunkMeterScreen> createState() => _BunkMeterScreenState();
}

class _BunkMeterScreenState extends State<BunkMeterScreen> {
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey _bunkCalculatorKey = GlobalKey();
  final GlobalKey _leavePlannerKey = GlobalKey();
  String _searchQuery = '';
  final Set<String> _expandedSubjectIds = <String>{};
  List<PlannedLeave> _plannedLeaves = [];

  @override
  void initState() {
    super.initState();
    _loadPlannedLeaves();
  }

  Future<void> _loadPlannedLeaves() async {
    final leaves = await DatabaseService().loadPlannedLeaves();
    if (mounted) {
      setState(() {
        _plannedLeaves = leaves;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    tutorialController.registerKey('appbar_bunk_calculator', _bunkCalculatorKey);
    tutorialController.registerKey('appbar_leave_planner', _leavePlannerKey);

    // By using Provider.of, this widget will rebuild when SubjectProvider notifies its listeners
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final attendanceProvider = Provider.of<AttendanceProvider>(context);
    final subjects = subjectProvider.subjects;
    final semester = semesterProvider.semester;

    if (semester == null) {
      return const Center(child: Text('Please set a semester first.'));
    }

    // Check if the semester has started yet
    if (!semesterProvider.hasSemesterStarted) {
      final startDate = semester.startDate;
      final formattedDate = '${startDate.day}/${startDate.month}/${startDate.year}';
      return Center(
        child: Padding(
          padding: rs.insetsAll(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pending_actions, size: rs.scale(50), color: Colors.blue),
              SizedBox(height: rs.height(16)),
              Text(
                'Semester Yet to Begin',
                style: TextStyle(fontSize: rs.font(22), fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: rs.height(8)),
              Text(
                'Your semester will start on $formattedDate. The bunk meter will be available from that date.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: rs.font(16)),
              ),
              SizedBox(height: rs.height(24)),
              ElevatedButton.icon(
                icon: const Icon(Icons.calendar_month),
                label: const Text('View Attendance Calendar'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CalendarScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }
    
    // Show info banner if semester has ended
    final bool semesterEnded = semesterProvider.hasSemesterEnded;

    if (subjects.isEmpty) {
      return const Center(child: Text('No subjects added yet.'));
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day); // Normalize to midnight
    final endDate = today.isAfter(semester.endDate) ? semester.endDate : today;

    // Pre-group/index all attendance records by subjectId to avoid O(S * R) scans
    final Map<String, List<Attendance>> recordsBySubject = {};
    for (final record in attendanceProvider.attendanceRecords) {
      recordsBySubject.putIfAbsent(record.subjectId, () => []).add(record);
    }

    // Precompute snapshots for all subjects to avoid O(N log N) recalculation during sorting
    // and redundant calculations in ListView.builder.
    final Map<String, _SubjectAttendanceSnapshot> snapshots = {
      for (final subject in subjects)
        subject.id: _buildAttendanceSnapshot(
          subject: subject,
          subjectRecords: recordsBySubject[subject.id] ?? const [],
          semester: semester,
          endDate: endDate,
        )
    };

    // Sort subjects: ones that need attendance first, then alphabetically
    final sortedSubjects = _getSortedSubjects(
      subjects,
      snapshots,
      semester,
    );

    // Filter subjects based on search query
    final filteredSubjects = _searchQuery.isEmpty
        ? sortedSubjects
        : sortedSubjects.where((subject) {
            return subject.matchesSearchQuery(_searchQuery);
          }).toList();

    return Column(
      children: [
        if (semesterEnded)
          Container(
            padding: rs.insetsAll(12),
            margin: rs.insetsAll(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(rs.scale(8)),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: rs.scale(20)),
                SizedBox(width: rs.width(8)),
                Expanded(
                  child: Text(
                    'Semester ended on ${semester.endDate.day}/${semester.endDate.month}/${semester.endDate.year}. Showing final attendance data.',
                    style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        // Search field (Tesla x Nothing Obsidian Capsule)
        Builder(
          builder: (context) {
            final isDarkMode = Theme.of(context).brightness == Brightness.dark;
            final searchBg = isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.60);
            final searchBorder = isDarkMode ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.08);

            return Padding(
              padding: rs.insetsSymmetric(horizontal: 16, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(rs.scale(28)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: searchBg,
                      borderRadius: BorderRadius.circular(rs.scale(28)),
                      border: Border.all(color: searchBorder, width: 0.9),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.inter(
                        fontSize: rs.font(13.5),
                        fontWeight: FontWeight.w500,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search for a class...',
                        hintStyle: GoogleFonts.inter(
                          fontSize: rs.font(13),
                          color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF8E8E93),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: rs.scale(18),
                          color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: rs.scale(16),
                                  color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                    _searchQuery = '';
                                  });
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        fillColor: Colors.transparent,
                        contentPadding: rs.insetsSymmetric(vertical: 12, horizontal: 16),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        // Action toolbar: Bunk Calculator & Leave Planner (Liquid Glass Dual Console)
        Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final isDarkMode = theme.brightness == Brightness.dark;
            final cardBg = isDarkMode
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.65);
            final cardBorder = isDarkMode
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.60);
            final textColor = isDarkMode ? Colors.white : const Color(0xFF1C1C1E);

            final calcBadgeBg = isDarkMode
                ? theme.colorScheme.primary.withValues(alpha: 0.16)
                : theme.colorScheme.primary.withValues(alpha: 0.12);
            final calcIconColor = theme.colorScheme.primary;

            final plannerBadgeBg = isDarkMode
                ? const Color(0xFFFF9F0A).withValues(alpha: 0.16)
                : const Color(0xFFFF9500).withValues(alpha: 0.12);
            final plannerIconColor = isDarkMode
                ? const Color(0xFFFF9F0A)
                : const Color(0xFFD97706);

            return Padding(
              padding: rs.insetsSymmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: KeyedSubtree(
                      key: _bunkCalculatorKey,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(rs.scale(22)),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Material(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(rs.scale(22)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(rs.scale(22)),
                              onTap: () {
                                if (tutorialController.isActive && tutorialController.currentStepIndex == 20) {
                                  tutorialController.nextStep();
                                }
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  barrierColor: isDarkMode
                                      ? Colors.black.withValues(alpha: 0.65)
                                      : Colors.black38,
                                  backgroundColor: Colors.transparent,
                                  sheetAnimationStyle: AnimationStyle(
                                    duration: const Duration(milliseconds: 320),
                                    reverseDuration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOutCubic,
                                    reverseCurve: Curves.easeInCubic,
                                  ),
                                  builder: (ctx) => WhatIfCalculatorSheet(
                                    subjects: subjects,
                                    recordsBySubject: recordsBySubject,
                                    semester: semester,
                                  ),
                                );
                              },
                              child: Container(
                                padding: rs.insetsSymmetric(vertical: 12, horizontal: 14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(rs.scale(22)),
                                  border: Border.all(color: cardBorder, width: 0.8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: calcBadgeBg,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: calcIconColor.withValues(alpha: 0.25),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.calculate_outlined,
                                        color: calcIconColor,
                                        size: rs.scale(16),
                                      ),
                                    ),
                                    SizedBox(width: rs.width(8)),
                                    Flexible(
                                      child: Text(
                                        'Bunk Calculator',
                                        style: GoogleFonts.inter(
                                          fontSize: rs.font(12.5),
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                          color: textColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: rs.width(10)),
                  Expanded(
                    child: KeyedSubtree(
                      key: _leavePlannerKey,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(rs.scale(22)),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: Material(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(rs.scale(22)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(rs.scale(22)),
                              onTap: () async {
                                if (tutorialController.isActive && tutorialController.currentStepIndex == 22) {
                                  tutorialController.nextStep();
                                }
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const LeavePlannerScreen()),
                                );
                                _loadPlannedLeaves();
                              },
                              child: Container(
                                padding: rs.insetsSymmetric(vertical: 12, horizontal: 14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(rs.scale(22)),
                                  border: Border.all(color: cardBorder, width: 0.8),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: plannerBadgeBg,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: plannerIconColor.withValues(alpha: 0.25),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.event_available_outlined,
                                        color: plannerIconColor,
                                        size: rs.scale(16),
                                      ),
                                    ),
                                    SizedBox(width: rs.width(8)),
                                    Flexible(
                                      child: Text(
                                        'Leave Planner',
                                        style: GoogleFonts.inter(
                                          fontSize: rs.font(12.5),
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                          color: textColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        // Show count of filtered results
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: rs.insetsSymmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Found ${filteredSubjects.length} class${filteredSubjects.length == 1 ? '' : 'es'}',
                style: GoogleFonts.roboto(
                  fontSize: rs.font(11.5),
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF8E8E93)
                      : const Color(0xFF636366),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        Expanded(
          child: filteredSubjects.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off_rounded, size: rs.scale(56), color: Colors.grey.shade400),
                      SizedBox(height: rs.height(14)),
                      Text(
                        'No classes found',
                        style: GoogleFonts.roboto(
                          fontSize: rs.font(16),
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : Colors.grey.shade700,
                        ),
                      ),
                      SizedBox(height: rs.height(4)),
                      Text(
                        'Try a different search term',
                        style: GoogleFonts.roboto(fontSize: rs.font(13), color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  key: ValueKey(Theme.of(context).brightness),
                  padding: EdgeInsets.fromLTRB(rs.scale(16), rs.scale(8), rs.scale(16), rs.scale(140)),
                  itemCount: filteredSubjects.length,
                  itemBuilder: (context, index) {
                    final subject = filteredSubjects[index];
                    final snapshot = snapshots[subject.id]!;
                    final isExpanded = _expandedSubjectIds.contains(subject.id);

                    final subjectProjection = ProjectedAttendanceCalculator.calculateForSubject(
                      subject: subject,
                      attendanceRecords: attendanceProvider.attendanceRecords,
                      semester: semester,
                      plannedLeaves: _plannedLeaves,
                    );

                    final classesHeldSoFar = snapshot.classesHeldSoFar;
                    final attendedClasses = snapshot.attendedClasses;
                    final absentClasses = snapshot.absentClasses;
                    final markedClasses = snapshot.markedClasses;
                    final currentPercentage =
                        (markedClasses == 0) ? 100.0 : (attendedClasses / markedClasses) * 100;

                    // Calculate future bunking ability or required attendance
                    String message;
                    Color messageColor;
                    String compactStatus;

                    if (snapshot.totalClassesInWindow == 0 && snapshot.classesHeldSoFar == 0) {
                      message = 'No classes scheduled for this subject in the semester.';
                      compactStatus = 'No classes scheduled for this subject in the semester.';
                      messageColor = Colors.grey;
                    } else {
                      final currentRatio = (markedClasses == 0)
                          ? 1.0
                          : (attendedClasses / markedClasses);

                      final double targetPercentage = subject.targetAttendance / 100.0;

                      int futureScheduled = snapshot.totalClassesInWindow - snapshot.scheduledSoFarInWindow;
                      if (futureScheduled < 0) {
                        futureScheduled = 0;
                      }

                      if (currentRatio >= targetPercentage) {
                        // Already at or above target
                        final maxBunkable = AttendanceMath.calculateBunkableClasses(
                          attended: attendedClasses,
                          marked: markedClasses,
                          targetPercentage: subject.targetAttendance.toDouble(),
                        );
                        final bunkable = maxBunkable.clamp(0, futureScheduled);

                        if (bunkable == 0) {
                          message = 'You currently cannot bunk anymore classes';
                          compactStatus = 'Can\'t bunk';
                        } else {
                          message = 'You can bunk next $bunkable classes continously';
                          compactStatus = 'Bunkable: $bunkable';
                        }
                        messageColor = Colors.green.shade700;
                      } else {
                        // Below target - need to attend more classes
                        final neededClasses = AttendanceMath.calculateClassesNeededToReachTarget(
                          attended: attendedClasses,
                          marked: markedClasses,
                          targetPercentage: subject.targetAttendance.toDouble(),
                        );

                        // Check if target is achievable with remaining classes
                        if (neededClasses != -1 && neededClasses <= futureScheduled) {
                          message = 'Must attend next $neededClasses classes';
                          compactStatus = 'Must attend: $neededClasses';
                          messageColor = Colors.orange.shade700;
                        } else {
                          // Target is not achievable
                          final maxAttainableFuture = attendedClasses + futureScheduled;
                          final maxAttainableMarked = markedClasses + futureScheduled;
                          final maxAttainablePercentage =
                              (maxAttainableMarked == 0) ? 100.0 : (maxAttainableFuture / maxAttainableMarked) * 100;

                          message = 'Target unreachable (max ${maxAttainablePercentage.toStringAsFixed(1)}%)';
                          compactStatus = 'Can\'t reach target';
                          messageColor = Colors.red.shade700;
                        }
                      }
                    }

                    return _BunkMeterSubjectCard(
                      key: ValueKey(subject.id),
                      subject: subject,
                      snapshot: snapshot,
                      isExpanded: isExpanded,
                      onExpansionChanged: (expanded) {
                        setState(() {
                          if (expanded) {
                            _expandedSubjectIds.add(subject.id);
                          } else {
                            _expandedSubjectIds.remove(subject.id);
                          }
                        });
                      },
                      subjectProjection: subjectProjection,
                      message: message,
                      messageColor: messageColor,
                      compactStatus: compactStatus,
                      currentPercentage: currentPercentage,
                      classesHeldSoFar: classesHeldSoFar,
                      attendedClasses: attendedClasses,
                      absentClasses: absentClasses,
                      today: today,
                      subjectProvider: subjectProvider,
                      onUpdateCountsManually: () => _showManualCountUpdateDialog(
                        subject: subject,
                        subjectProvider: subjectProvider,
                        currentHeld: classesHeldSoFar,
                        currentAttended: attendedClasses,
                        effectiveFrom: today,
                      ),
                      onShowManualBaselineTooltip: () => _showManualBaselineTooltip(
                        context: context,
                        subject: subject,
                        subjectProvider: subjectProvider,
                        countingStart: snapshot.countingStart,
                      ),
                      onShowProjectedLeaveTooltip: () => _showProjectedLeaveTooltip(
                        context: context,
                        subject: subject,
                        subjectProjection: subjectProjection,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }


  /// Sort subjects: ones that need attendance (below target) first, then alphabetically
  List<Subject> _getSortedSubjects(
    List<Subject> subjects,
    Map<String, _SubjectAttendanceSnapshot> snapshots,
    Semester semester,
  ) {
    return List<Subject>.from(subjects)..sort((a, b) {
      final aNeeds = _needsAttendance(a, snapshots);
      final bNeeds = _needsAttendance(b, snapshots);

      // Classes that need attendance come first
      if (aNeeds != bNeeds) {
        return aNeeds ? -1 : 1;
      }

      // Within the same group, sort alphabetically
      return a.name.compareTo(b.name);
    });
  }

  /// Check if a subject needs attendance (is below target percentage)
  bool _needsAttendance(
    Subject subject,
    Map<String, _SubjectAttendanceSnapshot> snapshots,
  ) {
    final snapshot = snapshots[subject.id];
    if (snapshot == null) return false;

    final attendedClasses = snapshot.attendedClasses;
    final markedClasses = snapshot.markedClasses;

    // Check if below target
    if (markedClasses == 0) {
      return false; // No classes marked yet, not below target
    }

    final currentRatio = attendedClasses / markedClasses;
    final targetPercentage = subject.targetAttendance / 100.0;
    return currentRatio < targetPercentage;
  }

  _SubjectAttendanceSnapshot _buildAttendanceSnapshot({
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

    return _SubjectAttendanceSnapshot(
      totalClassesInWindow: totalClassesInWindow,
      scheduledSoFarInWindow: scheduledSoFarInWindow,
      classesHeldSoFar: baselineHeld + heldPostOverride,
      attendedClasses: baselineAttended + attendedPostOverride,
      absentClasses: baselineAbsent + absentPostOverride,
      markedClasses: baselineHeld + attendedPostOverride + absentPostOverride,
      countingStart: countingStart,
      manualOverride: manualOverride,
    );
  }

  Future<void> _showManualBaselineTooltip({
    required BuildContext context,
    required Subject subject,
    required SubjectProvider subjectProvider,
    required DateTime countingStart,
  }) async {
    final rs = context.rs;
    final theme = Theme.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rs.scale(24)),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: rs.scale(24)),
              SizedBox(width: rs.width(8)),
              Expanded(
                child: Text(
                  'Manual Baseline',
                  style: GoogleFonts.inter(fontSize: rs.font(16), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manual baseline active from ${countingStart.day}/${countingStart.month}/${countingStart.year}. Any attendance or timetable changes before this date are ignored in this card.',
                style: GoogleFonts.inter(
                  fontSize: rs.font(13),
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(rs.scale(16)),
                ),
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await subjectProvider.resetManualBaseline(subject.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Manual baseline reset for ${subject.name}.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset Baseline'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showProjectedLeaveTooltip({
    required BuildContext context,
    required Subject subject,
    required SubjectProjectedAttendance subjectProjection,
  }) async {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final plannedMissed = subjectProjection.plannedMissedCount;
    final projectedRatio = subjectProjection.projectedPercentage;
    final projectedBelowTarget = projectedRatio < subject.targetAttendance;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rs.scale(24)),
          ),
          title: Row(
            children: [
              Icon(
                Icons.event_available_outlined,
                color: projectedBelowTarget ? Colors.red : theme.colorScheme.primary,
                size: rs.scale(24),
              ),
              SizedBox(width: rs.width(8)),
              Expanded(
                child: Text(
                  'Projected (After Leave)',
                  style: TextStyle(fontSize: rs.font(16), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subject.name,
                style: TextStyle(
                  fontSize: rs.font(14),
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              SizedBox(height: rs.height(10)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: rs.width(12), vertical: rs.height(8)),
                decoration: BoxDecoration(
                  color: projectedBelowTarget
                      ? Colors.red.withValues(alpha: 0.12)
                      : (isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
                  borderRadius: BorderRadius.circular(rs.scale(16)),
                  border: Border.all(
                    color: projectedBelowTarget
                        ? Colors.red.withValues(alpha: 0.3)
                        : (isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade300),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Projected Attendance:',
                      style: TextStyle(fontSize: rs.font(12.5), fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Text(
                      '${projectedRatio.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: rs.font(14),
                        fontWeight: FontWeight.bold,
                        color: projectedBelowTarget ? Colors.red.shade700 : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: rs.height(10)),
              Text(
                '• Missed classes during leave: $plannedMissed',
                style: TextStyle(fontSize: rs.font(12.5), color: theme.colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: rs.height(4)),
              Text(
                '• Assumed present classes: ${subjectProjection.assumedPresentCount}',
                style: TextStyle(fontSize: rs.font(12.5), color: theme.colorScheme.onSurfaceVariant),
              ),
              if (subjectProjection.leaveName != null && subjectProjection.leaveName!.isNotEmpty) ...[
                SizedBox(height: rs.height(4)),
                Text(
                  '• Leave reason: ${subjectProjection.leaveName}',
                  style: TextStyle(fontSize: rs.font(12.5), color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showManualCountUpdateDialog({
    required Subject subject,
    required SubjectProvider subjectProvider,
    required int currentHeld,
    required int currentAttended,
    required DateTime effectiveFrom,
  }) async {
    final manualInput = await showModalBottomSheet<_ManualCountInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.black54
          : Colors.black26,
      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      builder: (context) => _ManualCountUpdateSheet(
        subjectName: subject.name,
        effectiveFrom: effectiveFrom,
        initialHeld: currentHeld,
        initialAttended: currentAttended,
        hasManualOverride: subject.manualAttendanceOverride != null,
      ),
    );

    if (manualInput == null || !mounted) {
      return;
    }

    if (manualInput.isReset) {
      await subjectProvider.resetManualBaseline(subject.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Manual baseline reset for ${subject.name}.'),
          ),
        );
      }
      return;
    }

    await subjectProvider.updateManualAttendanceCounts(
      subjectId: subject.id,
      classesHeld: manualInput.held,
      classesAttended: manualInput.attended,
      effectiveFrom: effectiveFrom,
    );
  }
}

class _BunkMeterSubjectCard extends StatefulWidget {
  final Subject subject;
  final _SubjectAttendanceSnapshot snapshot;
  final bool isExpanded;
  final ValueChanged<bool> onExpansionChanged;
  final SubjectProjectedAttendance subjectProjection;
  final String message;
  final Color messageColor;
  final String compactStatus;
  final double currentPercentage;
  final int classesHeldSoFar;
  final int attendedClasses;
  final int absentClasses;
  final DateTime today;
  final SubjectProvider subjectProvider;
  final VoidCallback onUpdateCountsManually;
  final VoidCallback onShowManualBaselineTooltip;
  final VoidCallback onShowProjectedLeaveTooltip;

  const _BunkMeterSubjectCard({
    super.key,
    required this.subject,
    required this.snapshot,
    required this.isExpanded,
    required this.onExpansionChanged,
    required this.subjectProjection,
    required this.message,
    required this.messageColor,
    required this.compactStatus,
    required this.currentPercentage,
    required this.classesHeldSoFar,
    required this.attendedClasses,
    required this.absentClasses,
    required this.today,
    required this.subjectProvider,
    required this.onUpdateCountsManually,
    required this.onShowManualBaselineTooltip,
    required this.onShowProjectedLeaveTooltip,
  });

  @override
  State<_BunkMeterSubjectCard> createState() => _BunkMeterSubjectCardState();
}

class _BunkMeterSubjectCardState extends State<_BunkMeterSubjectCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _iconTurns;
  late final Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: widget.isExpanded ? 1.0 : 0.0,
    );
    _iconTurns = _controller.drive(
      Tween<double>(begin: 0.0, end: 0.5).chain(
        CurveTween(curve: Curves.easeInOut),
      ),
    );
    _heightFactor = _controller.drive(
      CurveTween(curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant _BunkMeterSubjectCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    final newExpanded = !widget.isExpanded;
    if (newExpanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    widget.onExpansionChanged(newExpanded);
  }

  Widget _buildStatColumn({
    required ResponsiveScale rs,
    required bool isDarkMode,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.roboto(
            fontSize: rs.font(9.5),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
          ),
        ),
        SizedBox(height: rs.height(4)),
        Text(
          value,
          style: GoogleFonts.roboto(
            fontSize: rs.font(15),
            fontWeight: FontWeight.w700,
            color: valueColor ?? (isDarkMode ? Colors.white : const Color(0xFF1C1C1E)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDarkMode
        ? const Color(0xFF14141C).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.75);
    final cardBorder = isDarkMode
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.60);
    final recessedBg = isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03);
    final innerBorder = isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06);

    final subject = widget.subject;
    final snapshot = widget.snapshot;
    final subjectProjection = widget.subjectProjection;
    final int plannedMissed = subjectProjection.plannedMissedCount;
    final double projectedRatio = subjectProjection.projectedPercentage;
    final bool projectedBelowTarget = projectedRatio < subject.targetAttendance;

    final double targetPercent = subject.targetAttendance.toDouble();
    final double currentPct = widget.currentPercentage;
    final bool isAboveTarget = currentPct >= targetPercent;

    // Status pill colors
    final Color statusColor = isAboveTarget
        ? (isDarkMode ? const Color(0xFF34C759) : const Color(0xFF28A745))
        : (isDarkMode ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500));

    return Padding(
      padding: EdgeInsets.only(bottom: rs.scale(12)),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(rs.scale(24)),
          border: Border.all(color: cardBorder, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDarkMode ? 0.20 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(rs.scale(24)),
              onTap: _handleTap,
              child: Padding(
                padding: rs.insetsAll(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top header: Acronym Capsule + Name + Target + Badges + Arrow
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Graphite Acronym squircle badge with micro color indicator
                        Container(
                          width: rs.scale(44),
                          height: rs.scale(44),
                          decoration: BoxDecoration(
                            color: isDarkMode ? const Color(0xFF1B1B20) : const Color(0xFFF0F0F3),
                            borderRadius: BorderRadius.circular(rs.scale(16)),
                            border: Border.all(
                              color: subject.color.withValues(alpha: isDarkMode ? 0.45 : 0.35),
                              width: 1.2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              subject.acronym ?? subject.name.acronymFromName(),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: GoogleFonts.inter(
                                color: isDarkMode ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w800,
                                fontSize: rs.font(12),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: rs.width(12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subject.name,
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: rs.font(14.5),
                                  color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: rs.height(3)),
                              Row(
                                children: [
                                  Text(
                                    'TARGET: ${subject.targetAttendance}%',
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(10.5),
                                      color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  if (snapshot.manualOverride != null) ...[
                                    SizedBox(width: rs.width(8)),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(rs.scale(8)),
                                      onTap: widget.onShowManualBaselineTooltip,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: isDarkMode ? const Color(0xFF261D12) : const Color(0xFFFFF7EB),
                                          borderRadius: BorderRadius.circular(rs.scale(8)),
                                          border: Border.all(
                                            color: isDarkMode ? const Color(0xFF5A3E1B) : const Color(0xFFFFD499),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.tune_rounded,
                                              size: rs.scale(10),
                                              color: isDarkMode ? const Color(0xFFFF9F0A) : const Color(0xFFD97706),
                                            ),
                                            SizedBox(width: rs.width(3)),
                                            Text(
                                              'BASELINE',
                                              style: GoogleFonts.inter(
                                                fontSize: rs.font(9),
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.3,
                                                color: isDarkMode ? const Color(0xFFFF9F0A) : const Color(0xFFD97706),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (subjectProjection.hasActivePlannedLeave && plannedMissed > 0) ...[
                                    SizedBox(width: rs.width(8)),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(rs.scale(8)),
                                      onTap: widget.onShowProjectedLeaveTooltip,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: projectedBelowTarget
                                              ? (isDarkMode ? const Color(0xFF261214) : const Color(0xFFFFF0F1))
                                              : (isDarkMode ? const Color(0xFF1B1B20) : const Color(0xFFF2F2F7)),
                                          borderRadius: BorderRadius.circular(rs.scale(8)),
                                          border: Border.all(
                                            color: projectedBelowTarget
                                                ? (isDarkMode ? const Color(0xFF5A1E24) : const Color(0xFFFFCCD2))
                                                : (isDarkMode ? const Color(0xFF2E2E36) : const Color(0xFFD1D1D6)),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.event_available_outlined,
                                              size: rs.scale(10),
                                              color: projectedBelowTarget
                                                  ? (isDarkMode ? const Color(0xFFFF453A) : const Color(0xFFDC2626))
                                                  : (isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366)),
                                            ),
                                            SizedBox(width: rs.width(3)),
                                            Text(
                                              'LEAVE (${projectedRatio.toStringAsFixed(0)}%)',
                                              style: GoogleFonts.inter(
                                                fontSize: rs.font(9),
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.3,
                                                color: projectedBelowTarget
                                                    ? (isDarkMode ? const Color(0xFFFF453A) : const Color(0xFFDC2626))
                                                    : (isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        RotationTransition(
                          turns: _iconTurns,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: rs.scale(18),
                              color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(13)),
                    // Modern Progress Bar with Flat Single Color & Target Needle
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final clampedPct = (currentPct / 100.0).clamp(0.0, 1.0);
                        final targetPos = (targetPercent / 100.0).clamp(0.0, 1.0) * width;
                        final barHeight = rs.height(8.0);

                        return SizedBox(
                          height: barHeight,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.centerLeft,
                            children: [
                              // Base Track
                              Container(
                                width: width,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: isDarkMode ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(rs.scale(4)),
                                ),
                              ),
                              // Current Fill (Flat Single Color)
                              Container(
                                width: width * clampedPct,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                                  borderRadius: BorderRadius.circular(rs.scale(4)),
                                ),
                              ),
                              // Target Threshold Pin Indicator (Flat vertical needle, never overflows)
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
                    // Status Telemetry Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left: Intuitive dynamic status capsule
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: rs.width(9), vertical: rs.height(3.5)),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(rs.scale(8)),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAboveTarget ? Icons.check_circle_rounded : Icons.info_rounded,
                                size: rs.scale(12),
                                color: statusColor,
                              ),
                              SizedBox(width: rs.width(5)),
                              AnimatedCrossFade(
                                firstChild: Text(
                                  widget.compactStatus.toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(10.5),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                    color: statusColor,
                                  ),
                                ),
                                secondChild: Text(
                                  widget.message,
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(10.5),
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                                crossFadeState: widget.isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                                duration: const Duration(milliseconds: 200),
                              ),
                            ],
                          ),
                        ),
                        // Right: Current Percentage
                        Text(
                          '${currentPct.toStringAsFixed(1)}%',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(16),
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Expandable Telemetry Console
            ClipRect(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller.view,
                  builder: (context, child) {
                    return Align(
                      alignment: Alignment.topCenter,
                      heightFactor: _heightFactor.value,
                      child: child,
                    );
                  },
                  child: Padding(
                  padding: EdgeInsets.fromLTRB(rs.scale(15), 0, rs.scale(15), rs.scale(15)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(
                        height: 1,
                        thickness: 0.8,
                        color: isDarkMode ? const Color(0xFF222227) : const Color(0xFFE5E5EA),
                      ),
                      SizedBox(height: rs.height(12)),
                      // 4-column recessed telemetry cockpit
                      Container(
                        padding: rs.insetsSymmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: recessedBg,
                          borderRadius: BorderRadius.circular(rs.scale(18)),
                          border: Border.all(color: innerBorder, width: 0.8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatColumn(
                              rs: rs,
                              isDarkMode: isDarkMode,
                              label: 'Held',
                              value: widget.classesHeldSoFar.toString(),
                            ),
                            Container(
                              width: 0.8,
                              height: rs.height(28),
                              color: innerBorder,
                            ),
                            _buildStatColumn(
                              rs: rs,
                              isDarkMode: isDarkMode,
                              label: 'Attended',
                              value: widget.attendedClasses.toString(),
                              valueColor: isDarkMode ? const Color(0xFF34C759) : const Color(0xFF28A745),
                            ),
                            Container(
                              width: 0.8,
                              height: rs.height(28),
                              color: innerBorder,
                            ),
                            _buildStatColumn(
                              rs: rs,
                              isDarkMode: isDarkMode,
                              label: 'Bunked',
                              value: widget.absentClasses.toString(),
                              valueColor: isDarkMode ? const Color(0xFFFF453A) : const Color(0xFFDC2626),
                            ),
                            Container(
                              width: 0.8,
                              height: rs.height(28),
                              color: innerBorder,
                            ),
                            _buildStatColumn(
                              rs: rs,
                              isDarkMode: isDarkMode,
                              label: 'Ratio',
                              value: '${currentPct.toStringAsFixed(1)}%',
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: rs.height(10)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: widget.onUpdateCountsManually,
                          style: OutlinedButton.styleFrom(
                            padding: rs.insetsSymmetric(horizontal: 14, vertical: 8),
                            side: BorderSide(
                              color: isDarkMode ? const Color(0xFF2A2A32) : const Color(0xFFD1D1D6),
                              width: 0.8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(rs.scale(20)),
                            ),
                          ),
                          icon: Icon(
                            Icons.tune_rounded,
                            size: rs.scale(14),
                            color: isDarkMode ? Colors.white70 : Colors.black87,
                          ),
                          label: Text(
                            'Update Counts Manually',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(11.5),
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    ),
  );
}
}

class _SubjectAttendanceSnapshot {
  final int totalClassesInWindow;
  final int scheduledSoFarInWindow;
  final int classesHeldSoFar;
  final int attendedClasses;
  final int absentClasses;
  final int markedClasses;
  final DateTime countingStart;
  final ManualAttendanceOverride? manualOverride;

  const _SubjectAttendanceSnapshot({
    required this.totalClassesInWindow,
    required this.scheduledSoFarInWindow,
    required this.classesHeldSoFar,
    required this.attendedClasses,
    required this.absentClasses,
    required this.markedClasses,
    required this.countingStart,
    required this.manualOverride,
  });
}

class _ManualCountInput {
  final int held;
  final int attended;
  final bool isReset;

  const _ManualCountInput({
    required this.held,
    required this.attended,
    this.isReset = false,
  });
}

class _ManualCountUpdateSheet extends StatefulWidget {
  final String subjectName;
  final DateTime effectiveFrom;
  final int initialHeld;
  final int initialAttended;
  final bool hasManualOverride;

  const _ManualCountUpdateSheet({
    required this.subjectName,
    required this.effectiveFrom,
    required this.initialHeld,
    required this.initialAttended,
    this.hasManualOverride = false,
  });

  @override
  State<_ManualCountUpdateSheet> createState() => _ManualCountUpdateSheetState();
}

class _ManualCountUpdateSheetState extends State<_ManualCountUpdateSheet> {
  late final TextEditingController _heldController;
  late final TextEditingController _attendedController;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _heldController = TextEditingController(text: widget.initialHeld.toString());
    _attendedController = TextEditingController(text: widget.initialAttended.toString());
    _heldController.addListener(() => setState(() {}));
    _attendedController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _heldController.dispose();
    _attendedController.dispose();
    super.dispose();
  }

  void _save() {
    final held = int.tryParse(_heldController.text.trim());
    final attended = int.tryParse(_attendedController.text.trim());

    if (held == null || attended == null || held < 0 || attended < 0 || attended > held) {
      setState(() {
        _validationError = 'Enter valid counts. Attended must be between 0 and held.';
      });
      return;
    }

    Navigator.pop(context, _ManualCountInput(held: held, attended: attended));
  }

  void _resetBaseline() {
    Navigator.pop(context, const _ManualCountInput(held: 0, attended: 0, isReset: true));
  }

  void _incrementHeld() {
    HapticFeedback.selectionClick();
    final current = int.tryParse(_heldController.text.trim()) ?? 0;
    _heldController.text = (current + 1).toString();
    _clearError();
  }

  void _decrementHeld() {
    HapticFeedback.selectionClick();
    final current = int.tryParse(_heldController.text.trim()) ?? 0;
    if (current > 0) {
      _heldController.text = (current - 1).toString();
      _clearError();
    }
  }

  void _incrementAttended() {
    HapticFeedback.selectionClick();
    final current = int.tryParse(_attendedController.text.trim()) ?? 0;
    _attendedController.text = (current + 1).toString();
    _clearError();
  }

  void _decrementAttended() {
    HapticFeedback.selectionClick();
    final current = int.tryParse(_attendedController.text.trim()) ?? 0;
    if (current > 0) {
      _attendedController.text = (current - 1).toString();
      _clearError();
    }
  }

  void _clearError() {
    if (_validationError != null) {
      setState(() {
        _validationError = null;
      });
    }
  }

  Widget _buildGlassStepper({
    required BuildContext context,
    required ResponsiveScale rs,
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
    required bool isDark,
  }) {
    final cardBg = isDark ? const Color(0xFF18181C) : const Color(0xFFF6F6F9);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final btnBg = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.05);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: rs.width(10),
        vertical: rs.height(12),
      ),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(rs.scale(18)),
        border: Border.all(color: cardBorder, width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: rs.scale(13),
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
              ),
              SizedBox(width: rs.width(5)),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: rs.font(10),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(10)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Decrement
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onDecrement,
                  borderRadius: BorderRadius.circular(rs.scale(12)),
                  child: Container(
                    width: rs.scale(36),
                    height: rs.scale(36),
                    decoration: BoxDecoration(
                      color: btnBg,
                      borderRadius: BorderRadius.circular(rs.scale(12)),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      Icons.remove_rounded,
                      size: rs.scale(18),
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
              // Value display & direct edit
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: rs.font(23),
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => _clearError(),
                ),
              ),
              // Increment
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onIncrement,
                  borderRadius: BorderRadius.circular(rs.scale(12)),
                  child: Container(
                    width: rs.scale(36),
                    height: rs.scale(36),
                    decoration: BoxDecoration(
                      color: btnBg,
                      borderRadius: BorderRadius.circular(rs.scale(12)),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      size: rs.scale(18),
                      color: isDark ? Colors.white : Colors.black,
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

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark
        ? const Color(0xFF121218).withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.78);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.60);

    final held = int.tryParse(_heldController.text.trim()) ?? 0;
    final attended = int.tryParse(_attendedController.text.trim()) ?? 0;
    final double pct = held > 0 ? (attended / held * 100).clamp(0.0, 100.0) : 100.0;
    final bool isOnTrack = pct >= 75.0;

    final dateStr =
        '${widget.effectiveFrom.day}/${widget.effectiveFrom.month}/${widget.effectiveFrom.year}';

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(rs.scale(32))),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
        child: Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(rs.scale(32))),
            border: Border(
              top: BorderSide(color: borderColor, width: 0.9),
            ),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + rs.height(28),
            left: rs.width(20),
            right: rs.width(20),
            top: rs.height(14),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Minimal drag handle
                Center(
                  child: Container(
                    width: rs.scale(36),
                    height: rs.scale(4.5),
                    margin: EdgeInsets.only(bottom: rs.height(16)),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(rs.scale(2.5)),
                    ),
                  ),
                ),

                // Header Row with Icon Badge, Title, and Close Button
                Row(
                  children: [
                    Container(
                      width: rs.scale(42),
                      height: rs.scale(42),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(rs.scale(14)),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        size: rs.scale(21),
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    SizedBox(width: rs.width(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'UPDATE BASELINE',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(10),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                            ),
                          ),
                          SizedBox(height: rs.height(2)),
                          Text(
                            widget.subjectName,
                            style: GoogleFonts.inter(
                              fontSize: rs.font(16.5),
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(rs.scale(18)),
                        child: Container(
                          width: rs.scale(36),
                          height: rs.scale(36),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: rs.scale(18),
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: rs.height(16)),

                // Redesigned Glass Notice Box
                Container(
                  padding: EdgeInsets.all(rs.scale(14)),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(rs.scale(16)),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(rs.scale(6)),
                        decoration: BoxDecoration(
                          color: (isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706))
                              .withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.history_toggle_off_rounded,
                          color: isDark ? const Color(0xFFF59E0B) : const Color(0xFFB45309),
                          size: rs.scale(16),
                        ),
                      ),
                      SizedBox(width: rs.width(12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Manual Baseline Active',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(12),
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            SizedBox(height: rs.height(3)),
                            Text(
                              'Updating counts sets a new starting point as of $dateStr. Attendance records logged prior to this date will be bypassed in Bunk Meter analytics.',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(11.5),
                                color: isDark
                                    ? const Color(0xFF8E8E93)
                                    : const Color(0xFF6C6C70),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: rs.height(16)),

                // Two Tactile Counter Stepper Tiles
                Row(
                  children: [
                    Expanded(
                      child: _buildGlassStepper(
                        context: context,
                        rs: rs,
                        label: 'Classes Held',
                        icon: Icons.event_seat_outlined,
                        controller: _heldController,
                        onDecrement: _decrementHeld,
                        onIncrement: _incrementHeld,
                        isDark: isDark,
                      ),
                    ),
                    SizedBox(width: rs.width(12)),
                    Expanded(
                      child: _buildGlassStepper(
                        context: context,
                        rs: rs,
                        label: 'Classes Attended',
                        icon: Icons.check_circle_outline_rounded,
                        controller: _attendedController,
                        onDecrement: _decrementAttended,
                        onIncrement: _incrementAttended,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: rs.height(12)),

                // Live Baseline Preview Pill
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: rs.width(14),
                    vertical: rs.height(10),
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(rs.scale(14)),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.speed_rounded,
                            size: rs.scale(16),
                            color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                          ),
                          SizedBox(width: rs.width(8)),
                          Text(
                            'Resulting Baseline:',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(12),
                              fontWeight: FontWeight.w500,
                              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                            ),
                          ),
                          SizedBox(width: rs.width(6)),
                          Text(
                            '${pct.toStringAsFixed(1)}%',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(13),
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : Colors.black,
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
                          color: isOnTrack
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark
                                  ? const Color(0xFF2C1517)
                                  : const Color(0xFFFDEDED)),
                          borderRadius: BorderRadius.circular(rs.scale(100)),
                          border: Border.all(
                            color: isOnTrack
                                ? (isDark ? Colors.white : Colors.black)
                                : (isDark
                                    ? const Color(0xFFEF5350).withValues(alpha: 0.4)
                                    : const Color(0xFFEF5350).withValues(alpha: 0.3)),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isOnTrack ? 'ON TRACK' : 'BELOW 75%',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(9.5),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: isOnTrack
                                ? (isDark ? Colors.black : Colors.white)
                                : (isDark
                                    ? const Color(0xFFFF8A80)
                                    : const Color(0xFFD32F2F)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_validationError != null) ...[
                  SizedBox(height: rs.height(10)),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: rs.width(12),
                      vertical: rs.height(8),
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A1517) : const Color(0xFFFDEDED),
                      borderRadius: BorderRadius.circular(rs.scale(12)),
                      border: Border.all(
                        color: const Color(0xFFEF5350).withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFEF5350),
                          size: 16,
                        ),
                        SizedBox(width: rs.width(8)),
                        Expanded(
                          child: Text(
                            _validationError!,
                            style: GoogleFonts.inter(
                              color: isDark ? const Color(0xFFFF8A80) : const Color(0xFFD32F2F),
                              fontSize: rs.font(11.5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (widget.hasManualOverride) ...[
                  SizedBox(height: rs.height(12)),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _resetBaseline,
                      icon: const Icon(Icons.restart_alt_rounded, size: 17),
                      label: Text(
                        'Reset to System Recorded Attendance',
                        style: GoogleFonts.inter(
                          fontSize: rs.font(12.5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? const Color(0xFFFF8A80) : const Color(0xFFD32F2F),
                        side: BorderSide(
                          color: (isDark ? const Color(0xFFFF8A80) : const Color(0xFFD32F2F))
                              .withValues(alpha: 0.25),
                          width: 0.9,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(rs.scale(16)),
                        ),
                        padding: EdgeInsets.symmetric(vertical: rs.height(12)),
                      ),
                    ),
                  ),
                ],

                SizedBox(height: rs.height(18)),

                // Action Buttons (Cancel & Save)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: rs.height(14)),
                          side: BorderSide(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.10),
                            width: 0.9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(rs.scale(22)),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(13.5),
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: rs.width(12)),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          'Save Changes',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(13.5),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: isDark ? Colors.white : Colors.black,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          padding: EdgeInsets.symmetric(vertical: rs.height(14)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(rs.scale(22)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
