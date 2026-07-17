import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_utils.dart';
import '../../utils/responsive_scale.dart';
import '../semester/semester_provider.dart';
import '../settings/time_format_provider.dart';
import '../settings/swipe_action_provider.dart';
import '../settings/swipeable_card.dart';
import '../subject/subject_provider.dart';
import '../subject/subject_model.dart';
import '../attendance/attendance_model.dart';

class TodaySchedule extends StatelessWidget {
  const TodaySchedule({super.key});

  List<Subject> _expandSubjectsBySlot(List<Subject> subjects) {
    final expandedSubjects = <Subject>[];
    for (final subject in subjects) {
      for (final slot in subject.schedule) {
        expandedSubjects.add(subject.copyWith(schedule: [slot]));
      }
    }
    return expandedSubjects;
  }

  void _showConfirmationDialog({
    required BuildContext context,
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
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
              onConfirm();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showReplacingSnackBar(
                SnackBar(content: Text('$title action completed.')),
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
    required DateTime today,
    required SubjectProvider subjectProvider,
  }) async {
    final String message;
    if (isUnmarking) {
      await subjectProvider.unmarkAttendance(
        subject.id,
        today,
        slotKey: slotKey,
      );
      message = 'Attendance unmarked for ${subject.acronym ?? subject.name}';
    } else {
      switch (action) {
        case SwipeAction.present:
          await subjectProvider.markAttendance(
            subject.id,
            today,
            AttendanceStatus.attended,
            slotKey: slotKey,
          );
          message = '${subject.acronym ?? subject.name} marked as Present';
          break;
        case SwipeAction.absent:
          await subjectProvider.markAttendance(
            subject.id,
            today,
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);
    final swipeProvider = Provider.of<SwipeActionProvider>(context);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
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

    final bool semesterEnded = semesterProvider.hasSemesterEnded;

    final displayClasses = _expandSubjectsBySlot(subjectProvider.getClassesForDate(today));
    displayClasses.sort((a, b) {
      final aTime = a.schedule.first.startTime.hour * 60 + a.schedule.first.startTime.minute;
      final bTime = b.schedule.first.startTime.hour * 60 + b.schedule.first.startTime.minute;
      return aTime.compareTo(bTime);
    });

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
        if (!semesterEnded)
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
                          content: 'Are you sure you want to mark today as a holiday? All classes will be cancelled and won\'t affect attendance criteria.',
                          onConfirm: () => subjectProvider.markDayAsHoliday(today),
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
                          title: 'Skip Today',
                          content: 'Are you sure you want to skip all classes today? This will mark all scheduled classes as absent.',
                          onConfirm: () => subjectProvider.markDayAsAbsent(today),
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
                          title: 'Mark as Present',
                          content: 'Are you sure you want to mark today as present? All classes will be marked as attended.',
                          onConfirm: () => subjectProvider.markDayAsPresent(today),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
                      'No Classes Today',
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
                final attendance = subjectProvider.getAttendanceForSubjectOnDate(
                  subject.id,
                  today,
                  slotKey: slotKey,
                );

                String statusText;
                Color statusColor;
                IconData statusIcon;
                
                // Determine if we should show action buttons based on status
                final showActions = !semesterEnded;
                Widget? trailingWidget;

                switch (attendance?.status) {
                  case AttendanceStatus.attended:
                    statusText = 'Attended';
                    statusColor = Colors.green.shade700;
                    statusIcon = Icons.check_circle_outline;
                    break;
                  case AttendanceStatus.absent:
                    statusText = 'Absent';
                    statusColor = Colors.red.shade700;
                    statusIcon = Icons.cancel_outlined;
                    break;
                  case AttendanceStatus.cancelled:
                    statusText = 'Holiday';
                    statusColor = Colors.grey.shade600;
                    statusIcon = Icons.celebration_outlined;
                    break;
                  default:
                    statusText = 'Awaiting Status';
                    statusColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
                    statusIcon = Icons.hourglass_empty;
                }

                // Show a single button to toggle Holiday / Unmark Holiday
                if (showActions) {
                  if (attendance?.status == AttendanceStatus.cancelled) {
                    trailingWidget = IconButton(
                      icon: const Icon(Icons.cancel_outlined),
                      tooltip: 'Unmark Holiday',
                      color: Colors.grey,
                      onPressed: () => subjectProvider.unmarkAttendance(
                        subject.id,
                        today,
                        slotKey: slotKey,
                      ),
                    );
                  } else {
                    trailingWidget = IconButton(
                      icon: const Icon(Icons.celebration_outlined),
                      tooltip: 'Mark Holiday',
                      color: Colors.purple,
                      onPressed: () => subjectProvider.markAttendance(
                        subject.id,
                        today,
                        AttendanceStatus.cancelled,
                        slotKey: slotKey,
                      ),
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
                          Text(timeSlot.formatTimeRange(timeFormatProvider.timeFormat)),
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
                                    fontStyle: FontStyle.italic,
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
                );

                if (semesterEnded) {
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
                  key: ValueKey('${subject.id}_$slotKey'),
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
                    today: today,
                    subjectProvider: subjectProvider,
                  ),
                  onSwipeLeft: () => _handleSwipeAction(
                    context: context,
                    action: swipeProvider.leftAction,
                    isUnmarking: isUnmarkingLeft,
                    subject: subject,
                    slotKey: slotKey,
                    today: today,
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
