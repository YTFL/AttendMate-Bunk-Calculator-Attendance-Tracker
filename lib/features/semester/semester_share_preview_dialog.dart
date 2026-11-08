import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/semester_share_service.dart';
import '../../utils/error_utils.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../subject/elective_selection_dialog.dart';
import '../subject/subject_model.dart';

class SemesterSharePreviewDialog extends StatefulWidget {
  final Map<String, dynamic> shareData;
  final String? confirmButtonLabel;

  const SemesterSharePreviewDialog({
    super.key,
    required this.shareData,
    this.confirmButtonLabel,
  });

  @override
  State<SemesterSharePreviewDialog> createState() => _SemesterSharePreviewDialogState();
}

class _SemesterSharePreviewDialogState extends State<SemesterSharePreviewDialog> {
  bool _mergeIntoCurrent = false;
  bool _isImporting = false;
  late DateTime _effectiveFromDate;
  final List<ElectiveSlot> _electiveSlots = [];
  List<Subject> _selectedElectiveSubjects = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _effectiveFromDate = DateTime(now.year, now.month, now.day);

    final rawElectives = widget.shareData['electives'];
    if (rawElectives is List) {
      for (final e in rawElectives) {
        if (e is Map<String, dynamic>) {
          try {
            _electiveSlots.add(ElectiveSlot.fromJson(e));
          } catch (_) {}
        }
      }
    }

