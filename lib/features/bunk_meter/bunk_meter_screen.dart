import 'package:flutter/material.dart';
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
        // Search field
        Padding(
          padding: rs.insetsSymmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search for a class...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(rs.scale(12)),
              ),
              contentPadding: rs.insetsSymmetric(vertical: 12),
            ),
          ),
        ),
        // Action toolbar: What-If Calculator & Trip Planner
        Padding(
          padding: rs.insetsSymmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: KeyedSubtree(
                  key: _bunkCalculatorKey,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: rs.insetsSymmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(rs.scale(10)),
                      ),
                    ),
                    icon: Icon(Icons.calculate_outlined, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87, size: 18),
                    label: Text('Bunk Calculator', style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
                    onPressed: () {
                      if (tutorialController.isActive && tutorialController.currentStepIndex == 20) {
                        tutorialController.nextStep();
                      }
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        barrierColor: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.12)
                            : null,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                        ),
                        sheetAnimationStyle: AnimationStyle(
                          duration: const Duration(milliseconds: 300),
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
                  ),
                ),
              ),
              SizedBox(width: rs.width(8)),
              Expanded(
                child: KeyedSubtree(
                  key: _leavePlannerKey,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: rs.insetsSymmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(rs.scale(10)),
                      ),
                    ),
                    icon: Icon(Icons.event_available_outlined, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87, size: 18),
                    label: Text('Leave Planner', style: TextStyle(fontSize: 12, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
                    onPressed: () async {
                      if (tutorialController.isActive && tutorialController.currentStepIndex == 22) {
                        tutorialController.nextStep();
                      }
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const LeavePlannerScreen()),
                      );
                      _loadPlannedLeaves();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // Show count of filtered results
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: rs.insetsSymmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Found ${filteredSubjects.length} class${filteredSubjects.length == 1 ? '' : 'es'}',
              style: TextStyle(
                fontSize: rs.font(12),
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Expanded(
          child: filteredSubjects.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: rs.scale(64), color: Colors.grey.shade400),
                      SizedBox(height: rs.height(16)),
                      Text(
                        'No classes found',
                        style: TextStyle(fontSize: rs.font(18), color: Colors.grey.shade600),
                      ),
                      SizedBox(height: rs.height(8)),
                      Text(
                        'Try a different search term',
                        style: TextStyle(fontSize: rs.font(14), color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  key: ValueKey(Theme.of(context).brightness),
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
            borderRadius: BorderRadius.circular(rs.scale(16)),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: rs.scale(24)),
              SizedBox(width: rs.width(8)),
              Expanded(
                child: Text(
                  'Manual Baseline',
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
                'Manual baseline active from ${countingStart.day}/${countingStart.month}/${countingStart.year}. Any attendance or timetable changes before this date are ignored in this card.',
                style: TextStyle(
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
            borderRadius: BorderRadius.circular(rs.scale(16)),
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
                  borderRadius: BorderRadius.circular(rs.scale(8)),
                  border: Border.all(
                    color: projectedBelowTarget
                        ? Colors.red.shade300
                        : (isDarkMode ? Colors.white24 : Colors.grey.shade300),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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

  Widget _buildStatColumn(String title, String value) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final subject = widget.subject;
    final snapshot = widget.snapshot;
    final subjectProjection = widget.subjectProjection;
    final int plannedMissed = subjectProjection.plannedMissedCount;
    final double projectedRatio = subjectProjection.projectedPercentage;
    final bool projectedBelowTarget = projectedRatio < subject.targetAttendance;

    return Card(
      elevation: 3.0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.4)
              : Colors.black.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      shadowColor: isDarkMode
          ? Colors.white.withValues(alpha: 0.3)
          : Colors.black.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8.0),
            onTap: _handleTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20.6,
                        backgroundColor: subject.color,
                        child: Center(
                          child: Text(
                            subject.acronym ?? subject.name.acronymFromName(),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            softWrap: true,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subject.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                Text(
                                  'Target: ${subject.targetAttendance}%',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (snapshot.manualOverride != null) ...[
                                  const SizedBox(width: 6),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: widget.onShowManualBaselineTooltip,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                                      ),
                                      child: Tooltip(
                                        message: 'Manual Baseline active',
                                        child: Icon(
                                          Icons.tune_rounded,
                                          size: 13,
                                          color: Colors.orange.shade800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (subjectProjection.hasActivePlannedLeave && plannedMissed > 0) ...[
                                  const SizedBox(width: 6),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(6),
                                    onTap: widget.onShowProjectedLeaveTooltip,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: projectedBelowTarget
                                            ? Colors.red.withValues(alpha: 0.15)
                                            : (isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06)),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: projectedBelowTarget
                                              ? Colors.red.withValues(alpha: 0.4)
                                              : (isDarkMode ? Colors.white24 : Colors.black26),
                                        ),
                                      ),
                                      child: Tooltip(
                                        message: 'Projected after leave: ${projectedRatio.toStringAsFixed(1)}%',
                                        child: Icon(
                                          Icons.event_available_outlined,
                                          size: 13,
                                          color: projectedBelowTarget
                                              ? Colors.red.shade700
                                              : (isDarkMode ? Colors.white70 : Colors.black87),
                                        ),
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
                        child: Icon(
                          Icons.expand_more,
                          color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  AnimatedCrossFade(
                    firstChild: Text(
                      widget.compactStatus,
                      style: TextStyle(fontSize: 14, color: widget.messageColor, fontWeight: FontWeight.w600),
                    ),
                    secondChild: Text(
                      widget.message,
                      style: TextStyle(fontSize: 14, color: widget.messageColor, fontWeight: FontWeight.w600),
                    ),
                    crossFadeState: widget.isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
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
                padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStatColumn('Classes Held', widget.classesHeldSoFar.toString()),
                        _buildStatColumn('Attended', widget.attendedClasses.toString()),
                        _buildStatColumn('Bunked', widget.absentClasses.toString()),
                        _buildStatColumn('Current %', '${widget.currentPercentage.toStringAsFixed(1)}%'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: widget.onUpdateCountsManually,
                        icon: const Icon(Icons.edit_calendar_outlined),
                        label: const Text('Update Counts Manually'),
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
    final current = int.tryParse(_heldController.text.trim()) ?? 0;
    _heldController.text = (current + 1).toString();
    _clearError();
  }

  void _decrementHeld() {
    final current = int.tryParse(_heldController.text.trim()) ?? 0;
    if (current > 0) {
      _heldController.text = (current - 1).toString();
      _clearError();
    }
  }

  void _incrementAttended() {
    final current = int.tryParse(_attendedController.text.trim()) ?? 0;
    _attendedController.text = (current + 1).toString();
    _clearError();
  }

  void _decrementAttended() {
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

  Widget _buildCountStepper({
    required BuildContext context,
    required ResponsiveScale rs,
    required String label,
    required TextEditingController controller,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: rs.font(12.5),
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: rs.height(6)),
        Container(
          height: rs.height(48),
          decoration: BoxDecoration(
            color: isDarkMode
                ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
                : theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(rs.scale(14)),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onDecrement,
                icon: Icon(Icons.remove_rounded, size: rs.scale(18)),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: rs.width(36),
                  minHeight: rs.height(48),
                ),
                color: theme.colorScheme.onSurface,
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: rs.font(16),
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => _clearError(),
                ),
              ),
              IconButton(
                onPressed: onIncrement,
                icon: Icon(Icons.add_rounded, size: rs.scale(18)),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: rs.width(36),
                  minHeight: rs.height(48),
                ),
                color: theme.colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + rs.height(16),
        left: rs.width(20),
        right: rs.width(20),
        top: rs.height(12),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: rs.width(36),
                height: rs.height(4),
                margin: EdgeInsets.only(bottom: rs.height(12)),
                decoration: BoxDecoration(
                  color: theme.dividerColor.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(rs.scale(2)),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Update ${widget.subjectName} Counts',
                    style: TextStyle(
                      fontSize: rs.font(16.5),
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            SizedBox(height: rs.height(8)),
            Container(
              padding: EdgeInsets.all(rs.scale(12)),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(rs.scale(12)),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade800,
                    size: rs.scale(20),
                  ),
                  SizedBox(width: rs.width(10)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Manual Override Notice',
                          style: TextStyle(
                            fontSize: rs.font(12.5),
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                        SizedBox(height: rs.height(2)),
                        Text(
                          'Updating counts manually ignores attendance history before ${widget.effectiveFrom.day}/${widget.effectiveFrom.month}/${widget.effectiveFrom.year} for this subject in Bunk Meter.',
                          style: TextStyle(
                            fontSize: rs.font(11.5),
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: rs.height(16)),
            Row(
              children: [
                Expanded(
                  child: _buildCountStepper(
                    context: context,
                    rs: rs,
                    label: 'Classes Held',
                    controller: _heldController,
                    onDecrement: _decrementHeld,
                    onIncrement: _incrementHeld,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                SizedBox(width: rs.width(12)),
                Expanded(
                  child: _buildCountStepper(
                    context: context,
                    rs: rs,
                    label: 'Classes Attended',
                    controller: _attendedController,
                    onDecrement: _decrementAttended,
                    onIncrement: _incrementAttended,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (_validationError != null) ...[
              SizedBox(height: rs.height(10)),
              Text(
                _validationError!,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: rs.font(12),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (widget.hasManualOverride) ...[
              SizedBox(height: rs.height(10)),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _resetBaseline,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Reset Manual Baseline'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    padding: EdgeInsets.symmetric(vertical: rs.height(10)),
                  ),
                ),
              ),
            ],
            SizedBox(height: rs.height(12)),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: rs.height(12)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(rs.scale(12)),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(fontSize: rs.font(13.5)),
                    ),
                  ),
                ),
                SizedBox(width: rs.width(12)),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: rs.height(12)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(rs.scale(12)),
                      ),
                    ),
                    child: Text(
                      'Save',
                      style: TextStyle(
                        fontSize: rs.font(13.5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
