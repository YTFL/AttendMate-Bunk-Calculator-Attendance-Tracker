import 'package:flutter/material.dart';
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

    final startDay = today.isBefore(countingStartDay) ? countingStartDay : today;

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

    // Calculate current totals based on selection, respecting manual attendance overrides
    int currentAttended = 0;
    int currentHeld = 0;
    int leaveMissedTotal = 0;
    int totalRemaining = 0;

    final targetHorizon = _selectedTargetDate ?? widget.semester.endDate;
    Subject? selectedSubject;

    if (_selectedSubjectId == 'all') {
      for (final subject in widget.subjects) {
        final manualOverride = subject.manualAttendanceOverride;
        DateTime countingStart = manualOverride?.effectiveFrom ?? widget.semester.startDate;
        if (countingStart.isBefore(widget.semester.startDate)) {
          countingStart = widget.semester.startDate;
        }
        final countingStartDay = DateTime(countingStart.year, countingStart.month, countingStart.day);

        currentAttended += manualOverride?.classesAttended ?? 0;
        currentHeld += manualOverride?.classesHeld ?? 0;

        final records = widget.recordsBySubject[subject.id] ?? const [];
        for (final r in records) {
          final rDay = DateTime(r.date.year, r.date.month, r.date.day);
          if (rDay.isBefore(countingStartDay)) continue;

          if (r.status == AttendanceStatus.attended) {
            currentAttended++;
            currentHeld++;
          } else if (r.status == AttendanceStatus.absent) {
            currentHeld++;
          }
        }
        final res = _countClassesUpToDate(subject, targetHorizon, _considerPlannedLeave);
        totalRemaining += res.remainingClasses;
        leaveMissedTotal += res.leaveMissedClasses;
      }
    } else {
      selectedSubject = widget.subjects.firstWhere(
        (s) => s.id == _selectedSubjectId,
        orElse: () => widget.subjects.first,
      );
      final manualOverride = selectedSubject.manualAttendanceOverride;
      DateTime countingStart = manualOverride?.effectiveFrom ?? widget.semester.startDate;
      if (countingStart.isBefore(widget.semester.startDate)) {
        countingStart = widget.semester.startDate;
      }
      final countingStartDay = DateTime(countingStart.year, countingStart.month, countingStart.day);

      currentAttended += manualOverride?.classesAttended ?? 0;
      currentHeld += manualOverride?.classesHeld ?? 0;

      final records = widget.recordsBySubject[selectedSubject.id] ?? const [];
      for (final r in records) {
        final rDay = DateTime(r.date.year, r.date.month, r.date.day);
        if (rDay.isBefore(countingStartDay)) continue;

        if (r.status == AttendanceStatus.attended) {
          currentAttended++;
          currentHeld++;
        } else if (r.status == AttendanceStatus.absent) {
          currentHeld++;
        }
      }
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
        child: Container(
          padding: rs.insetsAll(20),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(rs.scale(24))),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: rs.width(40),
                    height: rs.height(4),
                    margin: EdgeInsets.only(bottom: rs.height(16)),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(rs.scale(2)),
                    ),
                  ),
                ),

                // Header title row with Reset & Close icon buttons
                Row(
                  children: [
                    Icon(
                      Icons.calculate_outlined,
                      color: isDarkMode ? Colors.white : Colors.black87,
                      size: rs.scale(24),
                    ),
                    SizedBox(width: rs.width(10)),
                    Text(
                      'Bunk Calculator',
                      style: TextStyle(
                        fontSize: rs.font(18),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_attendNext > 0 || _bunkNext > 0)
                      IconButton(
                        tooltip: 'Reset Simulation',
                        icon: Icon(
                          Icons.refresh,
                          size: rs.scale(20),
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
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: rs.scale(20),
                        color: isDarkMode ? Colors.white70 : Colors.black87,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                SizedBox(height: rs.height(16)),

                // Subject Selector + Small Max Button Row
                Text(
                  'Select Target Subject',
                  style: TextStyle(
                    fontSize: rs.font(13),
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white60 : Colors.black54,
                  ),
                ),
                SizedBox(height: rs.height(6)),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: rs.insetsSymmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDarkMode ? Colors.white24 : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(rs.scale(10)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedSubjectId,
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem(
                                value: 'all',
                                child: Text('Semester Average'),
                              ),
                              ...widget.subjects.map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: rs.scale(6),
                                        backgroundColor: s.color,
                                      ),
                                      SizedBox(width: rs.width(8)),
                                      Expanded(
                                        child: Text(
                                          s.acronym ?? s.name,
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
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: rs.insetsSymmetric(horizontal: 12, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(rs.scale(10)),
                        ),
                      ),
                      icon: const Icon(Icons.bolt, size: 16),
                      label: const Text('Max', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _applyMaxTargetSimulation(mustAttend, canBunk),
                    ),
                  ],
                ),

                SizedBox(height: rs.height(12)),

                // Target Date Horizon & Consider Planned Leave Controls
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedTargetDate ?? widget.semester.endDate,
                            firstDate: today,
                            lastDate: widget.semester.endDate,
                            helpText: 'Select Horizon End Date',
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
                        borderRadius: BorderRadius.circular(rs.scale(10)),
                        child: Container(
                          padding: rs.insetsSymmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isDarkMode ? Colors.white24 : Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(rs.scale(10)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today_rounded,
                                size: rs.scale(16),
                                color: theme.colorScheme.primary,
                              ),
                              SizedBox(width: rs.width(8)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Calculate Until',
                                      style: TextStyle(
                                        fontSize: rs.font(10),
                                        color: isDarkMode ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                    Text(
                                      _selectedTargetDate == null ||
                                              _isSameDay(_selectedTargetDate!, widget.semester.endDate)
                                          ? 'End of Semester'
                                          : DateFormat.yMMMd().format(_selectedTargetDate!),
                                      style: TextStyle(
                                        fontSize: rs.font(12),
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
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
                                    Icons.clear_rounded,
                                    size: rs.scale(16),
                                    color: isDarkMode ? Colors.white60 : Colors.black54,
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

                // Consider Planned Leave Checkbox
                InkWell(
                  onTap: () {
                    setState(() {
                      _considerPlannedLeave = !_considerPlannedLeave;
                    });
                  },
                  borderRadius: BorderRadius.circular(rs.scale(10)),
                  child: Padding(
                    padding: rs.insetsSymmetric(vertical: 2, horizontal: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: rs.scale(22),
                          height: rs.scale(22),
                          child: Checkbox(
                            value: _considerPlannedLeave,
                            onChanged: (val) {
                              setState(() {
                                _considerPlannedLeave = val ?? false;
                              });
                            },
                          ),
                        ),
                        SizedBox(width: rs.width(8)),
                        Expanded(
                          child: Text(
                            'Consider Planned Leaves',
                            style: TextStyle(
                              fontSize: rs.font(13),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: rs.height(14)),

                // Target Horizon Breakdown Card
                Container(
                  padding: rs.insetsAll(12),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(rs.scale(12)),
                    border: Border.all(
                      color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedTargetDate == null || _isSameDay(_selectedTargetDate!, widget.semester.endDate)
                            ? 'Semester Remaining: $totalRemaining classes'
                            : 'Remaining (Up to ${DateFormat.yMMMd().format(_selectedTargetDate!)}): $totalRemaining classes',
                        style: TextStyle(
                          fontSize: rs.font(12),
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      if (_considerPlannedLeave && leaveMissedTotal > 0) ...[
                        SizedBox(height: rs.height(2)),
                        Text(
                          'Includes $leaveMissedTotal planned leave class${leaveMissedTotal == 1 ? '' : 'es'} (counted as missed)',
                          style: TextStyle(
                            fontSize: rs.font(11),
                            color: isDarkMode ? Colors.amber.shade300 : Colors.amber.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      SizedBox(height: rs.height(4)),
                      Row(
                        children: [
                          Text(
                            'Must Attend: $mustAttend',
                            style: TextStyle(
                              fontSize: rs.font(12),
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                          SizedBox(width: rs.width(16)),
                          Text(
                            'Can Bunk: $canBunk',
                            style: TextStyle(
                              fontSize: rs.font(12),
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: rs.height(16)),

                // Steppers Section
                Row(
                  children: [
                    Expanded(
                      child: _buildStepperCard(
                        context: context,
                        rs: rs,
                        title: 'Attend Next',
                        value: _attendNext,
                        color: Colors.green,
                        icon: Icons.check_circle_outline,
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
                    SizedBox(width: rs.width(12)),
                    Expanded(
                      child: _buildStepperCard(
                        context: context,
                        rs: rs,
                        title: 'Bunk Next',
                        value: _bunkNext,
                        color: Colors.red.shade700,
                        icon: Icons.cancel_outlined,
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

                SizedBox(height: rs.height(16)),

                // Simulation Result Summary Card
                Container(
                  padding: rs.insetsAll(16),
                  decoration: BoxDecoration(
                    color: isAboveTarget
                        ? Colors.green.withValues(alpha: isDarkMode ? 0.15 : 0.08)
                        : Colors.red.withValues(alpha: isDarkMode ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(rs.scale(16)),
                    border: Border.all(
                      color: isAboveTarget
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Simulated Attendance',
                                style: TextStyle(
                                  fontSize: rs.font(12),
                                  color: isDarkMode ? Colors.white60 : Colors.black54,
                                ),
                              ),
                              SizedBox(height: rs.height(4)),
                              Row(
                                children: [
                                  Text(
                                    '${simulatedRatio.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      fontSize: rs.font(24),
                                      fontWeight: FontWeight.bold,
                                      color: isAboveTarget ? Colors.green.shade700 : Colors.red.shade700,
                                    ),
                                  ),
                                  SizedBox(width: rs.width(8)),
                                  Text(
                                    '(${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%)',
                                    style: TextStyle(
                                      fontSize: rs.font(14),
                                      fontWeight: FontWeight.bold,
                                      color: delta >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                            padding: rs.insetsSymmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isAboveTarget ? Colors.green.shade700 : Colors.red.shade700,
                              borderRadius: BorderRadius.circular(rs.scale(8)),
                            ),
                            child: Text(
                              isAboveTarget ? 'Target Met' : 'Below Target',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: rs.font(12),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: rs.height(10)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Simulated: $simulatedAttended / $simulatedHeld classes',
                            style: TextStyle(
                              fontSize: rs.font(12),
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          Text(
                            'Target: ${targetPercentage.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: rs.font(12),
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
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
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      padding: rs.insetsAll(12),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(rs.scale(12)),
        border: Border.all(
          color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: rs.scale(16), color: color),
              SizedBox(width: rs.width(6)),
              Text(
                title,
                style: TextStyle(
                  fontSize: rs.font(12),
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(8)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: onDecrement,
                icon: const Icon(Icons.remove_circle_outline),
                color: color,
                disabledColor: isDarkMode ? Colors.white24 : Colors.black12,
              ),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: rs.font(20),
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              IconButton(
                onPressed: onIncrement,
                icon: const Icon(Icons.add_circle_outline),
                color: color,
                disabledColor: isDarkMode ? Colors.white24 : Colors.black12,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
