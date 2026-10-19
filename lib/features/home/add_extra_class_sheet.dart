import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_utils.dart';
import '../../utils/time_format_utils.dart';
import '../../widgets/app_time_picker.dart';
import '../settings/time_format_provider.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';

class ExtraClassBadge extends StatelessWidget {
  const ExtraClassBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF00897B).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Extra',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF00897B),
          height: 1.2,
        ),
      ),
    );
  }
}

Future<void> showAddExtraClassSheet({
  required BuildContext context,
  required DateTime date,
}) async {
  final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
  if (subjectProvider.subjects.isEmpty) {
    ScaffoldMessenger.of(context).showReplacingSnackBar(
      const SnackBar(content: Text('Add a subject before scheduling an extra class.')),
    );
    return;
  }

  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    barrierColor: Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.12)
        : null,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _AddExtraClassSheet(date: date),
  );

  if (added == true && context.mounted) {
    ScaffoldMessenger.of(context).showReplacingSnackBar(
      const SnackBar(content: Text('Extra class added for this day.')),
    );
  }
}

Future<bool> confirmAndRemoveExtraClass({
  required BuildContext context,
  required String subjectId,
  required String subjectName,
  required DateTime date,
  required String slotKey,
}) async {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove Extra Class'),
      content: Text(
        'Remove the extra $subjectName class from this day? Your weekly timetable stays the same.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            HapticFeedback.vibrate();
            Navigator.pop(dialogContext, true);
          },
          child: const Text('Remove'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) {
    return false;
  }

  final result = await Provider.of<SubjectProvider>(context, listen: false).removeExtraClass(
    subjectId: subjectId,
    date: date,
    slotKey: slotKey,
  );

  if (!context.mounted) {
    return result.success;
  }

  ScaffoldMessenger.of(context).showReplacingSnackBar(
    SnackBar(
      content: Text(result.message),
      backgroundColor: result.success ? null : Colors.red,
    ),
  );
  return result.success;
}

class _AddExtraClassSheet extends StatefulWidget {
  final DateTime date;

  const _AddExtraClassSheet({required this.date});

  @override
  State<_AddExtraClassSheet> createState() => _AddExtraClassSheetState();
}

class _AddExtraClassSheetState extends State<_AddExtraClassSheet> {
  late String _subjectId;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  String? _errorText;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final subjects = Provider.of<SubjectProvider>(context, listen: false).subjects;
    final sorted = List<Subject>.from(subjects)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _subjectId = sorted.first.id;

    final latestEnd = _latestClassEnd(sorted, widget.date);
    if (latestEnd != null && latestEnd.hour < 23) {
      _startTime = TimeOfDay(hour: latestEnd.hour, minute: latestEnd.minute);
      final endHour = (latestEnd.hour + 1).clamp(0, 23);
      _endTime = TimeOfDay(
        hour: endHour,
        minute: endHour == 23 ? 59 : latestEnd.minute,
      );
      if (_toMinutes(_endTime) <= _toMinutes(_startTime)) {
        _endTime = const TimeOfDay(hour: 23, minute: 59);
      }
    } else {
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 10, minute: 0);
    }
  }

  TimeOfDay? _latestClassEnd(List<Subject> subjects, DateTime date) {
    TimeOfDay? latest;
    var latestMinutes = -1;
    for (final subject in subjects) {
      for (final slot in subject.schedule) {
        if (!slot.occursOnDate(date)) {
          continue;
        }
        if (slot.endMinutes > latestMinutes) {
          latestMinutes = slot.endMinutes;
          latest = slot.endTime;
        }
      }
    }
    return latest;
  }

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  String _formatDate(DateTime date) {
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showAppTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      helpText: isStart ? 'Select Start Time' : 'Select End Time',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (isStart) {
        _startTime = picked;
        if (_toMinutes(_endTime) <= _toMinutes(_startTime)) {
          final total = _toMinutes(_startTime) + 60;
          _endTime = TimeOfDay(hour: (total ~/ 60).clamp(0, 23), minute: total % 60);
          if (_toMinutes(_endTime) <= _toMinutes(_startTime)) {
            _endTime = const TimeOfDay(hour: 23, minute: 59);
          }
        }
      } else {
        _endTime = picked;
      }
      _errorText = null;
    });
  }

  Future<void> _save() async {
    if (_toMinutes(_endTime) <= _toMinutes(_startTime)) {
      setState(() => _errorText = 'End time must be after the start time.');
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    final result = await Provider.of<SubjectProvider>(context, listen: false).addExtraClass(
      subjectId: _subjectId,
      date: widget.date,
      startTime: _startTime,
      endTime: _endTime,
    );

    if (!mounted) {
      return;
    }

    if (!result.success) {
      setState(() {
        _saving = false;
        _errorText = result.message;
      });
      return;
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFormat = Provider.of<TimeFormatProvider>(context).timeFormat;
    final subjects = List<Subject>.from(Provider.of<SubjectProvider>(context).subjects)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (subjects.every((subject) => subject.id != _subjectId) && subjects.isNotEmpty) {
      _subjectId = subjects.first.id;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.dividerColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Add Extra Class',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _formatDate(widget.date),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Adds a makeup or extra lecture for this date only. The weekly timetable stays the same, and the class counts toward that subject.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              key: ValueKey(_subjectId),
              initialValue: _subjectId,
              decoration: const InputDecoration(
                labelText: 'Subject',
                border: OutlineInputBorder(),
              ),
              items: subjects
                  .map(
                    (subject) => DropdownMenuItem<String>(
                      value: subject.id,
                      child: Text(
                        subject.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _subjectId = value;
                        _errorText = null;
                      });
                    },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: 'Starts',
                    value: TimeFormatUtils.formatTime(_startTime, timeFormat),
                    onTap: _saving ? null : () => _pickTime(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeField(
                    label: 'Ends',
                    value: TimeFormatUtils.formatTime(_endTime, timeFormat),
                    onTap: _saving ? null : () => _pickTime(isStart: false),
                  ),
                ),
              ],
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Adding…' : 'Add Class'),
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

class _TimeField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(value),
      ),
    );
  }
}
