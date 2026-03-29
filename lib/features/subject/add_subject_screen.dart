import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/string_extension.dart';
import '../settings/time_format_provider.dart';
import 'class_color_palettes.dart';
import 'subject_model.dart';
import 'subject_provider.dart';

class AddSubjectScreen extends StatefulWidget {
  const AddSubjectScreen({super.key});

  @override
  State<AddSubjectScreen> createState() => _AddSubjectScreenState();
}

class _AddSubjectScreenState extends State<AddSubjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final FocusNode _nameFocusNode = FocusNode(canRequestFocus: false);
  final FocusNode _acronymFocusNode = FocusNode(canRequestFocus: false);
  Timer? _typingIdleTimer;
  Timer? _invalidTimeToastTimer;
  OverlayEntry? _invalidTimeToastEntry;

  String _subjectName = '';
  String? _subjectAcronym;
  late Color _selectedColor;
  bool _isSpecialClass = false;
  DateTime? _specialClassDate;
  final List<TimeSlot> _schedule = [];

  @override
  void initState() {
    super.initState();
    _selectedColor = _pickRandomAvailableColor();
  }

  @override
  void dispose() {
    _typingIdleTimer?.cancel();
    _invalidTimeToastTimer?.cancel();
    _invalidTimeToastEntry?.remove();
    _nameFocusNode.dispose();
    _acronymFocusNode.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    _typingIdleTimer?.cancel();
    _nameFocusNode.unfocus();
    _acronymFocusNode.unfocus();
    _nameFocusNode.canRequestFocus = false;
    _acronymFocusNode.canRequestFocus = false;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _activateTextField(FocusNode node) {
    _typingIdleTimer?.cancel();
    if (!node.canRequestFocus) {
      node.canRequestFocus = true;
    }
    FocusScope.of(context).requestFocus(node);
  }

  void _scheduleTypingStopDismiss() {
    _typingIdleTimer?.cancel();
    _typingIdleTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        _dismissKeyboard();
      }
    });
  }

  Future<void> _prepareForDialogTransition() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 60));
  }

  Widget _timePickerBuilder(BuildContext context, Widget? child) {
    final timeFormatProvider =
        Provider.of<TimeFormatProvider>(context, listen: false);
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        alwaysUse24HourFormat: timeFormatProvider.is24Hour,
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  Set<int> _getUsedWeeklyColorValues() {
    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
    return subjectProvider.subjects
        .where((s) => !s.isSpecialClass)
        .map((s) => s.color.toARGB32())
        .toSet();
  }

  Set<int> _getUsedSpecialColorValuesForDate(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
    return subjectProvider.subjects
        .where((s) => s.isSpecialClass && s.specialClassDate != null)
        .where((s) => isSameDay(s.specialClassDate!, normalizedDate))
        .map((s) => s.color.toARGB32())
        .toSet();
  }

  Set<int> _getUsedColorValuesForCurrentMode() {
    if (_isSpecialClass) {
      if (_specialClassDate == null) {
        return <int>{};
      }
      return _getUsedSpecialColorValuesForDate(_specialClassDate!);
    }
    return _getUsedWeeklyColorValues();
  }

  List<Color> get _activePalette =>
      _isSpecialClass ? specialClassColors : weeklyClassColors;

  Color _pickRandomAvailableColor() {
    final usedColorValues = _getUsedColorValuesForCurrentMode();
    final availableColors = _activePalette
        .where((color) => !usedColorValues.contains(color.toARGB32()))
        .toList();
    final source = availableColors.isEmpty ? _activePalette : availableColors;
    return source[Random().nextInt(source.length)];
  }

  Future<void> _showColorPicker() async {
    await _prepareForDialogTransition();
    if (!mounted) return;

    final usedColorValues = _getUsedColorValuesForCurrentMode();
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) {
        Color selected = _selectedColor;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_isSpecialClass
                  ? 'Select Special Class Color'
                  : 'Select Weekly Class Color'),
              content: SizedBox(
                width: double.maxFinite,
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: _activePalette.length,
                  itemBuilder: (context, index) {
                    final color = _activePalette[index];
                    final isSelected = color.toARGB32() == selected.toARGB32();
                    final isUsed = usedColorValues.contains(color.toARGB32());
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() => selected = color);
                        setState(() => _selectedColor = color);
                        Navigator.pop(context);
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          if (isUsed)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (isUsed)
                            const Icon(Icons.close, color: Colors.white, size: 30),
                        ],
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _sortSchedule() {
    _schedule.sort((a, b) {
      final aDate = a.specificDate;
      final bDate = b.specificDate;
      if (aDate != null && bDate != null) {
        final dateCompare = aDate.compareTo(bDate);
        if (dateCompare != 0) return dateCompare;
      }

      final dayCompare = a.day.index.compareTo(b.day.index);
      if (dayCompare != 0) return dayCompare;

      final aTime = a.startTime.hour * 60 + a.startTime.minute;
      final bTime = b.startTime.hour * 60 + b.startTime.minute;
      return aTime.compareTo(bTime);
    });
  }

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  TimeOfDay _defaultEndTimeAfterStart(TimeOfDay startTime) {
    final totalMinutes = _toMinutes(startTime) + 60;
    final candidate = TimeOfDay(
      hour: (totalMinutes ~/ 60) % 24,
      minute: totalMinutes % 60,
    );
    if (_toMinutes(candidate) > _toMinutes(startTime)) {
      return candidate;
    }
    return const TimeOfDay(hour: 23, minute: 59);
  }

  String _acronymFromSubjectName(String subjectName) {
    return subjectName.acronymFromName();
  }

  void _showInvalidTimeSnackBar() {
    if (!mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    final colorScheme = Theme.of(context).colorScheme;
    _invalidTimeToastTimer?.cancel();
    _invalidTimeToastEntry?.remove();
    final entry = OverlayEntry(
      builder: (context) => SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'End time must be after start time.',
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ),
        ),
      ),
    );
    _invalidTimeToastEntry = entry;
    overlay.insert(entry);
    _invalidTimeToastTimer = Timer(const Duration(seconds: 2), () {
      entry.remove();
      if (identical(_invalidTimeToastEntry, entry)) {
        _invalidTimeToastEntry = null;
      }
    });
  }

  Future<TimeOfDay?> _pickEndTimeAfterStart(TimeOfDay startTime) async {
    while (mounted) {
      final endTime = await showTimePicker(
        context: context,
        useRootNavigator: false,
        initialTime: _defaultEndTimeAfterStart(startTime),
        helpText: 'Select End Time',
        builder: _timePickerBuilder,
      );
      if (endTime == null || !mounted) return null;
      if (_toMinutes(endTime) > _toMinutes(startTime)) {
        return endTime;
      }
      _showInvalidTimeSnackBar();
    }
    return null;
  }

  Future<void> _pickSpecialClassDate() async {
    await _prepareForDialogTransition();
    if (!mounted) return;

    final now = DateTime.now();
    final initialDate = _specialClassDate ?? now;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (!mounted || selected == null) return;

    final normalized = DateTime(selected.year, selected.month, selected.day);
    final oldSchedule = List<TimeSlot>.from(_schedule);
    final updatedSchedule = oldSchedule
        .map(
          (slot) => TimeSlot(
            day: DayOfWeek.values[normalized.weekday - 1],
            startTime: slot.startTime,
            endTime: slot.endTime,
            specificDate: normalized,
          ),
        )
        .toList();

    setState(() {
      _specialClassDate = normalized;
      _schedule
        ..clear()
        ..addAll(updatedSchedule);
      _selectedColor = _pickRandomAvailableColor();
      _sortSchedule();
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _slotLabel(TimeSlot slot) {
    if (slot.specificDate != null) {
      final date = slot.specificDate!;
      return '${slot.day.name.capitalize()}, ${_formatDate(date)}';
    }
    return slot.day.name.capitalize();
  }

  Future<void> _showTimePicker() async {
    await _prepareForDialogTransition();
    if (!mounted) return;

    final startTime = await showTimePicker(
      context: context,
      useRootNavigator: false,
      initialTime: TimeOfDay.now(),
      helpText: 'Select Start Time',
      builder: _timePickerBuilder,
    );
    if (startTime == null || !mounted) return;

    final endTime = await _pickEndTimeAfterStart(startTime);
    if (endTime == null || !mounted) return;

    if (_isSpecialClass) {
      if (_specialClassDate == null) {
        await _pickSpecialClassDate();
      }
      if (!mounted || _specialClassDate == null) return;

      final date = _specialClassDate!;
      setState(() {
        _schedule.add(
          TimeSlot(
            day: DayOfWeek.values[date.weekday - 1],
            startTime: startTime,
            endTime: endTime,
            specificDate: date,
          ),
        );
        _sortSchedule();
      });
      return;
    }

    await _showWeeklyDayPicker(startTime, endTime);
  }

  Future<void> _editTimeslot(int index) async {
    await _prepareForDialogTransition();
    if (!mounted) return;

    final timeSlot = _schedule[index];
    final startTime = await showTimePicker(
      context: context,
      useRootNavigator: false,
      initialTime: timeSlot.startTime,
      helpText: 'Select Start Time',
      builder: _timePickerBuilder,
    );
    if (startTime == null || !mounted) return;

    final endTime = await _pickEndTimeAfterStart(startTime);
    if (endTime == null || !mounted) return;

    if (_isSpecialClass) {
      final date = _specialClassDate;
      if (date == null) return;
      setState(() {
        _schedule[index] = TimeSlot(
          day: DayOfWeek.values[date.weekday - 1],
          startTime: startTime,
          endTime: endTime,
          specificDate: date,
        );
        _sortSchedule();
      });
      return;
    }

    await _showWeeklyDayPicker(startTime, endTime, editIndex: index);
  }

  Future<void> _showWeeklyDayPicker(
    TimeOfDay startTime,
    TimeOfDay endTime, {
    int? editIndex,
  }) async {
    if (!mounted) return;

    final List<DayOfWeek>? days = await showDialog<List<DayOfWeek>>(
      context: context,
      useRootNavigator: false,
      builder: (context) {
        final selectedDays = List.filled(7, false);
        if (editIndex != null) {
          selectedDays[_schedule[editIndex].day.index] = true;
        }
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(editIndex != null ? 'Edit Days' : 'Select Days'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: DayOfWeek.values.map((day) {
                    return CheckboxListTile(
                      title: Text(day.name.capitalize()),
                      value: selectedDays[day.index],
                      onChanged: (value) {
                        setState(() {
                          selectedDays[day.index] = value!;
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final List<DayOfWeek> result = [];
                    for (int i = 0; i < selectedDays.length; i++) {
                      if (selectedDays[i]) {
                        result.add(DayOfWeek.values[i]);
                      }
                    }
                    Navigator.pop(context, result);
                  },
                  child: Text(editIndex != null ? 'Update' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (days != null && days.isNotEmpty) {
      setState(() {
        if (editIndex != null) {
          _schedule.removeAt(editIndex);
        }
        _schedule.addAll(days.map(
          (day) => TimeSlot(day: day, startTime: startTime, endTime: endTime),
        ));
        _sortSchedule();
      });
    }
  }

  void _toggleSpecialClass(bool enabled) {
    setState(() {
      _isSpecialClass = enabled;
      _schedule.clear();
      _specialClassDate = null;
      _selectedColor = _pickRandomAvailableColor();
    });
  }

  void _addSubject() {
    _dismissKeyboard();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    _formKey.currentState!.save();

    final resolvedAcronym = (_subjectAcronym == null || _subjectAcronym!.isEmpty)
        ? _acronymFromSubjectName(_subjectName)
        : _subjectAcronym;

    if (_schedule.isEmpty) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('Please add at least one time slot.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_isSpecialClass) {
      if (_specialClassDate == null) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('Please pick a date for the special class.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final usedSpecialColors = _getUsedSpecialColorValuesForDate(_specialClassDate!);
      if (usedSpecialColors.contains(_selectedColor.toARGB32())) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('This special class color is already used on the selected day.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } else {
      final usedWeeklyColors = _getUsedWeeklyColorValues();
      if (usedWeeklyColors.contains(_selectedColor.toARGB32())) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('This weekly class color is already used by another weekly class.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    _sortSchedule();
    Provider.of<SubjectProvider>(context, listen: false).addSubject(
      Subject(
        name: _subjectName,
        acronym: resolvedAcronym,
        color: _selectedColor,
        schedule: _schedule,
      ),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final timeFormat = Provider.of<TimeFormatProvider>(context).timeFormat;
    final rs = context.rs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Subject'),
      ),
      body: Padding(
        padding: rs.insetsAll(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Special One-Day Class'),
                subtitle: const Text(
                  'Special classes do not repeat weekly.',
                ),
                value: _isSpecialClass,
                onChanged: _toggleSpecialClass,
              ),
              if (_isSpecialClass)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: const Text('Special Class Date'),
                  subtitle: Text(
                    _specialClassDate == null
                        ? 'Tap to choose date'
                        : _formatDate(_specialClassDate!),
                  ),
                  onTap: _pickSpecialClassDate,
                ),
              SizedBox(height: rs.height(8)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _showColorPicker,
                    child: Container(
                      width: rs.scale(50),
                      height: rs.scale(50),
                      margin: EdgeInsets.only(right: rs.width(12), top: rs.height(8)),
                      decoration: BoxDecoration(
                        color: _selectedColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextFormField(
                      focusNode: _nameFocusNode,
                      autofocus: false,
                      onTapOutside: (_) => _dismissKeyboard(),
                      onTap: () => _activateTextField(_nameFocusNode),
                      onChanged: (_) => _scheduleTypingStopDismiss(),
                      onEditingComplete: _dismissKeyboard,
                      onFieldSubmitted: (_) => _dismissKeyboard(),
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Subject Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value!.trim().isEmpty ? 'Please enter a subject name' : null,
                      onSaved: (value) => _subjectName = value!.trim(),
                    ),
                  ),
                ],
              ),
              SizedBox(height: rs.height(12)),
              TextFormField(
                focusNode: _acronymFocusNode,
                autofocus: false,
                onTapOutside: (_) => _dismissKeyboard(),
                onTap: () => _activateTextField(_acronymFocusNode),
                onChanged: (_) => _scheduleTypingStopDismiss(),
                onEditingComplete: _dismissKeyboard,
                onFieldSubmitted: (_) => _dismissKeyboard(),
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Subject Acronym (Optional)',
                  hintText: 'e.g., MTH, PHY',
                  border: OutlineInputBorder(),
                ),
                onSaved: (value) => _subjectAcronym =
                    value?.trim().isEmpty ?? true ? null : value!.trim(),
              ),
              SizedBox(height: rs.height(20)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isSpecialClass ? 'Special Day Schedule' : 'Weekly Schedule',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: rs.font(14)),
                  ),
                  ElevatedButton.icon(
                    icon: Icon(Icons.add, size: rs.scale(18)),
                    onPressed: _showTimePicker,
                    label: const Text('Add Slot'),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: _schedule.isEmpty
                    ? Center(
                        child: Text(
                          _isSpecialClass
                              ? 'No special slots added. Tap Add Slot to begin.'
                              : 'No weekly slots added. Tap Add Slot to begin.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: _schedule.length,
                        itemBuilder: (context, index) {
                          final timeSlot = _schedule[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              leading: const Icon(Icons.access_time),
                              title: Text(_slotLabel(timeSlot)),
                              subtitle: Text(timeSlot.formatTimeRange(timeFormat)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                                    onPressed: () => _editTimeslot(index),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () {
                                      _dismissKeyboard();
                                      setState(() {
                                        _schedule.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _addSubject,
                  child: const Text('Add Subject'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
