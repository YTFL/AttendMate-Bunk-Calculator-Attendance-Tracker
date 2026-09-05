import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_utils.dart';
import '../../utils/responsive_scale.dart';
import '../semester/semester_model.dart';
import '../semester/semester_provider.dart';
import '../settings/time_format_provider.dart';
import '../settings/swipe_action_provider.dart';
import '../settings/swipeable_card.dart';
import '../subject/subject_provider.dart';
import '../subject/subject_model.dart';
import '../attendance/attendance_model.dart';
import '../calendar/calendar_utils.dart';
import '../location/location_model.dart';
import '../../services/database_service.dart';

typedef DayChangedCallback = void Function(String title, bool canGoPrevious, bool canGoNext);

class TodaySchedule extends StatefulWidget {
  final ValueChanged<String>? onTitleChanged;
  final DayChangedCallback? onDayChanged;

  const TodaySchedule({super.key, this.onTitleChanged, this.onDayChanged});

  @override
  State<TodaySchedule> createState() => TodayScheduleState();
}

class TodayScheduleState extends State<TodaySchedule> {
  late DateTime _today;
  List<DateTime> _dates = [];
  int _currentIndex = 0;
  int _todayIndex = 0;
  late PageController _pageController;
  Map<String, LocationConfig> _locationById = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);

    final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
    _buildDatesList(semesterProvider.semester);

    _pageController = PageController(initialPage: _todayIndex);
    _currentIndex = _todayIndex;

    _loadLocations();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _notifyDayChanged();
      }
    });
  }

  Future<void> _loadLocations() async {
    try {
      final locs = await DatabaseService().loadLocations();
      if (mounted) {
        setState(() {
          _locationById = {for (final l in locs) l.id: l};
        });
      }
    } catch (_) {
      // Location display is non-critical — silently ignore
    }
  }


  @override
  void didUpdateWidget(covariant TodaySchedule oldWidget) {
    super.didUpdateWidget(oldWidget);
    final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
    _buildDatesList(semesterProvider.semester);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _buildDatesList(Semester? semester) {
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);

    final minDate = _today.subtract(const Duration(days: 7));
    final maxDate = _today.add(const Duration(days: 7));

    DateTime effectiveStart = minDate;
    DateTime effectiveEnd = maxDate;

    if (semester != null) {
      final semStart = DateTime(semester.startDate.year, semester.startDate.month, semester.startDate.day);
      final semEnd = DateTime(semester.endDate.year, semester.endDate.month, semester.endDate.day);
      if (semStart.isAfter(effectiveStart)) {
        effectiveStart = semStart;
      }
      if (semEnd.isBefore(effectiveEnd)) {
        effectiveEnd = semEnd;
      }
    }

    final list = <DateTime>[];
    var cur = effectiveStart;
    while (!cur.isAfter(effectiveEnd)) {
      list.add(cur);
      cur = cur.add(const Duration(days: 1));
    }

    if (list.isEmpty) {
      list.add(_today);
    }

    _dates = list;
    final foundToday = _dates.indexWhere((d) => CalendarUtils.isSameDay(d, _today));
    _todayIndex = foundToday >= 0 ? foundToday : 0;
    if (_currentIndex >= _dates.length) {
      _currentIndex = _todayIndex;
    }
  }

  String _getScheduleTitle(DateTime date) {
    final dNorm = DateTime(date.year, date.month, date.day);
    final tNorm = DateTime(_today.year, _today.month, _today.day);
    final dayDiff = dNorm.difference(tNorm).inDays;

    if (dayDiff == 0) {
      return "Today";
    } else if (dayDiff == -1) {
      return "Yesterday";
    } else if (dayDiff == 1) {
      return "Tomorrow";
    } else {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final weekday = weekdays[date.weekday - 1];
      final month = months[date.month - 1];
      return '$weekday, ${date.day} $month';
    }
  }

  void _notifyDayChanged() {
    if (_dates.isNotEmpty && _currentIndex < _dates.length) {
      final title = _getScheduleTitle(_dates[_currentIndex]);
      widget.onTitleChanged?.call(title);
      widget.onDayChanged?.call(title, canGoPrevious, canGoNext);
    }
  }

  bool get canGoPrevious => _currentIndex > 0;
  bool get canGoNext => _currentIndex < _dates.length - 1;

  void goToPreviousDay() {
    if (canGoPrevious && _pageController.hasClients) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void goToNextDay() {
    if (canGoNext && _pageController.hasClients) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void jumpToToday() {
    if (_pageController.hasClients && _currentIndex != _todayIndex) {
      _pageController.animateToPage(
        _todayIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  List<Subject> _expandSubjectsBySlot(List<Subject> subjects) {
    final expandedSubjects = <Subject>[];
    for (final subject in subjects) {
      for (final slot in subject.schedule) {
        expandedSubjects.add(subject.copyWith(schedule: [slot]));
      }
    }
    return expandedSubjects;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  void _showConfirmationDialog({
    required BuildContext context,
    required String title,
    required String content,
    required VoidCallback onConfirm,
    String? successMessage,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              HapticFeedback.vibrate();
              onConfirm();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showReplacingSnackBar(
                SnackBar(content: Text(successMessage ?? '$title action completed.')),
              );
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeBackground({
    required SwipeAction action,
    required Alignment alignment,
    required ResponsiveScale rs,
    required bool isUnmarking,
  }) {
    final Color color;
    final IconData icon;

    if (isUnmarking) {
      color = Colors.grey.shade600;
      icon = Icons.undo;
    } else {
      switch (action) {
        case SwipeAction.present:
          color = Colors.green.shade700;
          icon = Icons.check;
          break;
        case SwipeAction.absent:
          color = Colors.red.shade700;
          icon = Icons.close;
          break;
      }
    }

    return Container(
      margin: rs.insetsSymmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(rs.scale(12)),
      ),
      padding: EdgeInsets.symmetric(horizontal: rs.width(20)),
      alignment: alignment,
      child: Icon(icon, color: Colors.white, size: rs.scale(24)),
    );
  }

  Future<void> _handleSwipeAction({
    required BuildContext context,
    required SwipeAction action,
    required bool isUnmarking,
    required Subject subject,
    required String? slotKey,
    required DateTime targetDate,
    required SubjectProvider subjectProvider,
  }) async {
    if (CalendarUtils.isLockedByManualOverride(subject, targetDate)) {
      return;
    }
    HapticFeedback.vibrate();
    final String message;
    if (isUnmarking) {
      await subjectProvider.unmarkAttendance(
        subject.id,
        targetDate,
        slotKey: slotKey,
      );
      message = 'Attendance unmarked for ${subject.acronym ?? subject.name}';
    } else {
      switch (action) {
        case SwipeAction.present:
          await subjectProvider.markAttendance(
            subject.id,
            targetDate,
            AttendanceStatus.attended,
            slotKey: slotKey,
          );
          message = '${subject.acronym ?? subject.name} marked as Present';
          break;
        case SwipeAction.absent:
          await subjectProvider.markAttendance(
            subject.id,
            targetDate,
            AttendanceStatus.absent,
            slotKey: slotKey,
          );
          message = '${subject.acronym ?? subject.name} marked as Absent';
          break;
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final rs = context.rs;

    // Check if the semester has started yet
    final semester = semesterProvider.semester;
    if (semester != null && !semesterProvider.hasSemesterStarted) {
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
                'Your semester will start on $formattedDate. Today\'s schedule will be available from that date.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: rs.font(16)),
              ),
            ],
          ),
        ),
      );
    }

    // Check if the semester has ended
    if (semester != null && semesterProvider.hasSemesterEnded) {
      return Center(
        child: Padding(
          padding: rs.insetsAll(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.school_outlined, size: rs.scale(50), color: Colors.orange),
              SizedBox(height: rs.height(16)),
              Text(
                'Semester Ended',
                style: TextStyle(fontSize: rs.font(22), fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: rs.height(8)),
              Text(
                'The semester has ended.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: rs.font(16)),
              ),
            ],
          ),
        ),
      );
    }

    if (_dates.isEmpty) {
      _buildDatesList(semester);
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _dates.length,
      onPageChanged: (index) {
        setState(() {
          _currentIndex = index;
        });
        _notifyDayChanged();
      },
      itemBuilder: (context, index) {
        final date = _dates[index];
        return _buildDaySchedule(date);
      },
    );
  }

  Widget _buildDaySchedule(DateTime targetDate) {
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);
    final swipeProvider = Provider.of<SwipeActionProvider>(context);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final rs = context.rs;

    final bool semesterEnded = semesterProvider.hasSemesterEnded;
    final bool isFutureDate = targetDate.isAfter(_today);
    final bool isToday = CalendarUtils.isSameDay(targetDate, _today);

    final displayClasses = _expandSubjectsBySlot(subjectProvider.getClassesForDate(targetDate));
    displayClasses.sort((a, b) {
      final aTime = a.schedule.first.startTime.hour * 60 + a.schedule.first.startTime.minute;
      final bTime = b.schedule.first.startTime.hour * 60 + b.schedule.first.startTime.minute;
      return aTime.compareTo(bTime);
    });

    final editableClasses = displayClasses
        .where((subject) => !CalendarUtils.isLockedByManualOverride(subject, targetDate))
        .toList();
    final lockedCount = displayClasses.length - editableClasses.length;
    final bool allLocked = displayClasses.isNotEmpty && lockedCount == displayClasses.length;

    return Column(
      children: [
        if (semesterEnded)
          Container(
            padding: rs.insetsSymmetric(horizontal: 16, vertical: 12),
            color: Colors.orange.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: rs.scale(20)),
                SizedBox(width: rs.width(8)),
                Expanded(
                  child: Text(
                    'Semester has ended. Attendance tracking is disabled.',
                    style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        if (!semesterEnded && !isFutureDate && allLocked)
          Container(
            margin: rs.insetsSymmetric(horizontal: 16, vertical: 8),
            padding: rs.insetsSymmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF607D8B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(rs.scale(10)),
              border: Border.all(
                color: const Color(0xFF607D8B).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: const Color(0xFF607D8B), size: rs.scale(20)),
                SizedBox(width: rs.width(10)),
                Expanded(
                  child: Text(
                    'Classes on this date are locked due to manual count update.',
                    style: TextStyle(
                      color: isDarkMode ? Colors.blueGrey.shade200 : Colors.blueGrey.shade800,
                      fontWeight: FontWeight.w500,
                      fontSize: rs.font(13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (!semesterEnded && !isFutureDate && !allLocked)
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
                  backgroundColor: theme.colorScheme.onSurface,
                  foregroundColor: theme.colorScheme.surface,
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
                  final button = ElevatedButton(
                    onPressed: onPressed,
                    style: buttonStyle,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!iconlessMode) ...[
                          Icon(icon, size: (rs.scale(14) * rowScale).clamp(12.0, 16.0)),
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
                  );

                  return SizedBox(width: (constraints.maxWidth - rs.width(12)) / 3, child: button);
                }

                return Row(
                  children: [
                    Expanded(
                      child: actionButton(
                        icon: Icons.celebration_outlined,
                        label: 'Holiday',
                        onPressed: () => _showConfirmationDialog(
                          context: context,
                          title: 'Mark as Holiday',
                          content: lockedCount > 0
                              ? 'Are you sure you want to mark ${editableClasses.length} class(es) as holiday? $lockedCount locked class(es) will remain unchanged.'
                              : (isToday
                                  ? 'Are you sure you want to mark today as a holiday? All classes will be cancelled and won\'t affect attendance criteria.'
                                  : 'Are you sure you want to mark this day as a holiday? All classes will be cancelled and won\'t affect attendance criteria.'),
                          onConfirm: () => subjectProvider.markDayAsHoliday(targetDate),
                          successMessage: lockedCount > 0
                              ? 'Marked ${editableClasses.length} class(es) as holiday. $lockedCount locked.'
                              : 'Holiday action completed.',
                        ),
                      ),
                    ),
                    SizedBox(width: rs.width(6)),
                    Expanded(
                      child: actionButton(
                        icon: Icons.fast_forward_outlined,
                        label: 'Skip Day',
                        onPressed: () => _showConfirmationDialog(
                          context: context,
                          title: isToday ? 'Skip Today' : 'Skip Day',
                          content: lockedCount > 0
                              ? 'Are you sure you want to skip ${editableClasses.length} class(es)? $lockedCount locked class(es) will remain unchanged.'
                              : (isToday
                                  ? 'Are you sure you want to skip all classes today? This will mark all scheduled classes as absent.'
                                  : 'Are you sure you want to skip all classes on this day? This will mark all scheduled classes as absent.'),
                          onConfirm: () => subjectProvider.markDayAsAbsent(targetDate),
                          successMessage: lockedCount > 0
                              ? 'Marked ${editableClasses.length} class(es) as absent. $lockedCount locked.'
                              : 'Skip Day action completed.',
                        ),
                      ),
                    ),
                    SizedBox(width: rs.width(6)),
                    Expanded(
                      child: actionButton(
                        icon: Icons.check_circle_outline,
                        label: 'Present',
                        onPressed: () => _showConfirmationDialog(
                          context: context,
                          title: isToday ? 'Mark as Present' : 'Mark Day as Present',
                          content: lockedCount > 0
                              ? 'Are you sure you want to mark ${editableClasses.length} class(es) as present? $lockedCount locked class(es) will remain unchanged.'
                              : (isToday
                                  ? 'Are you sure you want to mark today as present? All classes will be marked as attended.'
                                  : 'Are you sure you want to mark all classes on this day as attended?'),
                          onConfirm: () => subjectProvider.markDayAsPresent(targetDate),
                          successMessage: lockedCount > 0
                              ? 'Marked ${editableClasses.length} class(es) as present. $lockedCount locked.'
                              : 'Mark as Present action completed.',
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        if (!semesterEnded && isFutureDate && displayClasses.isNotEmpty && !allLocked)
          Padding(
            padding: rs.insetsSymmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(0, rs.height(44)),
                  backgroundColor: theme.colorScheme.onSurface,
                  foregroundColor: theme.colorScheme.surface,
                ),
                icon: const Icon(Icons.celebration_outlined),
                label: const Text('Mark as Holiday', style: TextStyle(fontWeight: FontWeight.w600)),
                onPressed: () => _showConfirmationDialog(
                  context: context,
                  title: 'Mark as Holiday',
                  content: lockedCount > 0
                      ? 'Are you sure you want to mark ${editableClasses.length} upcoming class(es) as a holiday? $lockedCount locked class(es) will remain unchanged.'
                      : 'Are you sure you want to mark this upcoming day as a holiday? All classes will be cancelled.',
                  onConfirm: () => subjectProvider.markDayAsHoliday(targetDate),
                  successMessage: lockedCount > 0
                      ? 'Marked ${editableClasses.length} class(es) as holiday. $lockedCount locked.'
                      : 'Day marked as holiday.',
                ),
              ),
            ),
          ),
        if (displayClasses.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: rs.insetsAll(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: rs.scale(60), color: Colors.grey),
                    SizedBox(height: rs.height(16)),
                    Text(
                      isToday ? 'No Classes Today' : 'No Classes Scheduled',
                      style: TextStyle(fontSize: rs.font(20), fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: rs.height(8)),
                    Text(
                      'There are no classes scheduled for this day of the week.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: rs.insetsAll(8),
              itemCount: displayClasses.length,
              itemBuilder: (context, index) {
                final subject = displayClasses[index];
                final timeSlot = subject.schedule.first;
                final slotKey = timeSlot.slotKey;
                final isLocked = CalendarUtils.isLockedByManualOverride(subject, targetDate);
                final overrideDate = subject.manualAttendanceOverride?.effectiveFrom;
                final attendance = subjectProvider.getAttendanceForSubjectOnDate(
                  subject.id,
                  targetDate,
                  slotKey: slotKey,
                );

                String statusText;
                Color statusColor;
                IconData statusIcon;

                // Determine if we should show action buttons based on status
                final showActions = !semesterEnded && !isLocked;
                Widget? trailingWidget;

                if (isLocked) {
                  statusText = 'Locked';
                  statusColor = const Color(0xFF607D8B);
                  statusIcon = Icons.lock_outline;
                } else if (attendance?.status == AttendanceStatus.attended) {
                  statusText = 'Attended';
                  statusColor = Colors.green.shade700;
                  statusIcon = Icons.check_circle_outline;
                } else if (attendance?.status == AttendanceStatus.absent) {
                  statusText = 'Absent';
                  statusColor = Colors.red.shade700;
                  statusIcon = Icons.cancel_outlined;
                } else if (attendance?.status == AttendanceStatus.cancelled) {
                  statusText = 'Holiday';
                  statusColor = Colors.grey.shade600;
                  statusIcon = Icons.celebration_outlined;
                } else if (isFutureDate) {
                  statusText = 'Upcoming';
                  statusColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
                  statusIcon = Icons.schedule;
                } else {
                  statusText = 'Awaiting Status';
                  statusColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
                  statusIcon = Icons.hourglass_empty;
                }

                // Show a single button to toggle Holiday / Unmark Attendance
                if (showActions) {
                  if (attendance != null) {
                    trailingWidget = IconButton(
                      icon: const Icon(Icons.cancel_outlined),
                      tooltip: 'Unmark Attendance',
                      color: Colors.grey,
                      onPressed: () {
                        HapticFeedback.vibrate();
                        subjectProvider.unmarkAttendance(
                          subject.id,
                          targetDate,
                          slotKey: slotKey,
                        );
                      },
                    );
                  } else {
                    trailingWidget = IconButton(
                      icon: const Icon(Icons.celebration_outlined),
                      tooltip: 'Mark Holiday',
                      color: Colors.purple,
                      onPressed: () {
                        HapticFeedback.vibrate();
                        subjectProvider.markAttendance(
                          subject.id,
                          targetDate,
                          AttendanceStatus.cancelled,
                          slotKey: slotKey,
                        );
                      },
                    );
                  }
                }

                final cardWidget = Card(
                  elevation: 2.0,
                  margin: rs.insetsSymmetric(horizontal: 8, vertical: 6),
                  shadowColor: isDarkMode ? null : Colors.black.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(rs.scale(12)),
                    side: BorderSide(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.4)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: rs.insetsAll(8),
                    child: Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: rs.insetsSymmetric(horizontal: 8, vertical: 2),
                        leading: CircleAvatar(
                          radius: rs.scale(20.6),
                          backgroundColor: subject.color,
                          child: Center(
                            child: Text(
                              subject.acronym ?? '',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              softWrap: true,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: rs.font(11),
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          subject.name,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: rs.font(15)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(() {
                              final effectiveLocId = subject.getEffectiveLocationId(timeSlot);
                              final locConfig = effectiveLocId != null ? _locationById[effectiveLocId] : null;
                              // Prefer slot/subject plain-text room; fall back to LocationConfig name
                              final room = subject.getEffectiveRoom(timeSlot) ?? locConfig?.name;
                              final block = subject.getEffectiveBlock(timeSlot) ?? locConfig?.block;
                              final roomStr = room != null
                                  ? ' • $room${block != null && block.isNotEmpty ? " ($block)" : ""}'
                                  : '';
                              return timeSlot.formatTimeRange(timeFormatProvider.timeFormat) + roomStr;
                            }()),
                            if (isLocked && overrideDate != null)
                              Padding(
                                padding: EdgeInsets.only(top: rs.height(2)),
                                child: Text(
                                  'Locked before ${_formatDate(overrideDate)}',
                                  style: TextStyle(
                                    fontSize: rs.font(11),
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            SizedBox(height: rs.height(4)),
                            Row(
                              children: [
                                Icon(statusIcon, size: rs.scale(16), color: statusColor),
                                SizedBox(width: rs.width(4)),
                                Flexible(
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontStyle: isLocked ? FontStyle.normal : FontStyle.italic,
                                      fontWeight: isLocked ? FontWeight.w600 : FontWeight.normal,
                                      fontSize: rs.font(13),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: trailingWidget,
                      ),
                    ),
                  ),
                );

                if (semesterEnded || isFutureDate || isLocked) {
                  return cardWidget;
                }

                final isUnmarkingRight = (attendance?.status == AttendanceStatus.attended &&
                        swipeProvider.rightAction == SwipeAction.present) ||
                    (attendance?.status == AttendanceStatus.absent &&
                        swipeProvider.rightAction == SwipeAction.absent);

                final isUnmarkingLeft = (attendance?.status == AttendanceStatus.attended &&
                        swipeProvider.leftAction == SwipeAction.present) ||
                    (attendance?.status == AttendanceStatus.absent &&
                        swipeProvider.leftAction == SwipeAction.absent);

                return SwipeableCard(
                  key: ValueKey('${subject.id}_${slotKey}_${targetDate.millisecondsSinceEpoch}'),
                  swipeRightBackground: _buildSwipeBackground(
                    action: swipeProvider.rightAction,
                    alignment: Alignment.centerLeft,
                    rs: rs,
                    isUnmarking: isUnmarkingRight,
                  ),
                  swipeLeftBackground: _buildSwipeBackground(
                    action: swipeProvider.leftAction,
                    alignment: Alignment.centerRight,
                    rs: rs,
                    isUnmarking: isUnmarkingLeft,
                  ),
                  onSwipeRight: () => _handleSwipeAction(
                    context: context,
                    action: swipeProvider.rightAction,
                    isUnmarking: isUnmarkingRight,
                    subject: subject,
                    slotKey: slotKey,
                    targetDate: targetDate,
                    subjectProvider: subjectProvider,
                  ),
                  onSwipeLeft: () => _handleSwipeAction(
                    context: context,
                    action: swipeProvider.leftAction,
                    isUnmarking: isUnmarkingLeft,
                    subject: subject,
                    slotKey: slotKey,
                    targetDate: targetDate,
                    subjectProvider: subjectProvider,
                  ),
                  rs: rs,
                  child: cardWidget,
                );
              },
            ),
          ),
      ],
    );
  }
}
