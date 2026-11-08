import 'package:flutter/material.dart';

import '../../utils/responsive_scale.dart';
import '../../utils/time_format_utils.dart';
import 'subject_model.dart';

class ElectiveSelectionDialog extends StatefulWidget {
  final List<ElectiveSlot> electiveSlots;

  const ElectiveSelectionDialog({
    super.key,
    required this.electiveSlots,
  });

  /// Static helper to display the elective selection dialog
  static Future<List<Subject>?> show(
    BuildContext context, {
    required List<ElectiveSlot> electiveSlots,
  }) {
    if (electiveSlots.isEmpty) return Future.value([]);
    return showDialog<List<Subject>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ElectiveSelectionDialog(electiveSlots: electiveSlots),
    );
  }

  @override
  State<ElectiveSelectionDialog> createState() => _ElectiveSelectionDialogState();
}

class _ElectiveSelectionDialogState extends State<ElectiveSelectionDialog> {
  // Map of slot ID -> selected subject ID (or null if skipped)
  final Map<String, String?> _selectedSubjectIds = {};

  @override
  void initState() {
    super.initState();
    for (final slot in widget.electiveSlots) {
      if (slot.subjects.isNotEmpty) {
        // Pre-select the first subject by default
        _selectedSubjectIds[slot.id] = slot.subjects.first.id;
      }
    }
  }

  List<Subject> _buildResolvedSubjects() {
    final chosen = <Subject>[];
    for (final slot in widget.electiveSlots) {
      final selectedId = _selectedSubjectIds[slot.id];
      if (selectedId != null) {
        final match = slot.subjects.firstWhere(
          (s) => s.id == selectedId,
          orElse: () => slot.subjects.first,
        );
        chosen.add(match.copyWith(
          isElective: true,
          electiveGroupName: () => slot.name,
        ));
      }
    }
    return chosen;
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(rs.scale(20)),
      ),
      titlePadding: EdgeInsets.fromLTRB(rs.width(20), rs.height(20), rs.width(20), rs.height(10)),
      contentPadding: EdgeInsets.symmetric(horizontal: rs.width(20)),
      actionsPadding: EdgeInsets.fromLTRB(rs.width(16), rs.height(10), rs.width(16), rs.height(16)),
      title: Row(
        children: [
          Container(
            padding: EdgeInsets.all(rs.scale(10)),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(rs.scale(12)),
            ),
            child: Icon(
              Icons.tune_rounded,
              color: colorScheme.primary,
              size: rs.scale(24),
            ),
          ),
          SizedBox(width: rs.width(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Elective Preferences',
                  style: TextStyle(
                    fontSize: rs.font(17),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: rs.height(2)),
                Text(
                  'Choose your enrolled course for each elective slot',
                  style: TextStyle(
                    fontSize: rs.font(12),
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: rs.height(8)),
              ...widget.electiveSlots.map((slot) => _buildElectiveSlotCard(context, rs, slot)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            final resolved = _buildResolvedSubjects();
            Navigator.pop(context, resolved);
          },
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Confirm Electives'),
        ),
      ],
    );
  }

  Widget _buildElectiveSlotCard(BuildContext context, ResponsiveScale rs, ElectiveSlot slot) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = theme.brightness == Brightness.dark;
    final selectedSubjectId = _selectedSubjectIds[slot.id];

    // Determine schedule summary for this slot
    String scheduleSummary = '';
    if (slot.subjects.isNotEmpty && slot.subjects.first.schedule.isNotEmpty) {
      final sampleSlot = slot.subjects.first.schedule.first;
      final days = slot.subjects.first.schedule.map((s) => s.day.name.substring(0, 3).toUpperCase()).toSet().join(', ');
      final timeStr = TimeFormatUtils.formatTimeRange(sampleSlot.startTime, sampleSlot.endTime, TimeFormat.format12Hr);
      scheduleSummary = '$days • $timeStr';
    }

