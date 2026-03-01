import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_utils.dart';
import '../semester/semester_provider.dart';
import '../settings/time_format_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    // Check if the semester has started yet
    final semester = semesterProvider.semester;
    if (semester != null && !semesterProvider.hasSemesterStarted) {
      final startDate = semester.startDate;
      final formattedDate = '${startDate.day}/${startDate.month}/${startDate.year}';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.pending_actions, size: 50, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'Semester Yet to Begin',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your semester will start on $formattedDate. Today\'s schedule will be available from that date.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }
    
    // Check if the semester has ended
    final bool semesterEnded = semesterProvider.hasSemesterEnded;

    final displayClasses = _expandSubjectsBySlot(subjectProvider.getClassesForDate(today));
    final isHoliday = subjectProvider.isHoliday(today);

    displayClasses.sort((a, b) {
      final aTime = a.schedule.first.startTime.hour * 60 + a.schedule.first.startTime.minute;
      final bTime = b.schedule.first.startTime.hour * 60 + b.schedule.first.startTime.minute;
      return aTime.compareTo(bTime);
    });

    return Column(
      children: [
        if (semesterEnded)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            color: Colors.orange.withValues(alpha: 0.1),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Semester has ended. Attendance tracking is disabled.',
                    style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        if (!semesterEnded && !isHoliday)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.celebration_outlined, size: 14),
                    label: const Text('Holiday', style: TextStyle(fontSize: 11)),
                    onPressed: () => _showConfirmationDialog(
                      context: context,
                      title: 'Mark as Holiday',
                      content: 'Are you sure you want to mark today as a holiday? All classes will be cancelled and won\'t affect attendance criteria.',
                      onConfirm: () => subjectProvider.markDayAsHoliday(today),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      backgroundColor: theme.colorScheme.onSurface,
                      foregroundColor: theme.colorScheme.surface,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.fast_forward_outlined, size: 14),
                    label: const Text('Skip Day', style: TextStyle(fontSize: 11)),
                    onPressed: () => _showConfirmationDialog(
                      context: context,
                      title: 'Skip Today',
                      content: 'Are you sure you want to skip all classes today? This will mark all scheduled classes as absent.',
                      onConfirm: () => subjectProvider.markDayAsAbsent(today),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      backgroundColor: theme.colorScheme.onSurface,
                      foregroundColor: theme.colorScheme.surface,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 14),
                    label: const Text('Present', style: TextStyle(fontSize: 11)),
                    onPressed: () => _showConfirmationDialog(
                      context: context,
                      title: 'Mark as Present',
                      content: 'Are you sure you want to mark today as present? All classes will be marked as attended.',
                      onConfirm: () => subjectProvider.markDayAsPresent(today),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      backgroundColor: theme.colorScheme.onSurface,
                      foregroundColor: theme.colorScheme.surface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (displayClasses.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 60, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'No Classes Today',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
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
              padding: const EdgeInsets.all(8),
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
                    // For attended classes, show "Mark Absent" and "Unmark" buttons
                    if (showActions) {
                      trailingWidget = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Mark Absent',
                            color: Colors.red,
                            onPressed: () => subjectProvider.markAttendance(
                              subject.id,
                              today,
                              AttendanceStatus.absent,
                              slotKey: slotKey,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel_outlined),
                            tooltip: 'Unmark',
                            color: Colors.grey,
                            onPressed: () => subjectProvider.unmarkAttendance(
                              subject.id,
                              today,
                              slotKey: slotKey,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.celebration_outlined),
                            tooltip: 'Mark Holiday',
                            color: Colors.purple,
                            onPressed: () => subjectProvider.markAttendance(
                              subject.id,
                              today,
                              AttendanceStatus.cancelled,
                              slotKey: slotKey,
                            ),
                          ),
                        ],
                      );
                    }
                    break;
                  case AttendanceStatus.absent:
                    statusText = 'Absent';
                    statusColor = Colors.red.shade700;
                    statusIcon = Icons.cancel_outlined;
                    // For absent classes, show "Mark Present" and "Unmark" buttons
                    if (showActions) {
                      trailingWidget = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check),
                            tooltip: 'Mark Present',
                            color: Colors.green,
                            onPressed: () => subjectProvider.markAttendance(
                              subject.id,
                              today,
                              AttendanceStatus.attended,
                              slotKey: slotKey,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel_outlined),
                            tooltip: 'Unmark',
                            color: Colors.grey,
                            onPressed: () => subjectProvider.unmarkAttendance(
                              subject.id,
                              today,
                              slotKey: slotKey,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.celebration_outlined),
                            tooltip: 'Mark Holiday',
                            color: Colors.purple,
                            onPressed: () => subjectProvider.markAttendance(
                              subject.id,
                              today,
                              AttendanceStatus.cancelled,
                              slotKey: slotKey,
                            ),
                          ),
                        ],
                      );
                    }
                    break;
                  case AttendanceStatus.cancelled:
                    statusText = 'Holiday';
                    statusColor = Colors.grey.shade600;
                    statusIcon = Icons.celebration_outlined;
                    if (showActions) {
                      trailingWidget = Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check),
                            tooltip: 'Mark Present',
                            color: Colors.green,
                            onPressed: () => subjectProvider.markAttendance(
                              subject.id,
                              today,
                              AttendanceStatus.attended,
                              slotKey: slotKey,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Mark Absent',
                            color: Colors.red,
                            onPressed: () => subjectProvider.markAttendance(
                              subject.id,
                              today,
                              AttendanceStatus.absent,
                              slotKey: slotKey,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel_outlined),
                            tooltip: 'Unmark',
                            color: Colors.grey,
                            onPressed: () => subjectProvider.unmarkAttendance(
                              subject.id,
                              today,
                              slotKey: slotKey,
                            ),
                          ),
                        ],
                      );
                    }
                    break;
                  default:
                    statusText = 'Awaiting Status';
                    statusColor = Theme.of(context).colorScheme.onSurface.withAlpha(179);
                    statusIcon = Icons.hourglass_empty;
                                    // For unmarked classes, show both buttons
                                    if (showActions) {
                                      trailingWidget = Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.check),
                                            tooltip: 'Mark Present',
                                            color: Colors.green,
                                            onPressed: () => subjectProvider.markAttendance(
                                              subject.id,
                                              today,
                                              AttendanceStatus.attended,
                                              slotKey: slotKey,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close),
                                            tooltip: 'Mark Absent',
                                            color: Colors.red,
                                            onPressed: () => subjectProvider.markAttendance(
                                              subject.id,
                                              today,
                                              AttendanceStatus.absent,
                                              slotKey: slotKey,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.celebration_outlined),
                                            tooltip: 'Mark Holiday',
                                            color: Colors.purple,
                                            onPressed: () => subjectProvider.markAttendance(
                                              subject.id,
                                              today,
                                              AttendanceStatus.cancelled,
                                              slotKey: slotKey,
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                }

                return Card(
                  elevation: 2.0,
                  margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                  shadowColor: isDarkMode ? null : Colors.black.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.4)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ListTile(
                      leading: CircleAvatar(
                        radius: 20.6,
                        backgroundColor: subject.color,
                        child: Center(
                          child: Text(
                            subject.acronym ?? '',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            softWrap: true,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                      title: Text(subject.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(timeSlot.formatTimeRange(timeFormatProvider.timeFormat)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(statusIcon, size: 16, color: statusColor),
                              const SizedBox(width: 4),
                              Text(statusText, style: TextStyle(color: statusColor, fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ],
                      ),
                      trailing: trailingWidget,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
