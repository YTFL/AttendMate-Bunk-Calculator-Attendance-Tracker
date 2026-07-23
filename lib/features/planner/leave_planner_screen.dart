import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/database_service.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_time_picker.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_overlay.dart';
import 'planned_leave_model.dart';

class LeavePlannerScreen extends StatefulWidget {
  const LeavePlannerScreen({super.key});

  @override
  State<LeavePlannerScreen> createState() => _LeavePlannerScreenState();
}

class _LeavePlannerScreenState extends State<LeavePlannerScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<PlannedLeave> _leaves = [];
  bool _isLoading = true;

  final GlobalKey _leavePlannerAddKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadLeaves();

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
    if (tutorialController.isActive && (tutorialController.currentStepIndex < 23 || tutorialController.currentStepIndex >= 24)) {
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

  Future<void> _loadLeaves() async {
    setState(() => _isLoading = true);
    final leaves = await _databaseService.loadPlannedLeaves();
    if (mounted) {
      setState(() {
        _leaves = leaves;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    tutorialController.registerKey('key_leave_planner_add', _leavePlannerAddKey);

    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final subjects = subjectProvider.subjects;

    return TutorialOverlay(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Leave Planner'),
        ),
        floatingActionButton: KeyedSubtree(
          key: _leavePlannerAddKey,
          child: FloatingActionButton.extended(
            backgroundColor: isDarkMode ? Colors.white : Colors.black,
            foregroundColor: isDarkMode ? Colors.black : Colors.white,
            onPressed: subjects.isEmpty ? null : () => _showAddLeaveDialog(context, subjects),
            icon: const Icon(Icons.add),
            label: const Text('Add Leave'),
          ),
        ),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _leaves.isEmpty
              ? _buildEmptyState(rs, theme, isDarkMode)
              : ListView.builder(
                  padding: rs.insetsAll(16),
                  itemCount: _leaves.length,
                  itemBuilder: (context, index) {
                    final leave = _leaves[index];
                    return _buildLeaveCard(context, rs, theme, isDarkMode, leave, subjects);
                  },
                ),
      ),
    );
  }

  Widget _buildEmptyState(ResponsiveScale rs, ThemeData theme, bool isDarkMode) {
    return Center(
      child: Padding(
        padding: rs.insetsAll(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_note_outlined,
              size: rs.scale(64),
              color: isDarkMode ? Colors.white38 : Colors.black38,
            ),
            SizedBox(height: rs.height(16)),
            Text(
              'No Leaves Planned',
              style: TextStyle(
                fontSize: rs.font(18),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: rs.height(8)),
            Text(
              'Plan future absences or medical leaves to forecast their impact on your attendance buffer before taking time off.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: rs.font(14),
                color: isDarkMode ? Colors.white60 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveCard(
    BuildContext context,
    ResponsiveScale rs,
    ThemeData theme,
    bool isDarkMode,
    PlannedLeave leave,
    List<Subject> subjects,
  ) {
    final startDate = DateTime(leave.startDate.year, leave.startDate.month, leave.startDate.day);
    final endDate = DateTime(leave.endDate.year, leave.endDate.month, leave.endDate.day);

    // Calculate exact missed class counts per subject taking start/end times into account
    final Map<String, int> missedCountsPerSubject = {};
    int totalClassesMissed = 0;

    DateTime cur = startDate;
    while (!cur.isAfter(endDate)) {
      for (final s in subjects) {
        if (leave.affectedSubjectIds.isNotEmpty && !leave.affectedSubjectIds.contains(s.id)) continue;
        for (final slot in s.schedule) {
          if (slot.occursOnDate(cur)) {
            final slotStart = DateTime(cur.year, cur.month, cur.day, slot.startTime.hour, slot.startTime.minute);
            final slotEnd = DateTime(cur.year, cur.month, cur.day, slot.endTime.hour, slot.endTime.minute);
            if (slotStart.isBefore(leave.endDate) && slotEnd.isAfter(leave.startDate)) {
              final name = s.acronym ?? s.name;
              missedCountsPerSubject[name] = (missedCountsPerSubject[name] ?? 0) + 1;
              totalClassesMissed++;
            }
          }
        }
      }
      cur = cur.add(const Duration(days: 1));
    }

    final String missedBreakdownText = totalClassesMissed > 0
        ? missedCountsPerSubject.entries.map((e) => '${e.key} (${e.value})').join(', ')
        : 'No classes scheduled on these dates/times';

    final isStartFullDay = leave.startDate.hour == 0 && leave.startDate.minute == 0;
    final isEndFullDay = leave.endDate.hour == 23 && leave.endDate.minute == 59;
    final startTimeStr = TimeOfDay.fromDateTime(leave.startDate).format(context);
    final endTimeStr = TimeOfDay.fromDateTime(leave.endDate).format(context);

    final String dateRangeDisplay;
    if (isStartFullDay && isEndFullDay) {
      if (leave.startDate.year == leave.endDate.year &&
          leave.startDate.month == leave.endDate.month &&
          leave.startDate.day == leave.endDate.day) {
        dateRangeDisplay = '${leave.startDate.day}/${leave.startDate.month}/${leave.startDate.year} (Full Day)';
      } else {
        dateRangeDisplay = '${leave.startDate.day}/${leave.startDate.month}/${leave.startDate.year} - ${leave.endDate.day}/${leave.endDate.month}/${leave.endDate.year} (Full Days)';
      }
    } else if (isStartFullDay) {
      dateRangeDisplay = '${leave.startDate.day}/${leave.startDate.month}/${leave.startDate.year} (Full Day) - ${leave.endDate.day}/${leave.endDate.month}/${leave.endDate.year} ($endTimeStr)';
    } else if (isEndFullDay) {
      dateRangeDisplay = '${leave.startDate.day}/${leave.startDate.month}/${leave.startDate.year} ($startTimeStr) - ${leave.endDate.day}/${leave.endDate.month}/${leave.endDate.year} (Full Day)';
    } else {
      dateRangeDisplay = '${leave.startDate.day}/${leave.startDate.month}/${leave.startDate.year} ($startTimeStr) - ${leave.endDate.day}/${leave.endDate.month}/${leave.endDate.year} ($endTimeStr)';
    }

    return Card(
      margin: EdgeInsets.only(bottom: rs.height(12)),
      elevation: 1.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(rs.scale(14)),
        side: BorderSide(
          color: isDarkMode ? Colors.white24 : Colors.grey.shade300,
        ),
      ),
      child: Padding(
        padding: rs.insetsAll(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: rs.insetsAll(8),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.event_available_outlined,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                SizedBox(width: rs.width(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        leave.name,
                        style: TextStyle(
                          fontSize: rs.font(16),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: rs.height(4)),
                      Text(
                        dateRangeDisplay,
                        style: TextStyle(
                          fontSize: rs.font(12),
                          color: isDarkMode ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                  onPressed: () => _showEditLeaveDialog(context, leave, subjects),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: isDarkMode ? Colors.red.shade300 : Colors.red.shade700,
                  onPressed: () => _confirmDeleteLeave(context, leave),
                ),
              ],
            ),
            SizedBox(height: rs.height(12)),
            const Divider(),
            SizedBox(height: rs.height(8)),
            Row(
              children: [
                Icon(
                  Icons.event_busy_outlined,
                  size: 16,
                  color: isDarkMode ? Colors.amber.shade300 : Colors.amber.shade900,
                ),
                SizedBox(width: rs.width(6)),
                Expanded(
                  child: Text(
                    'Total Classes Affected: $totalClassesMissed',
                    style: TextStyle(
                      fontSize: rs.font(13),
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.amber.shade300 : Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: rs.height(4)),
            Text(
              missedBreakdownText,
              style: TextStyle(
                fontSize: rs.font(12),
                color: isDarkMode ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddLeaveDialog(BuildContext parentContext, List<Subject> subjects) {
    final rs = parentContext.rs;
    final isDarkMode = Theme.of(parentContext).brightness == Brightness.dark;
    final nameController = TextEditingController();

    final now = DateTime.now();
    bool isStartFullDay = true;
    bool isEndFullDay = true;
    DateTime startDate = DateTime(now.year, now.month, now.day + 1, 0, 0);
    DateTime endDate = DateTime(now.year, now.month, now.day + 3, 23, 59);

    showDialog(
      context: parentContext,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final startTimeTod = TimeOfDay.fromDateTime(startDate);
            final endTimeTod = TimeOfDay.fromDateTime(endDate);

            return AlertDialog(
              title: const Text('Add Leave'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Reason for Leave',
                        hintText: 'e.g. Medical Leave, Family Event',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                    SizedBox(height: rs.height(16)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Start Date & Time',
                          style: TextStyle(
                            fontSize: rs.font(12),
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setDialogState(() {
                              isStartFullDay = !isStartFullDay;
                              if (isStartFullDay) {
                                startDate = DateTime(startDate.year, startDate.month, startDate.day, 0, 0);
                              } else {
                                startDate = DateTime(startDate.year, startDate.month, startDate.day, 9, 0);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: Checkbox(
                                    value: isStartFullDay,
                                    activeColor: Theme.of(context).colorScheme.primary,
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setDialogState(() {
                                        isStartFullDay = val;
                                        if (isStartFullDay) {
                                          startDate = DateTime(startDate.year, startDate.month, startDate.day, 0, 0);
                                        } else {
                                          startDate = DateTime(startDate.year, startDate.month, startDate.day, 9, 0);
                                        }
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(width: rs.width(4)),
                                Text(
                                  'Full Day',
                                  style: TextStyle(
                                    fontSize: rs.font(12),
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode ? Colors.white : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(4)),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text('${startDate.day}/${startDate.month}/${startDate.year}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  final h = isStartFullDay ? 0 : startDate.hour;
                                  final m = isStartFullDay ? 0 : startDate.minute;
                                  startDate = DateTime(picked.year, picked.month, picked.day, h, m);
                                  if (endDate.isBefore(startDate)) {
                                    final endH = isEndFullDay ? 23 : startDate.hour + 2;
                                    final endM = isEndFullDay ? 59 : startDate.minute;
                                    endDate = DateTime(picked.year, picked.month, picked.day, endH, endM);
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        SizedBox(width: rs.width(8)),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time, size: 16),
                            label: Text(isStartFullDay ? 'Full Day' : startTimeTod.format(context)),
                            onPressed: isStartFullDay
                                ? null
                                : () async {
                                    final picked = await showAppTimePicker(
                                      context: context,
                                      initialTime: startTimeTod,
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        startDate = DateTime(startDate.year, startDate.month, startDate.day, picked.hour, picked.minute);
                                        if (endDate.isBefore(startDate)) {
                                          endDate = startDate.add(const Duration(hours: 2));
                                        }
                                      });
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(12)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'End Date & Time',
                          style: TextStyle(
                            fontSize: rs.font(12),
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setDialogState(() {
                              isEndFullDay = !isEndFullDay;
                              if (isEndFullDay) {
                                endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59);
                              } else {
                                endDate = DateTime(endDate.year, endDate.month, endDate.day, 17, 0);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: Checkbox(
                                    value: isEndFullDay,
                                    activeColor: Theme.of(context).colorScheme.primary,
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setDialogState(() {
                                        isEndFullDay = val;
                                        if (isEndFullDay) {
                                          endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59);
                                        } else {
                                          endDate = DateTime(endDate.year, endDate.month, endDate.day, 17, 0);
                                        }
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(width: rs.width(4)),
                                Text(
                                  'Full Day',
                                  style: TextStyle(
                                    fontSize: rs.font(12),
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode ? Colors.white : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(4)),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text('${endDate.day}/${endDate.month}/${endDate.year}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: endDate,
                                firstDate: startDate,
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  final h = isEndFullDay ? 23 : endDate.hour;
                                  final m = isEndFullDay ? 59 : endDate.minute;
                                  endDate = DateTime(picked.year, picked.month, picked.day, h, m);
                                });
                              }
                            },
                          ),
                        ),
                        SizedBox(width: rs.width(8)),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time, size: 16),
                            label: Text(isEndFullDay ? 'Full Day' : endTimeTod.format(context)),
                            onPressed: isEndFullDay
                                ? null
                                : () async {
                                    final picked = await showAppTimePicker(
                                      context: context,
                                      initialTime: endTimeTod,
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        endDate = DateTime(endDate.year, endDate.month, endDate.day, picked.hour, picked.minute);
                                      });
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                    foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                  ),
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final messenger = ScaffoldMessenger.of(parentContext);
                    final nav = Navigator.of(dialogCtx);
                    final subjectProvider = Provider.of<SubjectProvider>(parentContext, listen: false);
                    if (name.isEmpty) {
                      messenger.showReplacingSnackBar(
                        const SnackBar(content: Text('Please enter a leave reason.')),
                      );
                      return;
                    }

                    final newLeave = PlannedLeave(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: name,
                      startDate: startDate,
                      endDate: endDate,
                      affectedSubjectIds: subjects.map((s) => s.id).toList(),
                    );

                    await _databaseService.savePlannedLeave(newLeave);
                    nav.pop();
                    _loadLeaves();
                    subjectProvider.scheduleAutoSync();
                    messenger.showReplacingSnackBar(
                      SnackBar(content: Text('Leave "$name" added.')),
                    );
                  },
                  child: const Text('Save Leave'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditLeaveDialog(BuildContext parentContext, PlannedLeave leave, List<Subject> subjects) {
    final rs = parentContext.rs;
    final isDarkMode = Theme.of(parentContext).brightness == Brightness.dark;
    final nameController = TextEditingController(text: leave.name);
    DateTime startDate = leave.startDate;
    DateTime endDate = leave.endDate;
    bool isStartFullDay = (startDate.hour == 0 && startDate.minute == 0);
    bool isEndFullDay = (endDate.hour == 23 && endDate.minute == 59);

    showDialog(
      context: parentContext,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final startTimeTod = TimeOfDay.fromDateTime(startDate);
            final endTimeTod = TimeOfDay.fromDateTime(endDate);

            return AlertDialog(
              title: const Text('Edit Leave'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Reason for Leave',
                        hintText: 'e.g. Medical Leave, Family Event',
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                    SizedBox(height: rs.height(16)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Start Date & Time',
                          style: TextStyle(
                            fontSize: rs.font(12),
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setDialogState(() {
                              isStartFullDay = !isStartFullDay;
                              if (isStartFullDay) {
                                startDate = DateTime(startDate.year, startDate.month, startDate.day, 0, 0);
                              } else {
                                startDate = DateTime(startDate.year, startDate.month, startDate.day, 9, 0);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: Checkbox(
                                    value: isStartFullDay,
                                    activeColor: Theme.of(context).colorScheme.primary,
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setDialogState(() {
                                        isStartFullDay = val;
                                        if (isStartFullDay) {
                                          startDate = DateTime(startDate.year, startDate.month, startDate.day, 0, 0);
                                        } else {
                                          startDate = DateTime(startDate.year, startDate.month, startDate.day, 9, 0);
                                        }
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(width: rs.width(4)),
                                Text(
                                  'Full Day',
                                  style: TextStyle(
                                    fontSize: rs.font(12),
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode ? Colors.white : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(4)),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text('${startDate.day}/${startDate.month}/${startDate.year}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  final h = isStartFullDay ? 0 : startDate.hour;
                                  final m = isStartFullDay ? 0 : startDate.minute;
                                  startDate = DateTime(picked.year, picked.month, picked.day, h, m);
                                  if (endDate.isBefore(startDate)) {
                                    final endH = isEndFullDay ? 23 : startDate.hour + 2;
                                    final endM = isEndFullDay ? 59 : startDate.minute;
                                    endDate = DateTime(picked.year, picked.month, picked.day, endH, endM);
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        SizedBox(width: rs.width(8)),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time, size: 16),
                            label: Text(isStartFullDay ? 'Full Day' : startTimeTod.format(context)),
                            onPressed: isStartFullDay
                                ? null
                                : () async {
                                    final picked = await showAppTimePicker(
                                      context: context,
                                      initialTime: startTimeTod,
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        startDate = DateTime(startDate.year, startDate.month, startDate.day, picked.hour, picked.minute);
                                        if (endDate.isBefore(startDate)) {
                                          endDate = startDate.add(const Duration(hours: 2));
                                        }
                                      });
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(12)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'End Date & Time',
                          style: TextStyle(
                            fontSize: rs.font(12),
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setDialogState(() {
                              isEndFullDay = !isEndFullDay;
                              if (isEndFullDay) {
                                endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59);
                              } else {
                                endDate = DateTime(endDate.year, endDate.month, endDate.day, 17, 0);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: Checkbox(
                                    value: isEndFullDay,
                                    activeColor: Theme.of(context).colorScheme.primary,
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setDialogState(() {
                                        isEndFullDay = val;
                                        if (isEndFullDay) {
                                          endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59);
                                        } else {
                                          endDate = DateTime(endDate.year, endDate.month, endDate.day, 17, 0);
                                        }
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(width: rs.width(4)),
                                Text(
                                  'Full Day',
                                  style: TextStyle(
                                    fontSize: rs.font(12),
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode ? Colors.white : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(4)),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text('${endDate.day}/${endDate.month}/${endDate.year}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: endDate,
                                firstDate: startDate,
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  final h = isEndFullDay ? 23 : endDate.hour;
                                  final m = isEndFullDay ? 59 : endDate.minute;
                                  endDate = DateTime(picked.year, picked.month, picked.day, h, m);
                                });
                              }
                            },
                          ),
                        ),
                        SizedBox(width: rs.width(8)),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.access_time, size: 16),
                            label: Text(isEndFullDay ? 'Full Day' : endTimeTod.format(context)),
                            onPressed: isEndFullDay
                                ? null
                                : () async {
                                    final picked = await showAppTimePicker(
                                      context: context,
                                      initialTime: endTimeTod,
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        endDate = DateTime(endDate.year, endDate.month, endDate.day, picked.hour, picked.minute);
                                      });
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black,
                    foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                  ),
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final messenger = ScaffoldMessenger.of(parentContext);
                    final nav = Navigator.of(dialogCtx);
                    final subjectProvider = Provider.of<SubjectProvider>(parentContext, listen: false);
                    if (name.isEmpty) {
                      messenger.showReplacingSnackBar(
                        const SnackBar(content: Text('Please enter a leave reason.')),
                      );
                      return;
                    }

                    final updatedLeave = PlannedLeave(
                      id: leave.id,
                      name: name,
                      startDate: startDate,
                      endDate: endDate,
                      affectedSubjectIds: subjects.map((s) => s.id).toList(),
                    );

                    await _databaseService.savePlannedLeave(updatedLeave);
                    nav.pop();
                    _loadLeaves();
                    subjectProvider.scheduleAutoSync();
                    messenger.showReplacingSnackBar(
                      SnackBar(content: Text('Leave "$name" updated.')),
                    );
                  },
                  child: const Text('Update Leave'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteLeave(BuildContext context, PlannedLeave leave) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
    showDialog(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Leave'),
        content: Text('Are you sure you want to delete "${leave.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final dialogNav = Navigator.of(ctx);
              await _databaseService.deletePlannedLeave(leave.id);
              dialogNav.pop();
              _loadLeaves();
              subjectProvider.scheduleAutoSync();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