    return Container(
      margin: EdgeInsets.only(bottom: rs.height(14)),
      decoration: BoxDecoration(
        color: isDarkMode
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(rs.scale(14)),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Slot Header
          Container(
            padding: EdgeInsets.symmetric(horizontal: rs.width(14), vertical: rs.height(10)),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.vertical(top: Radius.circular(rs.scale(13))),
            ),
            child: Row(
              children: [
                Icon(Icons.category_outlined, size: rs.scale(16), color: colorScheme.primary),
                SizedBox(width: rs.width(8)),
                Expanded(
                  child: Text(
                    slot.name,
                    style: TextStyle(
                      fontSize: rs.font(13.5),
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                if (scheduleSummary.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: rs.width(8), vertical: rs.height(2)),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(rs.scale(6)),
                    ),
                    child: Text(
                      scheduleSummary,
                      style: TextStyle(fontSize: rs.font(10.5), fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
          ),

          // Subjects Options
          Padding(
            padding: EdgeInsets.all(rs.scale(8)),
            child: Column(
              children: [
                ...slot.subjects.map((subject) {
                  final isSelected = selectedSubjectId == subject.id;
                  return InkWell(
                    borderRadius: BorderRadius.circular(rs.scale(10)),
                    onTap: () {
                      setState(() {
                        _selectedSubjectIds[slot.id] = subject.id;
                      });
                    },
                    child: Container(
                      margin: EdgeInsets.symmetric(vertical: rs.height(3)),
                      padding: EdgeInsets.symmetric(horizontal: rs.width(10), vertical: rs.height(8)),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(rs.scale(10)),
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant.withValues(alpha: 0.3),
                          width: isSelected ? 1.4 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Radio<String?>(
                            value: subject.id,
                            groupValue: selectedSubjectId,
                            onChanged: (val) {
                              setState(() {
                                _selectedSubjectIds[slot.id] = val;
                              });
                            },
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          SizedBox(width: rs.width(6)),
                          Container(
                            width: rs.scale(12),
                            height: rs.scale(12),
                            decoration: BoxDecoration(
                              color: subject.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: rs.width(8)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  subject.name,
                                  style: TextStyle(
                                    fontSize: rs.font(13),
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                                if (subject.room != null || subject.block != null)
                                  Text(
                                    [
                                      if (subject.block != null) 'Block ${subject.block}',
                                      if (subject.room != null) 'Room ${subject.room}',
                                    ].join(' • '),
                                    style: TextStyle(
                                      fontSize: rs.font(11),
                                      color: theme.textTheme.bodySmall?.color,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (subject.acronym != null)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: rs.width(6), vertical: rs.height(2)),
                              decoration: BoxDecoration(
                                color: subject.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(rs.scale(4)),
                              ),
                              child: Text(
                                subject.acronym!,
                                style: TextStyle(
                                  fontSize: rs.font(10),
                                  fontWeight: FontWeight.bold,
                                  color: subject.color,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),

                // Optional "None / Skip" tile
                InkWell(
                  borderRadius: BorderRadius.circular(rs.scale(10)),
                  onTap: () {
                    setState(() {
                      _selectedSubjectIds[slot.id] = null;
                    });
                  },
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: rs.height(3)),
                    padding: EdgeInsets.symmetric(horizontal: rs.width(10), vertical: rs.height(8)),
                    decoration: BoxDecoration(
                      color: selectedSubjectId == null
                          ? colorScheme.outline.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(rs.scale(10)),
                    ),
                    child: Row(
                      children: [
                        Radio<String?>(
                          value: null,
                          groupValue: selectedSubjectId,
                          onChanged: (val) {
                            setState(() {
                              _selectedSubjectIds[slot.id] = null;
                            });
                          },
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        SizedBox(width: rs.width(6)),
                        Icon(Icons.block_rounded, size: rs.scale(14), color: theme.textTheme.bodySmall?.color),
                        SizedBox(width: rs.width(8)),
                        Text(
                          'Skip / Not enrolled in this elective',
                          style: TextStyle(
                            fontSize: rs.font(12),
                            color: theme.textTheme.bodySmall?.color,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
