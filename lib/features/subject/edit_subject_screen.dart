import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_utils.dart';
import '../../utils/string_extension.dart';
import '../settings/time_format_provider.dart';
import 'subject_model.dart';
import 'subject_provider.dart';

class EditSubjectScreen extends StatefulWidget {
  final Subject subject;

  const EditSubjectScreen({super.key, required this.subject});

  @override
  State<EditSubjectScreen> createState() => _EditSubjectScreenState();
}

class _EditSubjectScreenState extends State<EditSubjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final FocusNode _nameFocusNode = FocusNode(canRequestFocus: false);
  final FocusNode _acronymFocusNode = FocusNode(canRequestFocus: false);
  Timer? _typingIdleTimer;
  Timer? _invalidTimeToastTimer;
  OverlayEntry? _invalidTimeToastEntry;
  late String _subjectName;
  late String? _subjectAcronym;
  late Color _selectedColor;
  late List<TimeSlot> _schedule;

  Set<int> _getUsedColorValues() {
    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
    // Exclude current subject's color from used colors
    return subjectProvider.subjects
        .where((s) => s.id != widget.subject.id)
        .map((s) => s.color.toARGB32())
        .toSet();
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

  void _showColorPicker() async {
    await _prepareForDialogTransition();
    if (!mounted) return;
    final usedColorValues = _getUsedColorValues();
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (context) {
        Color selected = _selectedColor;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Select Color'),
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
                  itemCount: _colors.length,
                  itemBuilder: (context, index) {
                    final color = _colors[index];
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


  final List<Color> _colors = [
    const Color(0xFFE53935),
    const Color(0xFFD81B60),
    const Color(0xFFEC407A),
    const Color(0xFFAB47BC),
    const Color(0xFF8E24AA),
    const Color(0xFF5E35B1),
    const Color(0xFF3949AB),
    const Color(0xFF1E88E5),
    const Color(0xFF42A5F5),
    const Color(0xFF039BE5),
    const Color(0xFF26C6DA),
    const Color(0xFF00ACC1),
    const Color(0xFF26A69A),
    const Color(0xFF00897B),
    const Color(0xFF43A047),
    const Color(0xFF66BB6A),
    const Color(0xFF7CB342),
    const Color(0xFFC0CA33),
    const Color(0xFFFDD835),
    const Color(0xFFFFCA28),
    const Color(0xFFFFB300),
    const Color(0xFFFB8C00),
    const Color(0xFFFF7043),
    const Color(0xFFF4511E),
    const Color(0xFF6D4C41),
    const Color(0xFF8D6E63),
    const Color(0xFF546E7A),
    const Color(0xFF757575),
  ];

  @override
  void initState() {
    super.initState();
    _subjectName = widget.subject.name;
    _subjectAcronym = widget.subject.acronym;
    _selectedColor = widget.subject.color;
    _schedule = List.from(widget.subject.schedule);
    _sortSchedule();
  }

  @override
  void dispose() {
    _typingIdleTimer?.cancel();
    _invalidTimeToastTimer?.cancel();
    _invalidTimeToastEntry?.remove();
    _invalidTimeToastEntry = null;
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

  void _sortSchedule() {
    _schedule.sort((a, b) {
      int dayCompare = a.day.index.compareTo(b.day.index);
      if (dayCompare != 0) return dayCompare;
      double aTime = a.startTime.hour + a.startTime.minute / 60.0;
      double bTime = b.startTime.hour + b.startTime.minute / 60.0;
      return aTime.compareTo(bTime);
    });
  }

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  TimeOfDay _addOneHour(TimeOfDay time) {
    final totalMinutes = _toMinutes(time) + 60;
    return TimeOfDay(hour: (totalMinutes ~/ 60) % 24, minute: totalMinutes % 60);
  }

  TimeOfDay _defaultEndTimeAfterStart(TimeOfDay startTime) {
    final candidate = _addOneHour(startTime);
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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
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

  Future<TimeOfDay?> _pickEndTimeAfterStart(TimeOfDay startTime, {TimeOfDay? initialEndTime}) async {
    while (mounted) {
      final initialTime = (initialEndTime != null && _toMinutes(initialEndTime) > _toMinutes(startTime))
          ? initialEndTime
          : _defaultEndTimeAfterStart(startTime);
      final endTime = await showTimePicker(
        context: context,
        useRootNavigator: false,
        initialTime: initialTime,
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

  void _updateSubject() {
    _dismissKeyboard();
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final resolvedAcronym = (_subjectAcronym == null || _subjectAcronym!.isEmpty)
          ? _acronymFromSubjectName(_subjectName)
          : _subjectAcronym;
      final usedColorValues = _getUsedColorValues();
      if (usedColorValues.contains(_selectedColor.toARGB32())) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('This color is already used by another subject.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (_schedule.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('Please add at least one time slot.'),
          ),
        );
        return;
      }
      _sortSchedule();
      final updatedSubject = widget.subject.copyWith(
        name: _subjectName,
        acronym: resolvedAcronym,
        color: _selectedColor,
        schedule: _schedule,
      );
      Provider.of<SubjectProvider>(context, listen: false)
          .updateSubject(widget.subject, updatedSubject);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  void _showTimePicker() async {
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

    await _showDayPicker(startTime, endTime);
  }

  void _editTimeslot(int index) async {
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

    final endTime = await _pickEndTimeAfterStart(startTime, initialEndTime: timeSlot.endTime);
    if (endTime == null || !mounted) return;

    await _showDayPicker(startTime, endTime, editIndex: index);
  }

  Future<void> _showDayPicker(TimeOfDay startTime, TimeOfDay endTime, {int? editIndex}) async {
    if (!mounted) return; // Guard against async gaps

    final List<DayOfWeek>? days = await showDialog<List<DayOfWeek>>(
      context: context,
      useRootNavigator: false,
      builder: (context) {
        final selectedDays = List.filled(7, false);
        // Pre-select the day if editing
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
          // Remove the old timeslot
          _schedule.removeAt(editIndex);
        }
        final newSlots = days.map((day) => TimeSlot(day: day, startTime: startTime, endTime: endTime));
        _schedule.addAll(newSlots);
        _sortSchedule();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Subject'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _showColorPicker,
                    child: Container(
                      width: 50,
                      height: 50,
                      margin: const EdgeInsets.only(right: 12, top: 8),
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
                      initialValue: _subjectName,
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
              const SizedBox(height: 12),
              TextFormField(
                focusNode: _acronymFocusNode,
                autofocus: false,
                onTapOutside: (_) => _dismissKeyboard(),
                onTap: () => _activateTextField(_acronymFocusNode),
                onChanged: (_) => _scheduleTypingStopDismiss(),
                onEditingComplete: _dismissKeyboard,
                onFieldSubmitted: (_) => _dismissKeyboard(),
                textInputAction: TextInputAction.done,
                initialValue: _subjectAcronym,
                decoration: const InputDecoration(
                  labelText: 'Subject Acronym (Optional)',
                  hintText: 'e.g., MTH, PHY',
                  border: OutlineInputBorder(),
                ),
                onSaved: (value) => _subjectAcronym = value?.trim().isEmpty ?? true ? null : value!.trim(),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Schedule', style: TextStyle(fontWeight: FontWeight.bold)),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: _showTimePicker,
                    label: const Text('Add Slot'),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: _schedule.isEmpty
                    ? const Center(child: Text('No time slots added.'))
                    : ListView.builder(
                        itemCount: _schedule.length,
                        itemBuilder: (context, index) {
                          final timeSlot = _schedule[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4.0),
                            child: ListTile(
                              leading: const Icon(Icons.access_time),
                              title: Text(timeSlot.day.name.capitalize()),
                              subtitle: Text(
                                timeSlot.formatTimeRange(
                                  Provider.of<TimeFormatProvider>(context)
                                      .timeFormat,
                                ),
                              ),
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
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _updateSubject,
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
