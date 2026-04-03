import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/attendance/attendance_model.dart';
import '../../features/attendance/attendance_provider.dart';
import '../../features/semester/semester_provider.dart';
import '../../features/settings/time_format_provider.dart';
import '../../features/subject/subject_model.dart';
import '../../features/subject/subject_provider.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import 'calendar_utils.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _selectedMonth;
  DateTime? _pressedDate;
  PageController? _monthPageController;
  List<DateTime> _monthPages = [];

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime.now();
  }

  @override
  void dispose() {
    _monthPageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final attendanceProvider = Provider.of<AttendanceProvider>(context);

    if (semesterProvider.semester == null) {
      return const Scaffold(
        body: Center(child: Text('Semester not set')),
      );
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Calendar'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Month/Year Selector
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _isSameMonthYear(_selectedMonth, startDate)
                      ? null
                      : () => _goToPreviousMonth(startDate),
                ),
                Text(
                  '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _isSameMonthYear(_selectedMonth, endDate)
                      ? null
                      : () => _goToNextMonth(endDate),
                ),
              ],
            ),
          ),
          // Legend
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: _buildLegend(),
          ),
          const SizedBox(height: 8),
          // Calendar Grid
          Expanded(
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
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
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
        ],
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

  Widget _buildLegend() {
    final rs = context.rs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Legend:', style: TextStyle(fontWeight: FontWeight.bold)),
        SizedBox(height: rs.height(8)),
        Wrap(
          spacing: rs.width(12),
          runSpacing: rs.height(8),
          children: [
            _buildLegendItem(
              DayState.attendedFullDay,
              'Attended Full Day',
            ),
            _buildLegendItem(
              DayState.bunkedFullDay,
              'Bunked Full Day',
            ),
            _buildLegendItem(
              DayState.classesNotMarked,
              'Not Marked',
            ),
            _buildLegendItem(
              DayState.classesMarked,
              'Mixed',
            ),
            _buildLegendItem(
              DayState.holiday,
              'Holiday',
            ),
            _buildLegendItem(
              DayState.futureClasses,
              'Upcoming',
            ),
            _buildLegendItem(
              DayState.noClasses,
              'No Classes',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(DayState state, String label) {
    final rs = context.rs;
    return Tooltip(
      message: CalendarUtils.getStateLabel(state),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: rs.scale(24),
            height: rs.scale(24),
            decoration: BoxDecoration(
              color: CalendarUtils.getStateColor(state),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CalendarUtils.getStateIcon(state),
              size: rs.scale(14),
              color: Colors.white,
            ),
          ),
          SizedBox(width: rs.width(6)),
          Text(label, style: TextStyle(fontSize: rs.font(12))),
        ],
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
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final lastDayOfMonth =
        DateTime(month.year, month.month + 1, 0);

    // Adjust if before semester start or after semester end
    final displayStartDate = firstDayOfMonth.isBefore(startDate)
        ? startDate
        : firstDayOfMonth;
    final displayEndDate =
        lastDayOfMonth.isAfter(endDate) ? endDate : lastDayOfMonth;

    final int daysInMonth = displayEndDate.difference(displayStartDate).inDays + 1;
    final int firstWeekday = displayStartDate.weekday;

    return Column(
      children: [
        // Day headers
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
              .map((day) => Expanded(
                    child: Text(
                      day,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ))
              .toList(),
        ),
        SizedBox(height: rs.height(12)),
        // Calendar grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: rs.height(10),
            crossAxisSpacing: rs.width(10),
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
            );

            return _buildDayCell(context, dayInfo);
          },
        ),
      ],
    );
  }

  Widget _buildDayCell(BuildContext context, CalendarDayInfo dayInfo) {
    final rs = context.rs;
    final isPressed = _pressedDate != null && 
        _pressedDate!.year == dayInfo.date.year &&
        _pressedDate!.month == dayInfo.date.month &&
        _pressedDate!.day == dayInfo.date.day;
    
    final baseColor = CalendarUtils.getStateColor(dayInfo.state);
    final displayColor = isPressed ? _darkenColor(baseColor) : baseColor;

    return GestureDetector(
      onTapDown: (_) {
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
      child: Container(
        decoration: BoxDecoration(
          color: displayColor,
          borderRadius: BorderRadius.circular(rs.scale(8)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dayInfo.date.day.toString(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: rs.font(12),
              ),
            ),
            SizedBox(height: rs.height(2)),
            Icon(
              CalendarUtils.getStateIcon(dayInfo.state),
              size: rs.scale(16),
              color: Colors.white,
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
          height: MediaQuery.of(context).size.height * 0.95,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: rs.width(16),
            right: rs.width(16),
            top: rs.height(16),
          ),
          child: PageView.builder(
            controller: dayPageController,
            itemCount: swipableDates.length,
            itemBuilder: (context, pageIndex) {
              final pageDate = swipableDates[pageIndex];
              final pageDayInfo = CalendarUtils.getDayState(
                date: pageDate,
                subjects: subjectProvider.subjects,
                attendanceRecords: attendanceProvider.attendanceRecords,
              );
              final classesForDay = _expandSubjectsBySlotForDay(
                pageDayInfo.subjectsWithClassesToday,
                pageDate,
              );
              final dateFormatter = _formatDate(pageDate);

              return Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateFormatter,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          SizedBox(height: rs.height(4)),
                          Text(
                            CalendarUtils.getStateLabel(pageDayInfo.state),
                            style: TextStyle(
                              color: CalendarUtils.getStateColor(pageDayInfo.state),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  if (pageDayInfo.classesCount > 0 &&
                      pageDayInfo.state != DayState.futureClasses)
                    Padding(
                      padding: rs.insetsSymmetric(horizontal: 16, vertical: 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final rowScale = (constraints.maxWidth / 360).clamp(0.72, 1.0);
                          final compactMode = constraints.maxWidth < 370;
                          final iconlessMode = constraints.maxWidth < 335;
                          final buttonStyle = ElevatedButton.styleFrom(
                            minimumSize: Size(0, rs.height(44)),
                            padding: EdgeInsets.symmetric(
                              vertical: rs.height(9),
                              horizontal: rs.width(compactMode ? 4 : 6),
                            ),
                            visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
                            backgroundColor: Theme.of(context).colorScheme.onSurface,
                            foregroundColor: Theme.of(context).colorScheme.surface,
                          );

                          String adaptiveLabel(String label) {
                            if (!compactMode) return label;
                            if (label == 'Skip Day') return 'Skip';
                            return label;
                          }

                          Widget actionButton({
                            required IconData icon,
                            required String label,
                            required VoidCallback onPressed,
                          }) {
                            final buttonLabel = adaptiveLabel(label);
                            final fontSize = (rs.font(12) * rowScale).clamp(11.0, 13.0);
                            return SizedBox(
                              width: (constraints.maxWidth - rs.width(12)) / 3,
                              child: ElevatedButton(
                                onPressed: onPressed,
                                style: buttonStyle,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!iconlessMode) ...[
                                      Icon(icon, size: (rs.scale(16) * rowScale).clamp(13.0, 18.0)),
                                      SizedBox(width: rs.width(4)),
                                    ],
                                    Flexible(
                                      child: Text(
                                        buttonLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.fade,
                                        softWrap: false,
                                        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return Row(
                            children: [
                              Expanded(
                                child: actionButton(
                                  icon: Icons.check_circle_outline,
                                  label: 'Present',
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
                              ),
                              SizedBox(width: rs.width(6)),
                              Expanded(
                                child: actionButton(
                                  icon: Icons.fast_forward_outlined,
                                  label: 'Skip Day',
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
                              ),
                              SizedBox(width: rs.width(6)),
                              Expanded(
                                child: actionButton(
                                  icon: Icons.celebration_outlined,
                                  label: 'Holiday',
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
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  if (pageDayInfo.state != DayState.futureClasses)
                    Padding(
                      padding: rs.insetsSymmetric(horizontal: 16, vertical: 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
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
                          icon: const Icon(Icons.copy_all_outlined),
                          label: const Text('Copy Timetable To This Day'),
                        ),
                      ),
                    ),
                  SizedBox(height: rs.height(8)),
                  if (pageDayInfo.classesCount == 0)
                    Expanded(
                      child: Center(
                        child: Text(
                          pageDayInfo.state == DayState.holiday
                              ? 'Marked as Holiday'
                              : 'No classes scheduled',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
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
        );
      },
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
      final info = CalendarUtils.getDayState(
        date: date,
        subjects: subjects,
        attendanceRecords: attendanceRecords,
      );

      if (info.classesCount > 0) {
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
    final status = attendance?.status;
    final isFutureClass = dayState == DayState.futureClasses;
    final isLockedByManualOverride = _isLockedByManualOverride(subject, date);
    final overrideDate = subject.manualAttendanceOverride?.effectiveFrom;
    final timeSlot = CalendarUtils.getTimeSlotForDate(subject, date);
    final timeText = timeSlot != null
        ? '${timeSlot.startTime.hour.toString().padLeft(2, '0')}:${timeSlot.startTime.minute.toString().padLeft(2, '0')} - ${timeSlot.endTime.hour.toString().padLeft(2, '0')}:${timeSlot.endTime.minute.toString().padLeft(2, '0')}'
        : '';

    return Container(
      margin: EdgeInsets.only(bottom: rs.height(8)),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(rs.scale(8)),
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
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subject.name),
            if (timeText.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: rs.height(4)),
                child: Text(
                  timeText,
                  style: TextStyle(
                    fontSize: rs.font(11),
                    color: Colors.grey[600],
                  ),
                ),
              ),
            if (isLockedByManualOverride && overrideDate != null)
              Padding(
                padding: EdgeInsets.only(top: rs.height(4)),
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
        ),
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
                    Icon(Icons.schedule, size: rs.scale(16), color: Colors.white),
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
          Icon(Icons.lock_outline, size: rs.scale(16), color: Colors.white),
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
      bgColor = Colors.orange[300]!;
      label = 'Mark';
      icon = Icons.help_outline;
    } else if (status == AttendanceStatus.attended) {
      bgColor = Colors.green[400]!;
      label = 'Present';
      icon = Icons.done;
    } else if (status == AttendanceStatus.absent) {
      bgColor = Colors.red[400]!;
      label = 'Absent';
      icon = Icons.close;
    } else {
      bgColor = Colors.purple[300]!;
      label = 'Holiday';
      icon = Icons.celebration;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: rs.insetsSymmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(rs.scale(20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: rs.scale(16), color: Colors.white),
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
      return null; // Reset to not marked
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
