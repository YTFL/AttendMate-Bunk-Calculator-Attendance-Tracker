import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/responsive_scale.dart';
import '../attendance/attendance_model.dart';
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

class _WhatIfCalculatorSheetState extends State<WhatIfCalculatorSheet> {
  late String _selectedSubjectId; // 'all' or subject.id
  int _attendNext = 0;
  int _bunkNext = 0;

  final GlobalKey _bunkCalculatorCardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectedSubjectId = widget.initialSubjectId ?? 'all';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final tutorialController = Provider.of<TutorialController>(context, listen: false);
        tutorialController.addListener(_onTutorialStepChanged);
      }
    });
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

  int _countRemainingClasses(Subject subject) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDate = widget.semester.endDate;
    if (today.isAfter(endDate)) return 0;

    int count = 0;
    DateTime cur = today;
    while (!cur.isAfter(endDate)) {
      for (final slot in subject.schedule) {
        if (slot.occursOnDate(cur)) {
          count++;
        }
      }
      cur = cur.add(const Duration(days: 1));
    }
    return count;
  }

  void _applyMaxTargetSimulation(int mustAttend, int canBunk) {
    setState(() {
      _attendNext = mustAttend;
      _bunkNext = canBunk;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    // Calculate current totals based on selection
    int currentAttended = 0;
    int currentHeld = 0;

    if (_selectedSubjectId == 'all') {
      for (final subject in widget.subjects) {
        final records = widget.recordsBySubject[subject.id] ?? const [];
        for (final r in records) {
          if (r.status == AttendanceStatus.attended) {
            currentAttended++;
            currentHeld++;
          } else if (r.status == AttendanceStatus.absent) {
            currentHeld++;
          }
        }
      }
    } else {
      final records = widget.recordsBySubject[_selectedSubjectId] ?? const [];
      for (final r in records) {
        if (r.status == AttendanceStatus.attended) {
          currentAttended++;
          currentHeld++;
        } else if (r.status == AttendanceStatus.absent) {
          currentHeld++;
        }
      }
    }

    // Calculate remaining classes in semester for selection
    int totalRemaining = 0;
    Subject? selectedSubject;
    if (_selectedSubjectId == 'all') {
      for (final s in widget.subjects) {
        totalRemaining += _countRemainingClasses(s);
      }
    } else {
      selectedSubject = widget.subjects.firstWhere((s) => s.id == _selectedSubjectId, orElse: () => widget.subjects.first);
      totalRemaining = _countRemainingClasses(selectedSubject);
    }

    final double targetPercentage = selectedSubject != null
        ? selectedSubject.targetAttendance.toDouble()
        : widget.semester.targetPercentage;
    final double targetRatio = targetPercentage / 100.0;

    // Target breakdown calculations for remaining semester
    final int endSemesterTotalHeld = currentHeld + totalRemaining;
    final int targetAttendedNeeded = (targetRatio * endSemesterTotalHeld).ceil();
    final int mustAttend = (targetAttendedNeeded - currentAttended).clamp(0, totalRemaining);
    final int canBunk = (totalRemaining - mustAttend).clamp(0, totalRemaining);

    // Simulated totals
    final int simulatedAttended = currentAttended + _attendNext;
    final int simulatedHeld = currentHeld + _attendNext + _bunkNext;

    final double currentRatio = currentHeld > 0 ? (currentAttended / currentHeld) * 100 : 100.0;
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
            SizedBox(height: rs.height(16)),

            // Remaining Semester Target Breakdown Card
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
                    'Semester Remaining: $totalRemaining classes',
                    style: TextStyle(
                      fontSize: rs.font(12),
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                  ),
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
                    onIncrement: () => setState(() => _attendNext++),
                    onDecrement: () => setState(() {
                      if (_attendNext > 0) _attendNext--;
                    }),
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
                    onIncrement: () => setState(() => _bunkNext++),
                    onDecrement: () => setState(() {
                      if (_bunkNext > 0) _bunkNext--;
                    }),
                  ),
                ),
              ],
            ),

            SizedBox(height: rs.height(16)),

            // Simulation Result Summary Card
            Container(
              padding: rs.insetsAll(16),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(rs.scale(16)),
                border: Border.all(
                  color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Simulated Result',
                        style: TextStyle(
                          fontSize: rs.font(14),
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      Container(
                        padding: rs.insetsSymmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(rs.scale(12)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAboveTarget ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                              color: isAboveTarget ? Colors.green : Colors.red,
                              size: rs.scale(12),
                            ),
                            SizedBox(width: rs.width(4)),
                            Text(
                              isAboveTarget ? 'Above Target (${targetPercentage.toStringAsFixed(0)}%)' : 'Below Target',
                              style: TextStyle(
                                color: isAboveTarget ? Colors.green : Colors.red,
                                fontSize: rs.font(11),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: rs.height(12)),
                  Row(
                    children: [
                      Text(
                        '${currentRatio.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: rs.font(20),
                          color: isDarkMode ? Colors.white38 : Colors.black38,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      SizedBox(width: rs.width(8)),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: rs.scale(18),
                        color: isAboveTarget ? Colors.green : Colors.red,
                      ),
                      SizedBox(width: rs.width(8)),
                      Text(
                        '${simulatedRatio.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: rs.font(26),
                          fontWeight: FontWeight.w800,
                          color: isAboveTarget ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${delta >= 0 ? "+" : ""}${delta.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: rs.font(14),
                          fontWeight: FontWeight.bold,
                          color: delta >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: rs.height(8)),
                  Text(
                    'Classes: $simulatedAttended attended out of $simulatedHeld total held',
                    style: TextStyle(
                      fontSize: rs.font(12),
                      color: isDarkMode ? Colors.white60 : Colors.black54,
                    ),
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
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
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
              SizedBox(width: rs.width(4)),
              Text(
                title,
                style: TextStyle(
                  fontSize: rs.font(12),
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(8)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: value > 0 ? onDecrement : null,
                icon: const Icon(Icons.remove_circle_outline),
                iconSize: rs.scale(24),
                color: color,
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
                iconSize: rs.scale(24),
                color: color,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
