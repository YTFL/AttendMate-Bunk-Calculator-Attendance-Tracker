import 'dart:math';

import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_utils.dart';
import '../../utils/string_extension.dart';
import '../../widgets/app_time_picker.dart';
import '../settings/time_format_provider.dart';
import 'class_color_palettes.dart';
import 'subject_model.dart';
import 'subject_provider.dart';
import '../../services/database_service.dart';
import '../location/location_model.dart';
import '../location/location_manager_screen.dart';
import '../semester/semester_provider.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_overlay.dart';

class AddSubjectScreen extends StatefulWidget {
  const AddSubjectScreen({super.key});

  @override
  State<AddSubjectScreen> createState() => _AddSubjectScreenState();
}

class _AddSubjectScreenState extends State<AddSubjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _acronymController = TextEditingController();

  final GlobalKey _subjectNameKey = GlobalKey();
  final GlobalKey _locationDropdownKey = GlobalKey();
  final GlobalKey _specialToggleKey = GlobalKey();
  final GlobalKey _addSlotKey = GlobalKey();
  final GlobalKey _saveSubjectKey = GlobalKey();

  Color _selectedColor = weeklyClassColors.first;
  bool _isSpecialClass = false;
  final Set<DateTime> _specialClassDates = <DateTime>{};
  int _targetAttendance = 75;
  final List<TimeSlot> _schedule = [];
  List<LocationConfig> _locations = [];
  LocationConfig? _selectedLocation;
  bool _loadingLocations = true;

  @override
  void initState() {
    super.initState();
    _selectedColor = _pickRandomAvailableColor();
    _loadLocations();

    final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);
    if (semesterProvider.semester != null) {
      _targetAttendance = semesterProvider.semester!.targetPercentage.round();
    }

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
    if (tutorialController.isActive && (tutorialController.currentStepIndex < 5 || tutorialController.currentStepIndex >= 10)) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _loadLocations() async {
    final locs = await DatabaseService().loadLocations();
    if (mounted) {
      setState(() {
        _locations = locs;
        _loadingLocations = false;
      });
    }
  }

  @override
  void dispose() {
    try {
      final tutorialController = Provider.of<TutorialController>(context, listen: false);
      tutorialController.removeListener(_onTutorialStepChanged);
    } catch (_) {}
    _nameController.dispose();
    _acronymController.dispose();
    super.dispose();
  }

  // ── Color helpers ────────────────────────────────────────────────────────

  Set<int> _getUsedWeeklyColorValues() {
    final subjectProvider =
        Provider.of<SubjectProvider>(context, listen: false);
    return subjectProvider.subjects
        .where((s) => !s.isSpecialClass)
        .map((s) => s.color.toARGB32())
        .toSet();
  }

  Set<int> _getUsedSpecialColorValuesForDate(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final subjectProvider =
        Provider.of<SubjectProvider>(context, listen: false);
    return subjectProvider.subjects
        .where((s) => s.isSpecialClass)
        .where((s) =>
            s.specialClassDates.any((d) => isSameDay(d, normalizedDate)) ||
            (s.specialClassDate != null && isSameDay(s.specialClassDate!, normalizedDate)))
        .map((s) => s.color.toARGB32())
        .toSet();
  }

  Set<int> _getUsedColorValuesForCurrentMode() {
    if (_isSpecialClass) {
      if (_specialClassDates.isEmpty) return <int>{};
      final used = <int>{};
      for (final d in _specialClassDates) {
        used.addAll(_getUsedSpecialColorValuesForDate(d));
      }
      return used;
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



  Future<TimeOfDay?> _selectTime({
    required BuildContext context,
    required TimeOfDay initialTime,
    required String helpText,
  }) async {
    return await showAppTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: helpText,
    );
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

    if (_isSpecialClass && _specialClassDates.isEmpty) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(content: Text('Please add at least one date under "Class Dates" before adding time slots.')),
      );
      return;
    }

    final timeFormat =
        Provider.of<TimeFormatProvider>(context, listen: false).timeFormat;

    final existing = editIndex != null ? _schedule[editIndex] : null;

    // State for the bottom sheet
    TimeOfDay startTime = existing?.startTime ?? TimeOfDay.now();
    TimeOfDay endTime = existing?.endTime ?? _defaultEndTime(startTime);
    final Set<DayOfWeek> selectedDays = existing != null && existing.specificDate == null
        ? {existing.day}
        : {};
    final Set<DateTime> selectedSpecialDates = existing != null && existing.specificDate != null
        ? {existing.specificDate!}
        : Set<DateTime>.from(_specialClassDates);

    LocationConfig? slotLocation;
    if (existing != null && existing.locationId != null) {
      try {
        slotLocation = _locations.firstWhere((l) => l.id == existing.locationId);
      } catch (_) {
        slotLocation = LocationConfig(
          id: existing.locationId!,
          name: existing.room ?? 'Unknown Room',
          block: existing.block,
        );
      }
    }

    bool timeError = _toMinutes(endTime) <= _toMinutes(startTime);

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.12)
          : null,
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
              child: SingleChildScrollView(
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
                        fontSize: 20, fontWeight: FontWeight.bold),
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
                  ] else ...[
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Dates for this class',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        if (editIndex == null && _specialClassDates.length > 1)
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              setSheetState(() {
                                if (selectedSpecialDates.length == _specialClassDates.length) {
                                  selectedSpecialDates.clear();
                                } else {
                                  selectedSpecialDates.addAll(_specialClassDates);
                                }
                              });
                            },
                            child: Text(selectedSpecialDates.length == _specialClassDates.length ? 'Deselect All' : 'Select All'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: (_specialClassDates.toList()..sort()).map((date) {
                        final selected = selectedSpecialDates.any((d) => isSameDay(d, date));
                        return FilterChip(
                          label: Text(
                            DateFormat('MMM d (EEE)').format(date),
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
                                  selectedSpecialDates.clear();
                                }
                                selectedSpecialDates.add(date);
                              } else {
                                selectedSpecialDates.removeWhere((d) => isSameDay(d, date));
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
                    if (selectedSpecialDates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              'Select at least one date',
                              style: TextStyle(
                                  color: colorScheme.error, fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                  ],

                  // Class specific location
                  const SizedBox(height: 24),
                  DropdownButtonFormField<LocationConfig?>(
                    initialValue: slotLocation,
                    decoration: InputDecoration(
                      labelText: 'Class Location (Optional)',
                      hintText: 'Use Subject Default Location',
                      prefixIcon: Icon(Icons.pin_drop_outlined, color: colorScheme.onSurface.withValues(alpha: 0.4)),
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                    items: [
                      DropdownMenuItem<LocationConfig?>(
                        value: null,
                        child: Text(
                          _selectedLocation != null
                              ? 'Default (${_selectedLocation!.name})'
                              : 'Default (Use Subject Location)',
                          style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.8)),
                        ),
                      ),
                      ..._locations.map((loc) => DropdownMenuItem<LocationConfig?>(
                            value: loc,
                            child: Text('${loc.name}${loc.block != null && loc.block!.isNotEmpty ? " (${loc.block})" : ""}'),
                          )),
                    ],
                    onChanged: (val) {
                      setSheetState(() => slotLocation = val);
                    },
                  ),

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
                              (isWeekly && selectedDays.isEmpty) ||
                              (!isWeekly && selectedSpecialDates.isEmpty))
                          ? null
                          : () {
                              if (_isSpecialClass) {
                                setState(() {
                                  if (editIndex != null) {
                                    _schedule.removeAt(editIndex);
                                  }
                                  for (final date in selectedSpecialDates) {
                                    _schedule.add(TimeSlot(
                                      day: DayOfWeek.values[
                                          date.weekday - 1],
                                      startTime: startTime,
                                      endTime: endTime,
                                      specificDate: date,
                                      locationId: slotLocation?.id,
                                      room: slotLocation?.name,
                                      block: slotLocation?.block,
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
                                      locationId: slotLocation?.id,
                                      room: slotLocation?.name,
                                      block: slotLocation?.block,
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
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
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
      initialDate: _specialClassDates.isEmpty ? now : _specialClassDates.last,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (!mounted || selected == null) return;
    final normalized = DateTime(selected.year, selected.month, selected.day);
    setState(() {
      _specialClassDates.add(normalized);
      _selectedColor = _pickRandomAvailableColor();
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
      barrierColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.12)
          : null,
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
      _specialClassDates.clear();
      _selectedColor = _pickRandomAvailableColor();
    });
  }

  // ── Save subject ─────────────────────────────────────────────────────────

  void _save() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final acronymRaw = _acronymController.text.trim();
    final defaultAcronym = Subject.defaultAcronymFromName(name);
    final acronym =
        acronymRaw.isEmpty ? defaultAcronym : acronymRaw.toUpperCase();

    if (_schedule.isEmpty) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('Please add at least one time slot.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_isSpecialClass && _specialClassDates.isEmpty) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('Please select at least one date for the special class.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_isSpecialClass) {
      final usedSpecialColors = _getUsedColorValuesForCurrentMode();
      if (usedSpecialColors.contains(_selectedColor.toARGB32())) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text(
                'This color is already used by another special class on one of these days.'),
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
    Provider.of<SubjectProvider>(context, listen: false).addSubject(
      Subject(
        name: name,
        acronym: acronym,
        color: _selectedColor,
        schedule: _schedule,
        targetAttendance: _targetAttendance,
        locationId: _selectedLocation?.id,
        room: _selectedLocation?.name,
        block: _selectedLocation?.block,
      ),
    );

    Navigator.pop(context);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    tutorialController.registerKey('key_subject_name', _subjectNameKey);
    tutorialController.registerKey('key_location_dropdown', _locationDropdownKey);
    tutorialController.registerKey('key_special_toggle', _specialToggleKey);
    tutorialController.registerKey('key_add_slot', _addSlotKey);
    tutorialController.registerKey('key_save_subject', _saveSubjectKey);

    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeFormat = Provider.of<TimeFormatProvider>(context).timeFormat;

    final inputFill = isDark ? const Color(0xFF131316) : const Color(0xFFF6F6F8);
    final inputBorder = isDark ? const Color(0xFF222227) : const Color(0xFFE5E5EB);
    final inputFocusBorder = isDark ? Colors.white : Colors.black;

    return TutorialOverlay(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Add New Subject',
            style: GoogleFonts.roboto(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          centerTitle: false,
          elevation: 0,
          actions: [
            KeyedSubtree(
              key: _saveSubjectKey,
              child: TextButton(
                onPressed: _save,
                child: Text(
                  'Save',
                  style: GoogleFonts.roboto(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              children: [
                // ── Subject Name & Acronym fields ───────────────────────────
                KeyedSubtree(
                  key: _subjectNameKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        style: GoogleFonts.roboto(fontWeight: FontWeight.w600, fontSize: 15, color: isDark ? Colors.white : Colors.black),
                        decoration: InputDecoration(
                          labelText: 'Subject Name',
                          hintText: 'e.g., Mathematics, Physics',
                          labelStyle: TextStyle(color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70), fontSize: 13),
                          hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 13),
                          filled: true,
                          fillColor: inputFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: inputBorder, width: 0.8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: inputFocusBorder, width: 1.2),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: colorScheme.error, width: 1),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: colorScheme.error, width: 1.5),
                          ),
                          prefixIcon: Icon(Icons.book_outlined, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70), size: 19),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty
                                ? 'Subject name is required'
                                : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _acronymController,
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(3),
                        ],
                        style: GoogleFonts.roboto(fontWeight: FontWeight.w600, fontSize: 15, color: isDark ? Colors.white : Colors.black),
                        decoration: InputDecoration(
                          labelText: 'Acronym (3 letters max)',
                          hintText: 'e.g., MTH, PHY',
                          helperText: 'Leave empty to use first 3 letters of subject',
                          helperStyle: TextStyle(color: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93), fontSize: 11),
                          labelStyle: TextStyle(color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70), fontSize: 13),
                          hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 13),
                          filled: true,
                          fillColor: inputFill,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: inputBorder, width: 0.8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: inputFocusBorder, width: 1.2),
                          ),
                          prefixIcon: Icon(Icons.label_outline_rounded, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70), size: 19),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // ── Target Attendance Percentage ───────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: inputFill,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: inputBorder,
                            width: 0.8,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.track_changes_outlined,
                                      size: 18,
                                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Target Attendance',
                                      style: GoogleFonts.roboto(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: isDark ? Colors.white : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white : Colors.black,
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    '$_targetAttendance%',
                                    style: GoogleFonts.roboto(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: isDark ? Colors.black : Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                activeTrackColor: isDark ? Colors.white : Colors.black,
                                inactiveTrackColor: isDark ? const Color(0xFF24242B) : const Color(0xFFE0E0E5),
                                thumbColor: isDark ? Colors.white : Colors.black,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: _targetAttendance.toDouble(),
                                min: 50,
                                max: 100,
                                divisions: 50,
                                label: '$_targetAttendance%',
                                onChanged: (val) {
                                  final newTarget = val.round();
                                  if (newTarget != _targetAttendance) {
                                    HapticFeedback.vibrate();
                                    setState(() {
                                      _targetAttendance = newTarget;
                                    });
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Class Location Dropdown ──────────────────────────────────
                KeyedSubtree(
                  key: _locationDropdownKey,
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<LocationConfig?>(
                          initialValue: _loadingLocations ? null : _selectedLocation,
                          dropdownColor: isDark ? const Color(0xFF131316) : Colors.white,
                          style: GoogleFonts.roboto(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Default Subject Location (Optional)',
                            helperText: 'Applies to all classes unless overridden per slot',
                            helperStyle: TextStyle(
                              color: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93),
                              fontSize: 11,
                            ),
                            labelStyle: TextStyle(
                              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                              fontSize: 13,
                            ),
                            hintText: _loadingLocations ? 'Loading...' : 'Select a room / location',
                            hintStyle: TextStyle(
                              color: isDark ? Colors.white24 : Colors.black26,
                              fontSize: 13,
                            ),
                            prefixIcon: Icon(
                              Icons.pin_drop_outlined,
                              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                              size: 19,
                            ),
                            filled: true,
                            fillColor: inputFill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: inputBorder, width: 0.8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: inputFocusBorder, width: 1.2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                          ),
                          items: [
                            DropdownMenuItem<LocationConfig?>(
                              value: null,
                              child: Text(
                                'No location',
                                style: TextStyle(
                                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            ..._locations.map((loc) => DropdownMenuItem<LocationConfig?>(
                              value: loc,
                              child: Text(
                                '${loc.name}${loc.block != null ? " (${loc.block})" : ""}',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontSize: 14,
                                ),
                              ),
                            )),
                          ],
                          onChanged: _loadingLocations ? null : (val) {
                            setState(() => _selectedLocation = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        height: 54,
                        width: 50,
                        decoration: BoxDecoration(
                          color: inputFill,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: inputBorder, width: 0.8),
                        ),
                        child: IconButton(
                          icon: Icon(
                            Icons.add_location_alt_outlined,
                            size: 20,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          tooltip: 'Manage locations',
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const LocationManagerScreen()),
                            );
                            _loadLocations();
                          },
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // ── Color picker ────────────────────────────────────────────
              _buildColorRow(colorScheme, isDark),

              const SizedBox(height: 20),

              // ── Special class toggle ────────────────────────────────────
              KeyedSubtree(
                key: _specialToggleKey,
                child: _buildSpecialClassSection(colorScheme, isDark),
              ),

              const SizedBox(height: 20),

              // ── Schedule section ────────────────────────────────────────
              KeyedSubtree(
                key: _addSlotKey,
                child: _buildScheduleSection(colorScheme, timeFormat, isDark),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildColorRow(ColorScheme colorScheme, bool isDark) {
    final usedColorValues = _getUsedColorValuesForCurrentMode();
    final cardBg = isDark
        ? const Color(0xFF14141C).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.75);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.60);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'COLOR TELEMETRY',
                style: GoogleFonts.roboto(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                ),
              ),
              GestureDetector(
                onTap: _showColorPicker,
                child: Text(
                  'CUSTOM',
                  style: GoogleFonts.roboto(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 42,
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
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? (isDark ? Colors.white : Colors.black)
                            : Colors.transparent,
                        width: 2,
                      ),
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
                          : (isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 14)
                              : null),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialClassSection(ColorScheme colorScheme, bool isDark) {
    final cardBg = isDark
        ? const Color(0xFF14141C).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.75);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.60);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 0.8),
      ),
      child: Column(
        children: [
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            activeThumbColor: isDark ? Colors.white : Colors.black,
            title: Text(
              'Special Class (One-Day or Multi-Day)',
              style: GoogleFonts.roboto(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            subtitle: Text(
              'Does not repeat weekly — select arbitrary dates with or without gaps',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366),
              ),
            ),
            secondary: Icon(
              Icons.event_note_rounded,
              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
              size: 20,
            ),
            value: _isSpecialClass,
            onChanged: _toggleSpecialClass,
          ),
          if (_isSpecialClass) ...[
            Divider(height: 1, color: cardBorder, thickness: 0.8),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CLASS DATES (${_specialClassDates.length})',
                        style: GoogleFonts.roboto(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          letterSpacing: 1.1,
                          color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickSpecialClassDate,
                        icon: Icon(Icons.add, size: 14, color: isDark ? Colors.white : Colors.black),
                        label: Text(
                          'Add Date',
                          style: GoogleFonts.roboto(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: cardBorder, width: 0.8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_specialClassDates.isEmpty)
                    InkWell(
                      onTap: _pickSpecialClassDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0E0E12) : const Color(0xFFEDEDF2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cardBorder, width: 0.8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_today_rounded, size: 16, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366)),
                            const SizedBox(width: 8),
                            Text(
                              'Tap to add class dates',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: (_specialClassDates.toList()..sort()).map((date) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1B1B20) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: cardBorder, width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 13, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366)),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat('MMM d, y (EEE)').format(date),
                                style: GoogleFonts.roboto(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _specialClassDates.remove(date);
                                    _schedule.removeWhere((s) => s.specificDate != null && isSameDay(s.specificDate!, date));
                                    _sortSchedule();
                                  });
                                },
                                child: Icon(Icons.close, size: 14, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScheduleSection(ColorScheme colorScheme, dynamic timeFormat, bool isDark) {
    final cardBg = isDark
        ? const Color(0xFF14141C).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.75);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.60);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TIMETABLE SLOTS',
              style: GoogleFonts.roboto(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _showAddSlotSheet(),
              icon: Icon(Icons.add_rounded, size: 14, color: isDark ? Colors.white : Colors.black),
              label: Text(
                'Add Slot',
                style: GoogleFonts.roboto(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cardBorder, width: 0.8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_schedule.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 0.8),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.calendar_view_week_rounded,
                  size: 28,
                  color: isDark ? const Color(0xFF383842) : const Color(0xFFC7C7CC),
                ),
                const SizedBox(height: 10),
                Text(
                  _isSpecialClass
                      ? 'No time slots added.'
                      : 'No schedule added yet.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.roboto(
                    color: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
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
              return _buildSlotCard(slot, index, colorScheme, timeFormat, isDark);
            },
          ),
      ],
    );
  }

  Widget _buildSlotCard(TimeSlot slot, int index, ColorScheme colorScheme,
      dynamic timeFormat, bool isDark) {
    final cardBg = isDark
        ? const Color(0xFF14141C).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.75);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.60);

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
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.red),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder, width: 0.8),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B1B20) : const Color(0xFFEBEBF0),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                _slotLabel(slot).substring(0, min(3, _slotLabel(slot).length)).toUpperCase(),
                style: GoogleFonts.roboto(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 0.6,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _slotLabel(slot),
                    style: GoogleFonts.roboto(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    slot.formatTimeRange(timeFormat) +
                        (slot.room != null
                            ? '  |  ${slot.room}${slot.block != null && slot.block!.isNotEmpty ? " (${slot.block})" : ""}'
                            : (_selectedLocation != null ? '  |  Default (${_selectedLocation!.name})' : '')),
                    style: GoogleFonts.roboto(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 17, color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF636366)),
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showAddSlotSheet(editIndex: index),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 17, color: Color(0xFFFF453A)),
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  setState(() => _schedule.removeAt(index)),
            ),
          ],
        ),
      ),
    );
  }
}


