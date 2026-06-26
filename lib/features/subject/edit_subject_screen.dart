import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_utils.dart';
import '../../utils/string_extension.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import '../settings/time_format_provider.dart';
import 'class_color_palettes.dart';
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
  final _nameController = TextEditingController();
  final _acronymController = TextEditingController();

  late Color _selectedColor;
  late bool _isSpecialClass;
  DateTime? _specialClassDate;
  final List<TimeSlot> _schedule = [];

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.subject.name;
    _acronymController.text = widget.subject.acronym ?? '';
    _selectedColor = widget.subject.color;
    _isSpecialClass = widget.subject.isSpecialClass;
    _specialClassDate = widget.subject.specialClassDate;
    _schedule.addAll(widget.subject.schedule);
    _sortSchedule();

    _nameController.addListener(() => setState(() {}));
    _acronymController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _acronymController.dispose();
    super.dispose();
  }

  // ── Color helpers ────────────────────────────────────────────────────────

  Set<int> _getUsedWeeklyColorValues() {
    final subjectProvider =
        Provider.of<SubjectProvider>(context, listen: false);
    return subjectProvider.subjects
        .where((s) => s.id != widget.subject.id && !s.isSpecialClass)
        .map((s) => s.color.toARGB32())
        .toSet();
  }

  Set<int> _getUsedSpecialColorValuesForDate(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final subjectProvider =
        Provider.of<SubjectProvider>(context, listen: false);
    return subjectProvider.subjects
        .where((s) => s.id != widget.subject.id && s.isSpecialClass && s.specialClassDate != null)
        .where((s) => isSameDay(s.specialClassDate!, normalizedDate))
        .map((s) => s.color.toARGB32())
        .toSet();
  }

  Set<int> _getUsedColorValuesForCurrentMode() {
    if (_isSpecialClass) {
      if (_specialClassDate == null) return <int>{};
      return _getUsedSpecialColorValuesForDate(_specialClassDate!);
    }
    return _getUsedWeeklyColorValues();
  }

  List<Color> get _activePalette =>
      _isSpecialClass ? specialClassColors : weeklyClassColors;

  Color _pickRandomAvailableColor() {
    final usedColorValues = _getUsedColorValuesForCurrentMode();
    final availableColors = _activePalette
        .where((c) => !usedColorValues.contains(c.toARGB32()))
        .toList();
    final source = availableColors.isEmpty ? _activePalette : availableColors;
    return source[Random().nextInt(source.length)];
  }

  // ── Schedule helpers ─────────────────────────────────────────────────────

  void _sortSchedule() {
    _schedule.sort((a, b) {
      final aDate = a.specificDate;
      final bDate = b.specificDate;
      if (aDate != null && bDate != null) {
        final d = aDate.compareTo(bDate);
        if (d != 0) return d;
      }
      final dayCompare = a.day.index.compareTo(b.day.index);
      if (dayCompare != 0) return dayCompare;
      final aTime = a.startTime.hour * 60 + a.startTime.minute;
      final bTime = b.startTime.hour * 60 + b.startTime.minute;
      return aTime.compareTo(bTime);
    });
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  TimeOfDay _defaultEndTime(TimeOfDay start) {
    final totalMinutes = _toMinutes(start) + 60;
    final candidate = TimeOfDay(
      hour: (totalMinutes ~/ 60) % 24,
      minute: totalMinutes % 60,
    );
    if (_toMinutes(candidate) > _toMinutes(start)) return candidate;
    return const TimeOfDay(hour: 23, minute: 59);
  }

  // ── Time picker builder (respects time format setting) ───────────────────

  Widget _timePickerBuilder(BuildContext ctx, Widget? child) {
    final tfp = Provider.of<TimeFormatProvider>(ctx, listen: false);
    return MediaQuery(
      data: MediaQuery.of(ctx).copyWith(
        alwaysUse24HourFormat: tfp.is24Hour,
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }

  Future<TimeOfDay?> _selectTime({
    required BuildContext context,
    required TimeOfDay initialTime,
    required String helpText,
  }) async {
    final provider = Provider.of<TimeFormatProvider>(context, listen: false);
    if (provider.clockStyle == ClockStyle.material) {
      return await showTimePicker(
        context: context,
        initialTime: initialTime,
        helpText: helpText,
        builder: _timePickerBuilder,
      );
    } else {
      return await showDialog<TimeOfDay>(
        context: context,
        builder: (BuildContext dialogCtx) {
          return _CustomScrollTimePickerDialog(
            initialTime: initialTime,
            helpText: helpText,
            is24Hour: provider.is24Hour,
          );
        },
      );
    }
  }

  // ── Date formatting ──────────────────────────────────────────────────────

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _slotLabel(TimeSlot slot) {
    if (slot.specificDate != null) {
      final date = slot.specificDate!;
      return '${slot.day.name.capitalize()}, ${_formatDate(date)}';
    }
    return slot.day.name.capitalize();
  }

  // ── Slot bottom sheet ────────────────────────────────────────────────────

  Future<void> _showAddSlotSheet({int? editIndex}) async {
    FocusScope.of(context).unfocus();

    final timeFormat =
        Provider.of<TimeFormatProvider>(context, listen: false).timeFormat;

    final existing = editIndex != null ? _schedule[editIndex] : null;

    // State for the bottom sheet
    TimeOfDay startTime = existing?.startTime ?? TimeOfDay.now();
    TimeOfDay endTime = existing?.endTime ?? _defaultEndTime(startTime);
    final Set<DayOfWeek> selectedDays = existing != null
        ? {existing.day}
        : {};

    bool timeError = _toMinutes(endTime) <= _toMinutes(startTime);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final colorScheme = Theme.of(ctx).colorScheme;

            void pickEnd() async {
              final picked = await _selectTime(
                context: ctx,
                initialTime: endTime,
                helpText: 'Select End Time',
              );
              if (picked == null) return;
              setSheetState(() {
                endTime = picked;
                timeError = _toMinutes(endTime) <= _toMinutes(startTime);
              });
            }

            void pickStart() async {
              final picked = await _selectTime(
                context: ctx,
                initialTime: startTime,
                helpText: 'Select Start Time',
              );
              if (picked == null) return;
              setSheetState(() {
                startTime = picked;
                // Auto-adjust end time if it becomes invalid
                if (_toMinutes(endTime) <= _toMinutes(startTime)) {
                  endTime = _defaultEndTime(startTime);
                }
                timeError = _toMinutes(endTime) <= _toMinutes(startTime);
              });

              // Automatically prompt for end time
              Future.delayed(const Duration(milliseconds: 300), () {
                if (ctx.mounted) {
                  pickEnd();
                }
              });
            }

            String fmtTime(TimeOfDay t) {
              if (timeFormat.index == 1) {
                return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
              }
              final h = t.hour == 0
                  ? 12
                  : (t.hour > 12 ? t.hour - 12 : t.hour);
              final period = t.hour < 12 ? 'AM' : 'PM';
              return '${h.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} $period';
            }

            Widget timeButton({
              required String label,
              required TimeOfDay time,
              required VoidCallback onTap,
              bool isError = false,
            }) {
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: isError
                        ? colorScheme.errorContainer.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isError
                          ? colorScheme.error
                          : colorScheme.outlineVariant.withValues(alpha: 0.8),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          color: isError
                              ? colorScheme.error
                              : colorScheme.onSurface.withValues(alpha: 0.5),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            fmtTime(time),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isError
                                  ? colorScheme.error
                                  : colorScheme.onSurface,
                            ),
                          ),
                          Icon(
                            Icons.access_time_rounded,
                            size: 16,
                            color: isError
                                ? colorScheme.error
                                : colorScheme.onSurface.withValues(alpha: 0.35),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }

            final isWeekly = !_isSpecialClass;

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  Text(
                    editIndex != null ? 'Edit Time Slot' : 'Add Time Slot',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 24),

                  // Time pickers row
                  Row(
                    children: [
                      Expanded(
                        child: timeButton(
                          label: 'START TIME',
                          time: startTime,
                          onTap: pickStart,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: timeButton(
                          label: 'END TIME',
                          time: endTime,
                          onTap: pickEnd,
                          isError: timeError,
                        ),
                      ),
                    ],
                  ),

                  if (timeError) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: colorScheme.error, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'End time must be after start time',
                            style: TextStyle(
                                color: colorScheme.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Weekly day picker
                  if (isWeekly) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Days of Week',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: DayOfWeek.values.map((day) {
                        final selected = selectedDays.contains(day);
                        return ChoiceChip(
                          label: Text(
                            day.name.capitalize().substring(0, 3),
                            style: TextStyle(
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                              color: selected ? Colors.white : colorScheme.onSurface,
                            ),
                          ),
                          selected: selected,
                          onSelected: (val) {
                            setSheetState(() {
                              if (val) {
                                if (editIndex != null) {
                                  selectedDays.clear();
                                }
                                selectedDays.add(day);
                              } else {
                                selectedDays.remove(day);
                              }
                            });
                          },
                          selectedColor: _selectedColor,
                          backgroundColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          checkmarkColor: Colors.white,
                          showCheckmark: false,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: selected ? _selectedColor : colorScheme.outlineVariant.withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (selectedDays.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              'Select at least one day',
                              style: TextStyle(
                                  color: colorScheme.error, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                  ],

                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _selectedColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: (timeError ||
                              (isWeekly && selectedDays.isEmpty))
                          ? null
                          : () {
                              // Build slots
                              if (_isSpecialClass) {
                                if (_specialClassDate == null) {
                                  Navigator.pop(ctx);
                                  _pickSpecialClassDate().then((_) {
                                    if (!mounted ||
                                        _specialClassDate == null) {
                                      return;
                                    }
                                    final date = _specialClassDate!;
                                    setState(() {
                                      if (editIndex != null) {
                                        _schedule[editIndex] = TimeSlot(
                                          day: DayOfWeek.values[
                                              date.weekday - 1],
                                          startTime: startTime,
                                          endTime: endTime,
                                          specificDate: date,
                                        );
                                      } else {
                                        _schedule.add(TimeSlot(
                                          day: DayOfWeek.values[
                                              date.weekday - 1],
                                          startTime: startTime,
                                          endTime: endTime,
                                          specificDate: date,
                                        ));
                                      }
                                      _sortSchedule();
                                    });
                                  });
                                  return;
                                }

                                final date = _specialClassDate!;
                                setState(() {
                                  if (editIndex != null) {
                                    _schedule[editIndex] = TimeSlot(
                                      day: DayOfWeek.values[
                                          date.weekday - 1],
                                      startTime: startTime,
                                      endTime: endTime,
                                      specificDate: date,
                                    );
                                  } else {
                                    _schedule.add(TimeSlot(
                                      day: DayOfWeek.values[
                                          date.weekday - 1],
                                      startTime: startTime,
                                      endTime: endTime,
                                      specificDate: date,
                                    ));
                                  }
                                  _sortSchedule();
                                });
                              } else {
                                setState(() {
                                  if (editIndex != null) {
                                    _schedule.removeAt(editIndex);
                                  }
                                  for (final day in selectedDays) {
                                    _schedule.add(TimeSlot(
                                      day: day,
                                      startTime: startTime,
                                      endTime: endTime,
                                    ));
                                  }
                                  _sortSchedule();
                                });
                              }
                              Navigator.pop(ctx);
                            },
                      child: Text(
                        editIndex != null ? 'Update Slot' : 'Add Slot',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Special class date picker ────────────────────────────────────────────

  Future<void> _pickSpecialClassDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _specialClassDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (!mounted || selected == null) return;
    final normalized = DateTime(selected.year, selected.month, selected.day);
    setState(() {
      _specialClassDate = normalized;
      final updated = _schedule.map((slot) => TimeSlot(
            day: DayOfWeek.values[normalized.weekday - 1],
            startTime: slot.startTime,
            endTime: slot.endTime,
            specificDate: normalized,
          )).toList();
      _schedule
        ..clear()
        ..addAll(updated);
      _selectedColor = _pickRandomAvailableColor();
      _sortSchedule();
    });
  }

  // ── Color picker bottom sheet ────────────────────────────────────────────

  void _showColorPicker() {
    FocusScope.of(context).unfocus();
    final usedColorValues = _getUsedColorValuesForCurrentMode();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final colorScheme = Theme.of(ctx).colorScheme;
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    _isSpecialClass
                        ? 'Special Class Color'
                        : 'Subject Color',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isSpecialClass
                        ? 'Colors already used on this day are marked.'
                        : 'Colors already used by other subjects are marked.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 20),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1,
                    ),
                    itemCount: _activePalette.length,
                    itemBuilder: (ctx, index) {
                      final color = _activePalette[index];
                      final isSelected =
                          color.toARGB32() == _selectedColor.toARGB32();
                      final isUsed =
                          usedColorValues.contains(color.toARGB32());
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedColor = color);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? colorScheme.onSurface
                                  : Colors.transparent,
                              width: isSelected ? 3.5 : 0,
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (isUsed)
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (isSelected)
                                const Icon(Icons.check,
                                    color: Colors.white, size: 16)
                              else if (isUsed)
                                Icon(Icons.close,
                                    color: Colors.white.withValues(alpha: 0.8),
                                    size: 14),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Toggle special class ─────────────────────────────────────────────────

  void _toggleSpecialClass(bool enabled) {
    setState(() {
      _isSpecialClass = enabled;
      _schedule.clear();
      _specialClassDate = null;
      _selectedColor = _pickRandomAvailableColor();
    });
  }

  // ── Save subject ─────────────────────────────────────────────────────────

  void _save() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final acronymRaw = _acronymController.text.trim();
    final acronym =
        acronymRaw.isEmpty ? name.acronymFromName() : acronymRaw;

    if (_schedule.isEmpty) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('Please add at least one time slot.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_isSpecialClass && _specialClassDate == null) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('Please select a date for the special class.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_isSpecialClass) {
      final usedSpecialColors =
          _getUsedSpecialColorValuesForDate(_specialClassDate!);
      if (usedSpecialColors.contains(_selectedColor.toARGB32())) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text(
                'This color is already used by another special class on this day.'),
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
            content:
                Text('This color is already used by another subject.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    _sortSchedule();

    final updatedSubject = widget.subject.copyWith(
      name: name,
      acronym: acronym,
      color: _selectedColor,
      schedule: _schedule,
    );

    Provider.of<SubjectProvider>(context, listen: false).updateSubject(
      widget.subject,
      updatedSubject,
    );

    Navigator.pop(context);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timeFormat = Provider.of<TimeFormatProvider>(context).timeFormat;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Subject'),
        centerTitle: false,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text(
              'Save',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              // ── Subject name field ──────────────────────────────────────
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Subject Name',
                  hintText: 'e.g., Mathematics, Physics',
                  filled: true,
                  fillColor: colorScheme.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: _selectedColor, width: 1.5),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colorScheme.error, width: 1),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colorScheme.error, width: 1.5),
                  ),
                  prefixIcon: Icon(Icons.book_rounded, color: colorScheme.onSurface.withValues(alpha: 0.4)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty
                        ? 'Subject name is required'
                        : null,
              ),

              const SizedBox(height: 16),

              // ── Acronym field ───────────────────────────────────────────
              TextFormField(
                controller: _acronymController,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                decoration: InputDecoration(
                  labelText: 'Acronym (Optional)',
                  hintText: 'e.g., MTH, PHY',
                  helperText: 'Leave empty to auto-generate',
                  helperStyle: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.45)),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: _selectedColor, width: 1.5),
                  ),
                  prefixIcon: Icon(Icons.label_rounded, color: colorScheme.onSurface.withValues(alpha: 0.4)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                ),
                onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
              ),

              const SizedBox(height: 28),

              // ── Color picker ────────────────────────────────────────────
              _buildColorRow(colorScheme),

              const SizedBox(height: 28),

              // ── Special class toggle ────────────────────────────────────
              _buildSpecialClassSection(colorScheme),

              const SizedBox(height: 32),

              // ── Schedule section ────────────────────────────────────────
              _buildScheduleSection(colorScheme, timeFormat),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorRow(ColorScheme colorScheme) {
    final usedColorValues = _getUsedColorValuesForCurrentMode();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.palette_rounded, size: 18, color: colorScheme.onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 8),
            const Text('Color Palette',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(
              onPressed: _showColorPicker,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('All Colors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _activePalette.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (ctx, index) {
              final color = _activePalette[index];
              final isSelected =
                  color.toARGB32() == _selectedColor.toARGB32();
              final isUsed =
                  usedColorValues.contains(color.toARGB32());
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = color),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: colorScheme.onSurface, width: 2)
                        : null,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: isUsed && !isSelected
                        ? Icon(Icons.close,
                            color: Colors.white.withValues(alpha: 0.65),
                            size: 12)
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSpecialClassSection(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            title: const Text('Special One-Day Class',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
              'Does not repeat weekly — for make-up or extra classes',
              style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withValues(alpha: 0.5)),
            ),
            secondary: Icon(Icons.event_note_rounded,
                color: _isSpecialClass ? _selectedColor : colorScheme.onSurface.withValues(alpha: 0.4)),
            value: _isSpecialClass,
            onChanged: _toggleSpecialClass,
          ),
          if (_isSpecialClass) ...[
            Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Icon(Icons.calendar_today_rounded, color: _selectedColor),
              title: Text(
                _specialClassDate == null
                    ? 'Tap to select date'
                    : _formatDate(_specialClassDate!),
                style: TextStyle(
                  color: _specialClassDate == null
                      ? colorScheme.onSurface.withValues(alpha: 0.5)
                      : colorScheme.onSurface,
                  fontWeight: _specialClassDate != null
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              subtitle: _specialClassDate != null
                  ? Text(
                      _specialClassDate!.weekday == DateTime.monday
                          ? 'Monday'
                          : _specialClassDate!.weekday == DateTime.tuesday
                              ? 'Tuesday'
                              : _specialClassDate!.weekday ==
                                      DateTime.wednesday
                                  ? 'Wednesday'
                                  : _specialClassDate!.weekday ==
                                          DateTime.thursday
                                      ? 'Thursday'
                                      : _specialClassDate!.weekday ==
                                              DateTime.friday
                                          ? 'Friday'
                                          : _specialClassDate!.weekday ==
                                                  DateTime.saturday
                                              ? 'Saturday'
                                              : 'Sunday',
                      style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface
                              .withValues(alpha: 0.5)),
                    )
                  : null,
              trailing: Icon(Icons.chevron_right_rounded, color: _selectedColor),
              onTap: _pickSpecialClassDate,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScheduleSection(ColorScheme colorScheme, dynamic timeFormat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule_rounded, size: 18, color: colorScheme.onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 8),
            const Text(
              'Schedule',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showAddSlotSheet(),
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('Add Slot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_schedule.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Icon(Icons.calendar_view_week_rounded,
                    size: 32,
                    color:
                        colorScheme.onSurface.withValues(alpha: 0.25)),
                const SizedBox(height: 10),
                Text(
                  _isSpecialClass
                      ? 'No time slots added.'
                      : 'No schedule added yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color:
                        colorScheme.onSurface.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _schedule.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (ctx, index) {
              final slot = _schedule[index];
              return _buildSlotCard(slot, index, colorScheme, timeFormat);
            },
          ),
      ],
    );
  }

  Widget _buildSlotCard(TimeSlot slot, int index, ColorScheme colorScheme,
      dynamic timeFormat) {
    return Dismissible(
      key: ValueKey('${slot.day.index}-${slot.startTime.hour}-${slot.startTime.minute}-$index'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        setState(() => _schedule.removeAt(index));
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.red),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4), width: 1),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _slotLabel(slot),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      slot.formatTimeRange(timeFormat),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.edit_rounded, size: 18, color: colorScheme.onSurface.withValues(alpha: 0.5)),
              tooltip: 'Edit',
              onPressed: () => _showAddSlotSheet(editIndex: index),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
              tooltip: 'Delete',
              onPressed: () =>
                  setState(() => _schedule.removeAt(index)),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _CustomScrollTimePickerDialog extends StatefulWidget {
  final TimeOfDay initialTime;
  final String helpText;
  final bool is24Hour;

  const _CustomScrollTimePickerDialog({
    required this.initialTime,
    required this.helpText,
    required this.is24Hour,
  });

  @override
  State<_CustomScrollTimePickerDialog> createState() => _CustomScrollTimePickerDialogState();
}

class _CustomScrollTimePickerDialogState extends State<_CustomScrollTimePickerDialog> {
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  FixedExtentScrollController? _periodController;

  @override
  void initState() {
    super.initState();
    final hour = widget.initialTime.hour;
    final minute = widget.initialTime.minute;

    if (widget.is24Hour) {
      _hourController = FixedExtentScrollController(initialItem: hour);
      _minuteController = FixedExtentScrollController(initialItem: minute);
    } else {
      final isPm = hour >= 12;
      final hour12 = hour % 12;
      final initialHourIndex = (hour12 == 0 ? 12 : hour12) - 1;

      _hourController = FixedExtentScrollController(initialItem: initialHourIndex);
      _minuteController = FixedExtentScrollController(initialItem: minute);
      _periodController = FixedExtentScrollController(initialItem: isPm ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _periodController?.dispose();
    super.dispose();
  }

  int _wrapIndex(int value, int length) {
    return value % length < 0 ? (value % length) + length : value % length;
  }

  TimeOfDay _getCurrentTime() {
    if (widget.is24Hour) {
      return TimeOfDay(
        hour: _wrapIndex(_hourController.selectedItem, 24),
        minute: _wrapIndex(_minuteController.selectedItem, 60),
      );
    } else {
      final hour12 = _wrapIndex(_hourController.selectedItem, 12) + 1;
      final isPm = (_periodController?.selectedItem ?? 0) == 1;
      int hour24;
      if (isPm) {
        hour24 = hour12 == 12 ? 12 : hour12 + 12;
      } else {
        hour24 = hour12 == 12 ? 0 : hour12;
      }
      return TimeOfDay(
        hour: hour24,
        minute: _wrapIndex(_minuteController.selectedItem, 60),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = TextStyle(
      color: theme.colorScheme.onSurface,
      fontSize: 34, // Increased font size for selector text
      fontWeight: FontWeight.bold,
    );

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      contentPadding: EdgeInsets.zero,
      titlePadding: const EdgeInsets.only(top: 20, left: 24, right: 24),
      title: Text(
        widget.helpText,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Hours Wheel
              SizedBox(
                width: 80,
                height: 220,
                child: CupertinoPicker(
                  scrollController: _hourController,
                  itemExtent: 48,
                  looping: true,
                  onSelectedItemChanged: (_) {},
                  children: List.generate(widget.is24Hour ? 24 : 12, (index) {
                    final val = widget.is24Hour ? index : index + 1;
                    return Center(
                      child: Text(
                        val.toString().padLeft(2, '0'),
                        style: textStyle,
                      ),
                    );
                  }),
                ),
              ),
              
              // Separator colon with spacing
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  ':',
                  style: textStyle.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
              
              // Minutes Wheel
              SizedBox(
                width: 80,
                height: 220,
                child: CupertinoPicker(
                  scrollController: _minuteController,
                  itemExtent: 48,
                  looping: true,
                  onSelectedItemChanged: (_) {},
                  children: List.generate(60, (index) {
                    return Center(
                      child: Text(
                        index.toString().padLeft(2, '0'),
                        style: textStyle,
                      ),
                    );
                  }),
                ),
              ),

              if (!widget.is24Hour) ...[
                const SizedBox(width: 24), // Large spacing before AM/PM
                SizedBox(
                  width: 80,
                  height: 220,
                  child: CupertinoPicker(
                    scrollController: _periodController,
                    itemExtent: 48,
                    onSelectedItemChanged: (_) {},
                    children: [
                      Center(
                        child: Text(
                          'AM',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          'PM',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context, _getCurrentTime());
          },
          child: Text(
            'Done',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
