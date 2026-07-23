import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../features/attendance/attendance_model.dart';
import '../../features/attendance/attendance_provider.dart';
import '../../features/planner/planned_leave_model.dart';
import '../../features/semester/semester_provider.dart';
import '../../features/settings/time_format_provider.dart';
import '../../features/subject/subject_model.dart';
import '../../features/subject/subject_provider.dart';
import '../../services/database_service.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_overlay.dart';
import 'calendar_utils.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _selectedMonth;
  DateTime? _pressedDate;
  DayState? _selectedStateFilter;
  PageController? _monthPageController;
  List<DateTime> _monthPages = [];
  List<PlannedLeave> _plannedLeaves = [];

  final GlobalKey _calendarHeaderKey = GlobalKey();
  final GlobalKey _calendarLegendKey = GlobalKey();
  final GlobalKey _calendarGridKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime.now();
    _loadPlannedLeaves();

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
    if (tutorialController.isActive && (tutorialController.currentStepIndex < 16 || tutorialController.currentStepIndex >= 19)) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _loadPlannedLeaves() async {
    final leaves = await DatabaseService().loadPlannedLeaves();
    if (mounted) {
      setState(() {
        _plannedLeaves = leaves;
      });
    }
  }

  Future<void> _autoMarkPlannedLeaves(
    List<PlannedLeave> plannedLeaves,
    List<Subject> subjects,
    AttendanceProvider attendanceProvider,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59);

    for (final leave in plannedLeaves) {
      DateTime current = DateTime(leave.startDate.year, leave.startDate.month, leave.startDate.day);
      final end = DateTime(leave.endDate.year, leave.endDate.month, leave.endDate.day);

      while (!current.isAfter(end) && !current.isAfter(today)) {
        for (final subject in subjects) {
          if (leave.affectedSubjectIds.isNotEmpty && !leave.affectedSubjectIds.contains(subject.id)) continue;
          for (final slot in subject.schedule) {
            if (slot.occursOnDate(current)) {
              final slotStart = DateTime(current.year, current.month, current.day, slot.startTime.hour, slot.startTime.minute);
              final slotEnd = DateTime(current.year, current.month, current.day, slot.endTime.hour, slot.endTime.minute);
              if (slotStart.isBefore(leave.endDate) && slotEnd.isAfter(leave.startDate)) {
                final hasRecord = attendanceProvider.attendanceRecords.any(
                  (r) => r.subjectId == subject.id &&
                         r.date.year == current.year &&
                         r.date.month == current.month &&
                         r.date.day == current.day &&
                         (r.slotKey == null || r.slotKey == slot.slotKey || r.slotKey!.isEmpty),
                );

                if (!hasRecord) {
                  await attendanceProvider.markAttendance(
                    subject.id,
                    current,
                    AttendanceStatus.absent,
                    slotKey: slot.slotKey,
                  );
                }
              }
            }
          }
        }
        current = current.add(const Duration(days: 1));
      }
    }
  }

  @override
  void dispose() {
    try {
      final tutorialController = Provider.of<TutorialController>(context, listen: false);
      tutorialController.removeListener(_onTutorialStepChanged);
    } catch (_) {}
    _monthPageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    tutorialController.registerKey('key_calendar_header', _calendarHeaderKey);
    tutorialController.registerKey('key_calendar_legend', _calendarLegendKey);
    tutorialController.registerKey('key_calendar_grid', _calendarGridKey);

    final semesterProvider = Provider.of<SemesterProvider>(context);
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final attendanceProvider = Provider.of<AttendanceProvider>(context);

    if (semesterProvider.semester == null) {
      return const Scaffold(
        body: Center(child: Text('Semester not set')),
      );
    }

    if (_plannedLeaves.isNotEmpty && subjectProvider.subjects.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _autoMarkPlannedLeaves(_plannedLeaves, subjectProvider.subjects, attendanceProvider);
        }
      });
    }

    final startDate = semesterProvider.semester!.startDate;
    final endDate = semesterProvider.semester!.endDate;
    final startMonth = DateTime(startDate.year, startDate.month, 1);
    final endMonth = DateTime(endDate.year, endDate.month, 1);
    final selectedMonthOnly = DateTime(_selectedMonth.year, _selectedMonth.month, 1);

    if (selectedMonthOnly.isBefore(startMonth)) {
      _selectedMonth = startMonth;
    } else if (selectedMonthOnly.isAfter(endMonth)) {
      _selectedMonth = endMonth;
    }

    final rs = context.rs;

    final now = DateTime.now();
    final isCurrentMonth = _isSameMonthYear(_selectedMonth, now);

    return TutorialOverlay(
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Attendance Calendar',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          elevation: 0,
          centerTitle: false,
          actions: [
            if (!isCurrentMonth)
              IconButton(
                icon: const Icon(Icons.today_rounded),
                tooltip: 'Go to Today',
                onPressed: () => _goToToday(startDate, endDate),
              ),
          ],
        ),
        body: Column(
          children: [
            // Modern Month/Year Header Card with Today Shortcut
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: rs.width(16),
                vertical: rs.height(8),
              ),
              child: KeyedSubtree(
                key: _calendarHeaderKey,
                child: _buildHeaderCard(context, startDate, endDate),
              ),
            ),
            // Horizontal Chip Legend
            Padding(
              padding: EdgeInsets.symmetric(horizontal: rs.width(16)),
              child: KeyedSubtree(
                key: _calendarLegendKey,
                child: _buildLegend(),
              ),
            ),
            SizedBox(height: rs.height(12)),
            // Calendar Grid PageView
            Expanded(
              child: KeyedSubtree(
                key: _calendarGridKey,
                child: Builder(
                  builder: (context) {
                    final monthPages = _getMonthPages(startDate, endDate);
                    final selectedIndex = monthPages.indexWhere(
                      (month) => _isSameMonthYear(month, _selectedMonth),
                    );
                    final safeSelectedIndex = selectedIndex < 0 ? 0 : selectedIndex;
                    _monthPages = monthPages;

                    _monthPageController ??= PageController(
                      initialPage: safeSelectedIndex,
                    );

                    return PageView.builder(
                      controller: _monthPageController,
                      itemCount: monthPages.length,
                      onPageChanged: (index) {
                        setState(() {
                          _selectedMonth = monthPages[index];
                        });
                      },
                      itemBuilder: (context, index) {
                        final month = monthPages[index];
                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Padding(
                            padding: EdgeInsets.all(rs.scale(16)),
                            child: _buildCalendarGrid(
                              month,
                              startDate,
                              endDate,
                              subjectProvider.subjects,
                              attendanceProvider.attendanceRecords,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameMonthYear(DateTime first, DateTime second) {
    return first.year == second.year && first.month == second.month;
  }

  void _goToNextMonth(DateTime endDate) {
    if (_isSameMonthYear(_selectedMonth, endDate) ||
        _monthPageController == null ||
        _monthPages.isEmpty) {
      return;
    }

    final currentIndex = _monthPages.indexWhere(
      (month) => _isSameMonthYear(month, _selectedMonth),
    );
    final targetIndex = currentIndex + 1;

    if (currentIndex >= 0 && targetIndex < _monthPages.length) {
      _monthPageController!.animateToPage(
        targetIndex,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _goToPreviousMonth(DateTime startDate) {
    if (_isSameMonthYear(_selectedMonth, startDate) ||
        _monthPageController == null ||
        _monthPages.isEmpty) {
      return;
    }

    final currentIndex = _monthPages.indexWhere(
      (month) => _isSameMonthYear(month, _selectedMonth),
    );
    final targetIndex = currentIndex - 1;

    if (currentIndex >= 0 && targetIndex >= 0) {
      _monthPageController!.animateToPage(
        targetIndex,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _goToToday(DateTime startDate, DateTime endDate) {
    final now = DateTime.now();
    final todayMonth = DateTime(now.year, now.month, 1);
    final startMonth = DateTime(startDate.year, startDate.month, 1);
    final endMonth = DateTime(endDate.year, endDate.month, 1);

    DateTime targetMonth = todayMonth;
    if (targetMonth.isBefore(startMonth)) targetMonth = startMonth;
    if (targetMonth.isAfter(endMonth)) targetMonth = endMonth;

    if (_monthPageController != null && _monthPages.isNotEmpty) {
      final targetIndex = _monthPages.indexWhere(
        (month) => _isSameMonthYear(month, targetMonth),
      );
      if (targetIndex >= 0) {
        _monthPageController!.animateToPage(
          targetIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  List<DateTime> _getMonthPages(DateTime startDate, DateTime endDate) {
    final months = <DateTime>[];
    var current = DateTime(startDate.year, startDate.month, 1);
    final last = DateTime(endDate.year, endDate.month, 1);

    while (!current.isAfter(last)) {
      months.add(current);
      current = DateTime(current.year, current.month + 1, 1);
    }

    return months;
  }

  Widget _buildHeaderCard(
    BuildContext context,
    DateTime startDate,
    DateTime endDate,
  ) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: rs.width(12),
        vertical: rs.height(8),
      ),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(rs.scale(16)),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: rs.scale(8),
            offset: Offset(0, rs.scale(2)),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            iconSize: rs.scale(26),
            onPressed: _isSameMonthYear(_selectedMonth, startDate)
                ? null
                : () => _goToPreviousMonth(startDate),
          ),
          Expanded(
            child: Text(
              '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: rs.font(18),
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            iconSize: rs.scale(26),
            onPressed: _isSameMonthYear(_selectedMonth, endDate)
                ? null
                : () => _goToNextMonth(endDate),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final legendItems = [
      (DayState.attendedFullDay, 'Attended'),
      (DayState.bunkedFullDay, 'Bunked'),
      (DayState.plannedLeave, 'Planned Leave'),
      (DayState.classesNotMarked, 'Not Marked'),
      (DayState.classesMarked, 'Mixed'),
      (DayState.holiday, 'Holiday'),
      (DayState.futureClasses, 'Upcoming'),
      (DayState.noClasses, 'No Classes'),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: rs.width(10),
        vertical: rs.height(8),
      ),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(rs.scale(14)),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: rs.width(6),
            runSpacing: rs.height(6),
            alignment: WrapAlignment.center,
            children: legendItems
                .map((item) => _buildLegendItem(item.$1, item.$2))
                .toList(),
          ),
          if (_selectedStateFilter != null) ...[
            SizedBox(height: rs.height(6)),
            InkWell(
              onTap: () {
                setState(() {
                  _selectedStateFilter = null;
                });
              },
              borderRadius: BorderRadius.circular(rs.scale(10)),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: rs.width(6),
                  vertical: rs.height(2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.clear_rounded,
                      size: rs.scale(12),
                      color: theme.colorScheme.primary,
                    ),
                    SizedBox(width: rs.width(2)),
                    Text(
                      'Clear Filter',
                      style: TextStyle(
                        fontSize: rs.font(11),
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
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

  Widget _buildLegendItem(DayState state, String label) {
    final rs = context.rs;
    final color = CalendarUtils.getStateColor(state);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isSelected = _selectedStateFilter == state;
    final isAnyFilterActive = _selectedStateFilter != null;

    return Tooltip(
      message: isSelected ? 'Tap to clear filter' : 'Filter by ${CalendarUtils.getStateLabel(state)}',
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (_selectedStateFilter == state) {
              _selectedStateFilter = null;
            } else {
              _selectedStateFilter = state;
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: rs.width(8),
            vertical: rs.height(4),
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? color
                : isAnyFilterActive
                    ? color.withValues(alpha: isDark ? 0.08 : 0.05)
                    : color.withValues(alpha: isDark ? 0.2 : 0.12),
            borderRadius: BorderRadius.circular(rs.scale(12)),
            border: Border.all(
              color: isSelected
                  ? Colors.white
                  : color.withValues(alpha: isAnyFilterActive ? 0.2 : 0.35),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: rs.scale(6),
                      offset: Offset(0, rs.scale(2)),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: rs.scale(14),
                height: rs.scale(14),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : color,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSelected ? Icons.check_rounded : CalendarUtils.getStateIcon(state),
                  size: rs.scale(9),
                  color: isSelected ? color : Colors.white,
                ),
              ),
              SizedBox(width: rs.width(4)),
              Text(
                label,
                style: TextStyle(
                  fontSize: rs.font(11),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : isAnyFilterActive
                          ? (isDark ? Colors.white38 : Colors.black38)
                          : (isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid(
    DateTime month,
    DateTime startDate,
    DateTime endDate,
    List<Subject> subjects,
    List<Attendance> attendanceRecords,
  ) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final lastDayOfMonth = DateTime(month.year, month.month + 1, 0);

    final displayStartDate = firstDayOfMonth.isBefore(startDate)
        ? startDate
        : firstDayOfMonth;
    final displayEndDate =
        lastDayOfMonth.isAfter(endDate) ? endDate : lastDayOfMonth;

    final int daysInMonth = displayEndDate.difference(displayStartDate).inDays + 1;
    final int firstWeekday = displayStartDate.weekday;

    final Map<DateTime, List<Attendance>> indexedRecords = {};
    for (final record in attendanceRecords) {
      final normalizedDate = DateTime(record.date.year, record.date.month, record.date.day);
      indexedRecords.putIfAbsent(normalizedDate, () => []).add(record);
    }

    return Column(
      children: [
        // Styled Weekday Headers
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
              .map((day) {
                final isWeekend = day == 'Sat' || day == 'Sun';
                return Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: rs.height(6)),
                    child: Text(
                      day,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: rs.font(12),
                        color: isWeekend
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                );
              })
              .toList(),
        ),
        SizedBox(height: rs.height(8)),
        // Calendar grid day cells
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: rs.height(8),
            crossAxisSpacing: rs.width(8),
            childAspectRatio: 1.0,
          ),
          itemCount: (firstWeekday - 1) + daysInMonth,
          itemBuilder: (context, index) {
            if (index < firstWeekday - 1) {
              return const SizedBox.shrink();
            }

            final dayOffset = index - (firstWeekday - 1);
            final date = displayStartDate.add(Duration(days: dayOffset));

            final dayInfo = CalendarUtils.getDayState(
              date: date,
              subjects: subjects,
              attendanceRecords: attendanceRecords,
              indexedRecords: indexedRecords,
              plannedLeaves: _plannedLeaves,
            );

            return _buildDayCell(context, dayInfo);
          },
        ),
      ],
    );
  }

  Widget _buildDayCell(BuildContext context, CalendarDayInfo dayInfo) {
    final rs = context.rs;
    final now = DateTime.now();
    final isToday = CalendarUtils.isSameDay(dayInfo.date, now);
    final isPressed = _pressedDate != null && CalendarUtils.isSameDay(_pressedDate!, dayInfo.date);

    final matchesFilter = _selectedStateFilter == null || dayInfo.state == _selectedStateFilter;

    final baseColor = CalendarUtils.getStateColor(dayInfo.state);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final displayColor = isPressed
        ? _darkenColor(baseColor)
        : matchesFilter
            ? baseColor
            : (isDark
                ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2)
                : Colors.grey[200]!);

    final textColor = matchesFilter
        ? Colors.white
        : (isDark ? Colors.white24 : Colors.black26);

    final iconColor = matchesFilter
        ? Colors.white.withValues(alpha: 0.9)
        : (isDark ? Colors.white12 : Colors.black12);

    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.vibrate();
        setState(() {
          _pressedDate = dayInfo.date;
        });
      },
      onTapUp: (_) {
        setState(() {
          _pressedDate = null;
        });
        _showDayDetailsDialog(context, dayInfo);
      },
      onTapCancel: () {
        setState(() {
          _pressedDate = null;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: displayColor,
          borderRadius: BorderRadius.circular(rs.scale(12)),
          border: isToday
              ? Border.all(
                  color: matchesFilter ? Colors.white : theme.colorScheme.primary.withValues(alpha: 0.4),
                  width: rs.scale(2.5),
                )
              : matchesFilter
                  ? null
                  : Border.all(
                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    ),
          boxShadow: (isPressed || !matchesFilter)
              ? []
              : [
                  BoxShadow(
                    color: displayColor.withValues(alpha: 0.3),
                    blurRadius: rs.scale(4),
                    offset: Offset(0, rs.scale(2)),
                  ),
                ],
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dayInfo.date.day.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontSize: rs.font(13),
                    ),
                  ),
                  SizedBox(height: rs.height(2)),
                  Icon(
                    CalendarUtils.getStateIcon(dayInfo.state),
                    size: rs.scale(15),
                    color: iconColor,
                  ),
                ],
              ),
            ),
            if (isToday)
              Positioned(
                top: rs.scale(4),
                right: rs.scale(4),
                child: Container(
                  width: rs.scale(6),
                  height: rs.scale(6),
                  decoration: BoxDecoration(
                    color: matchesFilter ? Colors.white : theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDayDetailsDialog(BuildContext context, CalendarDayInfo dayInfo) {
    final attendanceProvider = Provider.of<AttendanceProvider>(
      context,
      listen: false,
    );
    final subjectProvider = Provider.of<SubjectProvider>(
      context,
      listen: false,
    );
    final semesterProvider = Provider.of<SemesterProvider>(
      context,
      listen: false,
    );

    if (semesterProvider.semester == null) {
      return;
    }

    final startDate = semesterProvider.semester!.startDate;
    final endDate = semesterProvider.semester!.endDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.12)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.rs.scale(24)),
        ),
      ),
      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      builder: (context) => _buildDayDetailsModal(
        context,
        dayInfo,
        subjectProvider,
        attendanceProvider,
        startDate,
        endDate,
      ),
    );
  }

  Future<void> _copyTimetableIntoDate({
    required BuildContext context,
    required DateTime targetDate,
    required DateTime startDate,
    required DateTime endDate,
    required SubjectProvider subjectProvider,
    required VoidCallback refreshModal,
  }) async {
    final normalizedTarget = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final candidateInitial = normalizedTarget.subtract(const Duration(days: 1));
    final normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);
    final normalizedEnd = DateTime(endDate.year, endDate.month, endDate.day);

    DateTime initialDate = candidateInitial;
    if (initialDate.isBefore(normalizedStart)) {
      initialDate = normalizedStart;
    } else if (initialDate.isAfter(normalizedEnd)) {
      initialDate = normalizedEnd;
    }

    final sourceDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: normalizedStart,
      lastDate: normalizedEnd,
      helpText: 'Copy classes from date',
    );

    if (!context.mounted) {
      return;
    }

    if (sourceDate == null) {
      return;
    }

    final normalizedSource = DateTime(sourceDate.year, sourceDate.month, sourceDate.day);
    if (CalendarUtils.isSameDay(normalizedSource, normalizedTarget)) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('Choose a different source date.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await subjectProvider.copyDayTimetable(
      sourceDate: normalizedSource,
      targetDate: normalizedTarget,
    );

    if (!context.mounted) {
      return;
    }

    if (!result.hasSourceClasses) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('No classes found on source date.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    refreshModal();

    final replacementText = result.replacedExistingClasses
        ? 'Replaced ${result.replacedClasses} class(es) on target date.'
        : 'Target date had no classes; copied directly.';
    ScaffoldMessenger.of(context).showReplacingSnackBar(
      SnackBar(
        content: Text('Copied ${result.copiedClasses} class(es). $replacementText'),
      ),
    );
  }

  Widget _buildDayDetailsModal(
    BuildContext context,
    CalendarDayInfo dayInfo,
    SubjectProvider subjectProvider,
    AttendanceProvider attendanceProvider,
    DateTime startDate,
    DateTime endDate,
  ) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);
    final swipableDates = _getSwipableDayDates(
      currentDate: dayInfo.date,
      startDate: startDate,
      endDate: endDate,
      subjects: subjectProvider.subjects,
      attendanceRecords: attendanceProvider.attendanceRecords,
    );
    final initialPageIndex = swipableDates.indexWhere(
      (date) => CalendarUtils.isSameDay(date, dayInfo.date),
    );
    final dayPageController = PageController(
      initialPage: initialPageIndex < 0 ? 0 : initialPageIndex,
    );

    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: rs.width(16),
            right: rs.width(16),
            top: rs.height(12),
          ),
          child: Column(
            children: [
              // Top Drag Handle
              Container(
                width: rs.width(36),
                height: rs.height(4),
                margin: EdgeInsets.only(bottom: rs.height(12)),
                decoration: BoxDecoration(
                  color: theme.dividerColor.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(rs.scale(2)),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: dayPageController,
                  itemCount: swipableDates.length,
                  itemBuilder: (context, pageIndex) {
                    final pageDate = swipableDates[pageIndex];
                    final pageDayInfo = CalendarUtils.getDayState(
                      date: pageDate,
                      subjects: subjectProvider.subjects,
                      attendanceRecords: attendanceProvider.attendanceRecords,
                      plannedLeaves: _plannedLeaves,
                    );
                    final classesForDay = _expandSubjectsBySlotForDay(
                      pageDayInfo.subjectsWithClassesToday,
                      pageDate,
                    );
                    final dateFormatter = _formatDate(pageDate);
                    final stateColor = CalendarUtils.getStateColor(pageDayInfo.state);

                    final activeLeave = _plannedLeaves.cast<PlannedLeave?>().firstWhere(
                      (l) => l != null &&
                             !pageDate.isBefore(DateTime(l.startDate.year, l.startDate.month, l.startDate.day)) &&
                             !pageDate.isAfter(DateTime(l.endDate.year, l.endDate.month, l.endDate.day)),
                      orElse: () => null,
                    );

                    return Column(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Modal Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dateFormatter,
                                  style: TextStyle(
                                    fontSize: rs.font(18),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: rs.height(4)),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: rs.width(8),
                                    vertical: rs.height(3),
                                  ),
                                  decoration: BoxDecoration(
                                    color: stateColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(rs.scale(8)),
                                    border: Border.all(
                                      color: stateColor.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    CalendarUtils.getStateLabel(pageDayInfo.state),
                                    style: TextStyle(
                                      color: stateColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: rs.font(11),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        SizedBox(height: rs.height(12)),
                        const Divider(),
                        SizedBox(height: rs.height(8)),
                        if (activeLeave != null) ...[
                          Container(
                            padding: rs.insetsAll(10),
                            margin: EdgeInsets.only(bottom: rs.height(10)),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF7043).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(rs.scale(12)),
                              border: Border.all(color: const Color(0xFFFF7043).withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.event_busy_rounded, color: const Color(0xFFFF7043), size: rs.scale(20)),
                                SizedBox(width: rs.width(8)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Planned Leave: ${activeLeave.name}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: rs.font(12),
                                          color: const Color(0xFFFF7043),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Classes on this day are automatically marked as Absent.',
                                        style: TextStyle(
                                          fontSize: rs.font(11),
                                          color: theme.brightness == Brightness.dark ? Colors.white70 : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Bulk Action Buttons Row
                        if (pageDayInfo.classesCount > 0 &&
                            pageDayInfo.state != DayState.futureClasses)
                          Padding(
                            padding: EdgeInsets.only(bottom: rs.height(12)),
                            child: Row(
                              children: [
                                _buildBulkActionButton(
                                  context: context,
                                  icon: Icons.check_circle_outline_rounded,
                                  label: 'Present',
                                  color: const Color(0xFF4CAF50),
                                  onPressed: () async {
                                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                                    final navigator = Navigator.of(context);
                                    final subjectProvider =
                                        Provider.of<SubjectProvider>(context, listen: false);
                                    final editableClasses = classesForDay
                                        .where((subject) => !_isLockedByManualOverride(subject, pageDate))
                                        .toList();
                                    final lockedCount = classesForDay.length - editableClasses.length;

                                    if (editableClasses.isEmpty) {
                                      ScaffoldMessenger.of(context).showReplacingSnackBar(
                                        const SnackBar(
                                          content: Text('Classes on this date are locked due to manual count update.'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }

                                    for (final subject in editableClasses) {
                                      await subjectProvider.markAttendance(
                                        subject.id,
                                        pageDate,
                                        AttendanceStatus.attended,
                                        slotKey: subject.schedule.first.slotKey,
                                      );
                                    }

                                    final message = lockedCount > 0
                                        ? 'Marked ${editableClasses.length} class(es) as present. $lockedCount locked.'
                                        : 'All classes marked as present';
                                    scaffoldMessenger.showReplacingSnackBar(
                                      SnackBar(content: Text(message)),
                                    );
                                    navigator.pop();
                                  },
                                ),
                                SizedBox(width: rs.width(8)),
                                _buildBulkActionButton(
                                  context: context,
                                  icon: Icons.highlight_off_rounded,
                                  label: 'Skip Day',
                                  color: const Color(0xFFEF5350),
                                  onPressed: () async {
                                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                                    final navigator = Navigator.of(context);
                                    final subjectProvider =
                                        Provider.of<SubjectProvider>(context, listen: false);
                                    final editableClasses = classesForDay
                                        .where((subject) => !_isLockedByManualOverride(subject, pageDate))
                                        .toList();
                                    final lockedCount = classesForDay.length - editableClasses.length;

                                    if (editableClasses.isEmpty) {
                                      ScaffoldMessenger.of(context).showReplacingSnackBar(
                                        const SnackBar(
                                          content: Text('Classes on this date are locked due to manual count update.'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }

                                    for (final subject in editableClasses) {
                                      await subjectProvider.markAttendance(
                                        subject.id,
                                        pageDate,
                                        AttendanceStatus.absent,
                                        slotKey: subject.schedule.first.slotKey,
                                      );
                                    }

                                    final message = lockedCount > 0
                                        ? 'Marked ${editableClasses.length} class(es) as absent. $lockedCount locked.'
                                        : 'All classes marked as absent';
                                    scaffoldMessenger.showReplacingSnackBar(
                                      SnackBar(content: Text(message)),
                                    );
                                    navigator.pop();
                                  },
                                ),
                                SizedBox(width: rs.width(8)),
                                _buildBulkActionButton(
                                  context: context,
                                  icon: Icons.celebration_outlined,
                                  label: 'Holiday',
                                  color: const Color(0xFFAB47BC),
                                  onPressed: () async {
                                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                                    final navigator = Navigator.of(context);
                                    final subjectProvider =
                                        Provider.of<SubjectProvider>(context, listen: false);
                                    final editableClasses = classesForDay
                                        .where((subject) => !_isLockedByManualOverride(subject, pageDate))
                                        .toList();
                                    final lockedCount = classesForDay.length - editableClasses.length;

                                    if (editableClasses.isEmpty) {
                                      ScaffoldMessenger.of(context).showReplacingSnackBar(
                                        const SnackBar(
                                          content: Text('Classes on this date are locked due to manual count update.'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      return;
                                    }

                                    for (final subject in editableClasses) {
                                      await subjectProvider.markAttendance(
                                        subject.id,
                                        pageDate,
                                        AttendanceStatus.cancelled,
                                        slotKey: subject.schedule.first.slotKey,
                                      );
                                    }

                                    final message = lockedCount > 0
                                        ? 'Marked ${editableClasses.length} class(es) as holiday. $lockedCount locked.'
                                        : 'Day marked as holiday';
                                    scaffoldMessenger.showReplacingSnackBar(
                                      SnackBar(content: Text(message)),
                                    );
                                    navigator.pop();
                                  },
                                ),
                              ],
                            ),
                          ),
                        // Copy Timetable Button
                        if (pageDayInfo.state != DayState.futureClasses)
                          Padding(
                            padding: EdgeInsets.only(bottom: rs.height(12)),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(rs.scale(12)),
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    vertical: rs.height(12),
                                  ),
                                ),
                                onPressed: () async {
                                  await _copyTimetableIntoDate(
                                    context: context,
                                    targetDate: pageDate,
                                    startDate: startDate,
                                    endDate: endDate,
                                    subjectProvider: subjectProvider,
                                    refreshModal: () => setState(() {}),
                                  );
                                },
                                icon: const Icon(Icons.copy_all_rounded, size: 18),
                                label: const Text(
                                  'Copy Timetable To This Day',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ),
                        // Subject list or Empty State
                        if (pageDayInfo.classesCount == 0)
                          Expanded(
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    pageDayInfo.state == DayState.holiday
                                        ? Icons.celebration_rounded
                                        : Icons.event_available_rounded,
                                    size: rs.scale(48),
                                    color: theme.disabledColor,
                                  ),
                                  SizedBox(height: rs.height(8)),
                                  Text(
                                    pageDayInfo.state == DayState.holiday
                                        ? 'Marked as Holiday'
                                        : 'No classes scheduled',
                                    style: TextStyle(
                                      color: theme.textTheme.bodySmall?.color,
                                      fontSize: rs.font(14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              itemCount: classesForDay.length,
                              itemBuilder: (context, index) {
                                final subject = classesForDay[index];
                                final slotKey = subject.schedule.first.slotKey;
                                final attendance = attendanceProvider.getAttendanceForSubjectOnDate(
                                  subject.id,
                                  pageDate,
                                  slotKey: slotKey,
                                );

                                return _buildSubjectAttendanceRow(
                                  context,
                                  subject,
                                  attendance,
                                  pageDate,
                                  pageDayInfo.state,
                                  attendanceProvider,
                                  setState,
                                  timeFormatProvider,
                                  slotKey,
                                );
                              },
                            ),
                          ),
                        SizedBox(height: rs.height(16)),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBulkActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final rs = context.rs;
    return Expanded(
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(rs.scale(12)),
        child: InkWell(
          onTap: () {
            HapticFeedback.vibrate();
            onPressed();
          },
          borderRadius: BorderRadius.circular(rs.scale(12)),
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: rs.height(10),
              horizontal: rs.width(4),
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(rs.scale(12)),
              border: Border.all(
                color: color.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: rs.scale(16), color: color),
                SizedBox(width: rs.width(4)),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: rs.font(12),
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<DateTime> _getSwipableDayDates({
    required DateTime currentDate,
    required DateTime startDate,
    required DateTime endDate,
    required List<Subject> subjects,
    required List<Attendance> attendanceRecords,
  }) {
    final classDates = <DateTime>[];
    var date = DateTime(startDate.year, startDate.month, startDate.day);
    final normalizedEndDate = DateTime(endDate.year, endDate.month, endDate.day);

    while (!date.isAfter(normalizedEndDate)) {
      int classesCount = 0;
      for (final subject in subjects) {
        for (final slot in subject.schedule) {
          if (slot.occursOnDate(date)) {
            classesCount++;
          }
        }
      }

      if (classesCount > 0) {
        classDates.add(date);
      }

      date = date.add(const Duration(days: 1));
    }

    final normalizedCurrent = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
    );

    if (classDates.any((d) => CalendarUtils.isSameDay(d, normalizedCurrent))) {
      return classDates;
    }

    if (classDates.isEmpty) {
      return [normalizedCurrent];
    }

    final combined = [...classDates, normalizedCurrent];
    combined.sort((a, b) => a.compareTo(b));

    final uniqueDates = <DateTime>[];
    for (final entry in combined) {
      if (uniqueDates.isEmpty || !CalendarUtils.isSameDay(uniqueDates.last, entry)) {
        uniqueDates.add(entry);
      }
    }

    return uniqueDates;
  }

  List<Subject> _expandSubjectsBySlotForDay(List<Subject> subjects, DateTime date) {
    final expandedSubjects = <Subject>[];

    for (final subject in subjects) {
      final slotsForDay = subject.schedule.where((slot) => slot.occursOnDate(date));
      for (final slot in slotsForDay) {
        expandedSubjects.add(subject.copyWith(schedule: [slot]));
      }
    }

    expandedSubjects.sort((a, b) {
      final aSlot = a.schedule.first;
      final bSlot = b.schedule.first;
      final aMinutes = aSlot.startTime.hour * 60 + aSlot.startTime.minute;
      final bMinutes = bSlot.startTime.hour * 60 + bSlot.startTime.minute;
      return aMinutes.compareTo(bMinutes);
    });

    return expandedSubjects;
  }

  Widget _buildSubjectAttendanceRow(
    BuildContext context,
    Subject subject,
    Attendance? attendance,
    DateTime date,
    DayState dayState,
    AttendanceProvider attendanceProvider,
    Function setState,
    TimeFormatProvider timeFormatProvider,
    String slotKey,
  ) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final status = attendance?.status;
    final isFutureClass = dayState == DayState.futureClasses;
    final isLockedByManualOverride = _isLockedByManualOverride(subject, date);
    final overrideDate = subject.manualAttendanceOverride?.effectiveFrom;
    final timeSlot = CalendarUtils.getTimeSlotForDate(subject, date);
    final timeText = timeSlot != null
        ? '${timeSlot.startTime.hour.toString().padLeft(2, '0')}:${timeSlot.startTime.minute.toString().padLeft(2, '0')} - ${timeSlot.endTime.hour.toString().padLeft(2, '0')}:${timeSlot.endTime.minute.toString().padLeft(2, '0')}'
        : '';

    return Container(
      margin: EdgeInsets.only(bottom: rs.height(10)),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(rs.scale(12)),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: rs.scale(6),
            offset: Offset(0, rs.scale(2)),
          ),
        ],
      ),
      child: ListTile(
        dense: true,
        contentPadding: rs.insetsSymmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: rs.scale(40),
          height: rs.scale(40),
          decoration: BoxDecoration(
            color: subject.color,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              subject.acronym ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        title: Text(
          subject.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: (timeText.isNotEmpty || (isLockedByManualOverride && overrideDate != null))
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (timeText.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: rs.height(2)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: rs.scale(12),
                            color: theme.textTheme.bodySmall?.color,
                          ),
                          SizedBox(width: rs.width(4)),
                          Text(
                            timeText,
                            style: TextStyle(
                              fontSize: rs.font(11),
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isLockedByManualOverride && overrideDate != null)
                    Padding(
                      padding: EdgeInsets.only(top: rs.height(2)),
                      child: Text(
                        'Locked before ${_formatShortDate(overrideDate)}',
                        style: TextStyle(
                          fontSize: rs.font(11),
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              )
            : null,
        trailing: isFutureClass
            ? Container(
                padding: rs.insetsSymmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(rs.scale(20)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, size: rs.scale(14), color: Colors.white),
                    SizedBox(width: rs.width(4)),
                    Text(
                      'Pending',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: rs.font(12),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            : isLockedByManualOverride
                ? _buildLockedStatusButton()
                : _buildAttendanceStatusButton(
                    status,
                    () async {
                      final newStatus = _getNextStatus(status);
                      if (newStatus == null) {
                        await attendanceProvider.deleteRecordForSubjectOnDate(
                          subject.id,
                          date,
                          slotKey: slotKey,
                        );
                      } else {
                        await attendanceProvider.markAttendance(
                          subject.id,
                          date,
                          newStatus,
                          slotKey: slotKey,
                        );
                      }
                      setState(() {});
                    },
                  ),
      ),
    );
  }

  Widget _buildLockedStatusButton() {
    final rs = context.rs;
    return Container(
      padding: rs.insetsSymmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey,
        borderRadius: BorderRadius.circular(rs.scale(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: rs.scale(14), color: Colors.white),
          SizedBox(width: rs.width(4)),
          Text(
            'Locked',
            style: TextStyle(
              color: Colors.white,
              fontSize: rs.font(12),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceStatusButton(AttendanceStatus? status, VoidCallback onTap) {
    final rs = context.rs;
    Color bgColor;
    String label;
    IconData icon;

    if (status == null) {
      bgColor = const Color(0xFFFFA726);
      label = 'Mark';
      icon = Icons.help_outline_rounded;
    } else if (status == AttendanceStatus.attended) {
      bgColor = const Color(0xFF4CAF50);
      label = 'Present';
      icon = Icons.check_circle_outline_rounded;
    } else if (status == AttendanceStatus.absent) {
      bgColor = const Color(0xFFEF5350);
      label = 'Absent';
      icon = Icons.highlight_off_rounded;
    } else {
      bgColor = const Color(0xFFAB47BC);
      label = 'Holiday';
      icon = Icons.celebration_rounded;
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.vibrate();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: rs.insetsSymmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(rs.scale(20)),
          boxShadow: [
            BoxShadow(
              color: bgColor.withValues(alpha: 0.3),
              blurRadius: rs.scale(4),
              offset: Offset(0, rs.scale(2)),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: rs.scale(14), color: Colors.white),
            SizedBox(width: rs.width(4)),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: rs.font(12),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  AttendanceStatus? _getNextStatus(AttendanceStatus? currentStatus) {
    if (currentStatus == null) {
      return AttendanceStatus.attended;
    } else if (currentStatus == AttendanceStatus.attended) {
      return AttendanceStatus.absent;
    } else if (currentStatus == AttendanceStatus.absent) {
      return AttendanceStatus.cancelled;
    } else {
      return null;
    }
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  bool _isLockedByManualOverride(Subject subject, DateTime date) {
    final manualOverride = subject.manualAttendanceOverride;
    if (manualOverride == null) {
      return false;
    }

    final normalizedDate = DateTime(date.year, date.month, date.day);
    final effectiveFrom = manualOverride.effectiveFrom;
    final normalizedEffectiveFrom =
        DateTime(effectiveFrom.year, effectiveFrom.month, effectiveFrom.day);

    return normalizedDate.isBefore(normalizedEffectiveFrom);
  }

  String _formatShortDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Color _darkenColor(Color color) {
    final hslColor = HSLColor.fromColor(color);
    final darkerHsl = hslColor.withLightness((hslColor.lightness - 0.15).clamp(0.0, 1.0));
    return darkerHsl.toColor();
  }
}
