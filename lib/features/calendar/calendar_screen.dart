import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/attendance/attendance_model.dart';
import '../../features/attendance/attendance_provider.dart';
import '../../features/semester/semester_provider.dart';
import '../../features/settings/time_format_provider.dart';
import '../../features/subject/subject_model.dart';
import '../../features/subject/subject_provider.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Legend:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
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
    return Tooltip(
      message: CalendarUtils.getStateLabel(state),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: CalendarUtils.getStateColor(state),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CalendarUtils.getStateIcon(state),
              size: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
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
        const SizedBox(height: 12),
        // Calendar grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 12,
            crossAxisSpacing: 14,
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
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dayInfo.date.day.toString(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Icon(
              CalendarUtils.getStateIcon(dayInfo.state),
              size: 16,
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

  Widget _buildDayDetailsModal(
    BuildContext context,
    CalendarDayInfo dayInfo,
    SubjectProvider subjectProvider,
    AttendanceProvider attendanceProvider,
    DateTime startDate,
    DateTime endDate,
  ) {
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
            left: 16,
            right: 16,
            top: 16,
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
                          const SizedBox(height: 4),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.check_circle_outline, size: 18),
                              label: const Text('Present', style: TextStyle(fontSize: 13)),
                              onPressed: () {
                                final subjectProvider =
                                    Provider.of<SubjectProvider>(context, listen: false);
                                for (var subject in classesForDay) {
                                  subjectProvider.markAttendance(
                                    subject.id,
                                    pageDate,
                                    AttendanceStatus.attended,
                                    slotKey: subject.schedule.first.slotKey,
                                  );
                                }
                                ScaffoldMessenger.of(context).showReplacingSnackBar(
                                  const SnackBar(content: Text('All classes marked as present')),
                                );
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 13),
                                backgroundColor: Theme.of(context).colorScheme.onSurface,
                                foregroundColor: Theme.of(context).colorScheme.surface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.fast_forward_outlined, size: 18),
                              label: const Text('Skip Day', style: TextStyle(fontSize: 13)),
                              onPressed: () {
                                final subjectProvider =
                                    Provider.of<SubjectProvider>(context, listen: false);
                                for (var subject in classesForDay) {
                                  subjectProvider.markAttendance(
                                    subject.id,
                                    pageDate,
                                    AttendanceStatus.absent,
                                    slotKey: subject.schedule.first.slotKey,
                                  );
                                }
                                ScaffoldMessenger.of(context).showReplacingSnackBar(
                                  const SnackBar(content: Text('All classes marked as absent')),
                                );
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 13),
                                backgroundColor: Theme.of(context).colorScheme.onSurface,
                                foregroundColor: Theme.of(context).colorScheme.surface,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.celebration_outlined, size: 18),
                              label: const Text('Holiday', style: TextStyle(fontSize: 13)),
                              onPressed: () {
                                final subjectProvider =
                                    Provider.of<SubjectProvider>(context, listen: false);
                                subjectProvider.markDayAsHoliday(pageDate);
                                ScaffoldMessenger.of(context).showReplacingSnackBar(
                                  const SnackBar(content: Text('Day marked as holiday')),
                                );
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 13),
                                backgroundColor: Theme.of(context).colorScheme.onSurface,
                                foregroundColor: Theme.of(context).colorScheme.surface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 16),
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
    final dayOfWeek = DayOfWeek.values[date.weekday - 1];
    final expandedSubjects = <Subject>[];

    for (final subject in subjects) {
      final slotsForDay = subject.schedule.where((slot) => slot.day == dayOfWeek);
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
    final status = attendance?.status;
    final isFutureClass = dayState == DayState.futureClasses;
    final timeSlot = CalendarUtils.getTimeSlotForDate(subject, date);
    final timeText = timeSlot != null
        ? '${timeSlot.startTime.hour.toString().padLeft(2, '0')}:${timeSlot.startTime.minute.toString().padLeft(2, '0')} - ${timeSlot.endTime.hour.toString().padLeft(2, '0')}:${timeSlot.endTime.minute.toString().padLeft(2, '0')}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
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
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  timeText,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ),
          ],
        ),
        trailing: isFutureClass
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, size: 16, color: Colors.white),
                    const SizedBox(width: 4),
                    const Text(
                      'Pending',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
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

  Widget _buildAttendanceStatusButton(AttendanceStatus? status, VoidCallback onTap) {
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
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

  Color _darkenColor(Color color) {
    final hslColor = HSLColor.fromColor(color);
    final darkerHsl = hslColor.withLightness((hslColor.lightness - 0.15).clamp(0.0, 1.0));
    return darkerHsl.toColor();
  }
}