    // Default: select the first subject for each elective slot
    for (final slot in _electiveSlots) {
      if (slot.subjects.isNotEmpty) {
        _selectedElectiveSubjects.add(slot.subjects.first.copyWith(
          isElective: true,
          electiveGroupName: () => slot.name,
        ));
      }
    }
  }

  Future<void> _pickElectives() async {
    final chosen = await ElectiveSelectionDialog.show(
      context,
      electiveSlots: _electiveSlots,
    );
    if (chosen != null && mounted) {
      setState(() {
        _selectedElectiveSubjects = chosen;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final semesterMap = widget.shareData['semester'] as Map<String, dynamic>?;
    String? semesterRangeStr;
    double targetPct = 75.0;

    if (semesterMap != null) {
      final startStr = semesterMap['startDate'] as String?;
      final endStr = semesterMap['endDate'] as String?;
      targetPct = (semesterMap['targetPercentage'] as num?)?.toDouble() ?? 75.0;

      if (startStr != null && endStr != null) {
        try {
          final sDate = DateFormat.yMMMd().format(DateTime.parse(startStr));
          final eDate = DateFormat.yMMMd().format(DateTime.parse(endStr));
          semesterRangeStr = '$sDate  →  $eDate';
        } catch (_) {}
      }
    }

    final subjectsRaw = widget.shareData['subjects'] as List? ?? [];
    final List<Subject> regularSubjects = [];
    for (final item in subjectsRaw) {
      if (item is Map<String, dynamic>) {
        try {
          regularSubjects.add(Subject.fromJson(item));
        } catch (_) {}
      }
    }

    // Combine standard subjects + resolved selected electives for preview
    final allPreviewSubjects = [...regularSubjects, ..._selectedElectiveSubjects];

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
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(rs.scale(12)),
            ),
            child: Icon(
              Icons.share_arrival_time_outlined,
              color: theme.colorScheme.primary,
              size: rs.scale(24),
            ),
          ),
          SizedBox(width: rs.width(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import Shared Semester',
                  style: TextStyle(
                    fontSize: rs.font(17),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: rs.height(2)),
                Text(
                  'Shared by a classmate',
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
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: rs.height(8)),

            // Semester Summary Card
            if (semesterRangeStr != null) ...[
              Container(
                padding: EdgeInsets.all(rs.scale(14)),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
                      : theme.colorScheme.primaryContainer.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(rs.scale(14)),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Semester Dates',
                          style: TextStyle(
                            fontSize: rs.font(12),
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: rs.width(8), vertical: rs.height(2)),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(rs.scale(8)),
                          ),
                          child: Text(
                            'Target: ${targetPct.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: rs.font(11),
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(6)),
                    Text(
                      semesterRangeStr,
                      style: TextStyle(
                        fontSize: rs.font(13),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: rs.height(14)),
            ],

            // Electives Section (if detected)
            if (_electiveSlots.isNotEmpty) ...[
              Container(
                padding: EdgeInsets.all(rs.scale(12)),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(rs.scale(12)),
                  border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: rs.scale(20), color: theme.colorScheme.primary),
                    SizedBox(width: rs.width(10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Elective Slots (${_electiveSlots.length})',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: rs.font(13)),
                          ),
                          Text(
                            '${_selectedElectiveSubjects.length} of ${_electiveSlots.length} selected',
                            style: TextStyle(fontSize: rs.font(11), color: theme.textTheme.bodySmall?.color),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickElectives,
                      icon: const Icon(Icons.edit, size: 14),
                      label: const Text('Change'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.symmetric(horizontal: rs.width(10), vertical: rs.height(4)),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: rs.height(14)),
            ],

            // Subjects List Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'INCLUDED SUBJECTS (${allPreviewSubjects.length})',
                  style: TextStyle(
                    fontSize: rs.font(11),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  '0 Attendance History',
                  style: TextStyle(
                    fontSize: rs.font(11),
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
            SizedBox(height: rs.height(8)),

            // Subjects List Container
            Container(
              constraints: BoxConstraints(maxHeight: rs.height(180)),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(rs.scale(12)),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.15),
                ),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.all(rs.scale(10)),
                itemCount: allPreviewSubjects.length,
                separatorBuilder: (context, index) => Divider(height: rs.height(12)),
                itemBuilder: (context, index) {
                  final s = allPreviewSubjects[index];
                  final slots = s.schedule.length;
                  return Row(
                    children: [
                      Container(
                        width: rs.scale(12),
                        height: rs.scale(12),
                        decoration: BoxDecoration(
                          color: s.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: rs.width(10)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    s.name,
                                    style: TextStyle(
                                      fontSize: rs.font(13),
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (s.isElective) ...[
                                  SizedBox(width: rs.width(6)),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: rs.width(5), vertical: rs.height(1)),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(rs.scale(4)),
                                    ),
                                    child: Text(
                                      'Elective',
                                      style: TextStyle(
                                        fontSize: rs.font(9.5),
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (s.room != null || s.block != null)
                              Text(
                                [
                                  if (s.block != null) 'Block ${s.block}',
                                  if (s.room != null) 'Room ${s.room}',
                                ].join(' • '),
                                style: TextStyle(
                                  fontSize: rs.font(11),
                                  color: theme.textTheme.bodySmall?.color,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: rs.width(8), vertical: rs.height(3)),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(rs.scale(6)),
                        ),
                        child: Text(
                          '$slots class/week',
                          style: TextStyle(
                            fontSize: rs.font(11),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            SizedBox(height: rs.height(16)),

            // Import Options Radio
            Text(
              'Import Mode',
              style: TextStyle(
                fontSize: rs.font(12),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: rs.height(4)),

            RadioGroup<bool>(
              groupValue: _mergeIntoCurrent,
              onChanged: (val) {
                if (val != null) setState(() => _mergeIntoCurrent = val);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<bool>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    title: Text(
                      'Fresh Semester Setup (Recommended)',
                      style: TextStyle(fontSize: rs.font(13), fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Clears current subjects & sets up this semester template with 0 attendance recorded.',
                      style: TextStyle(fontSize: rs.font(11)),
                    ),
                  ),
                  RadioListTile<bool>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    title: Text(
                      'Merge Subjects into Current Semester',
                      style: TextStyle(fontSize: rs.font(13), fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Appends subjects to your existing semester without clearing current data.',
                      style: TextStyle(fontSize: rs.font(11)),
                    ),
                  ),
                  if (_mergeIntoCurrent) ...[
                    Padding(
                      padding: EdgeInsets.only(left: rs.width(8), top: rs.height(6)),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _effectiveFromDate,
                            firstDate: DateTime(now.year - 1),
                            lastDate: DateTime(now.year + 2),
                            helpText: 'Classes start from date (mid-semester)',
                          );
                          if (picked != null) {
                            setState(() => _effectiveFromDate = DateTime(picked.year, picked.month, picked.day));
                          }
                        },
                        icon: const Icon(Icons.calendar_today_rounded, size: 14),
                        label: Text('Classes Start: ${DateFormat('dd/MM/yyyy').format(_effectiveFromDate)}'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.symmetric(horizontal: rs.width(10), vertical: rs.height(4)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isImporting ? null : _handleImport,
          icon: _isImporting
              ? SizedBox(
                  width: rs.scale(16),
                  height: rs.scale(16),
                  child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.download_rounded, size: 18),
          label: Text(_isImporting ? 'Importing...' : (widget.confirmButtonLabel ?? 'Import Semester')),
        ),
      ],
    );
  }

  Future<void> _handleImport() async {
    setState(() {
      _isImporting = true;
    });

    try {
      final regularSubjectsRaw = (widget.shareData['subjects'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();

      final resolvedSubjects = [
        ...regularSubjectsRaw,
        ..._selectedElectiveSubjects.map((s) => s.toJson()),
      ];

      final packageToImport = Map<String, dynamic>.from(widget.shareData);
      packageToImport['subjects'] = resolvedSubjects;

      final success = await SemesterShareService().importSharedSemesterPackage(
        packageToImport,
        context,
        mergeIntoCurrent: _mergeIntoCurrent,
        effectiveFromDate: _mergeIntoCurrent ? _effectiveFromDate : null,
      );

      if (!mounted) return;
      Navigator.pop(context, success);

      if (success) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(
            content: Text('Semester setup imported successfully! Start tracking your attendance.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
      });
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to import semester')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
