import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/semester_share_service.dart';
import '../../utils/error_utils.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../subject/subject_model.dart';

class SemesterSharePreviewDialog extends StatefulWidget {
  final Map<String, dynamic> shareData;

  const SemesterSharePreviewDialog({
    super.key,
    required this.shareData,
  });

  @override
  State<SemesterSharePreviewDialog> createState() => _SemesterSharePreviewDialogState();
}

class _SemesterSharePreviewDialogState extends State<SemesterSharePreviewDialog> {
  bool _mergeIntoCurrent = false;
  bool _isImporting = false;

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
    final List<Subject> subjects = [];
    for (final item in subjectsRaw) {
      if (item is Map<String, dynamic>) {
        try {
          subjects.add(Subject.fromJson(item));
        } catch (_) {}
      }
    }

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

            // Subjects List Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'INCLUDED SUBJECTS (${subjects.length})',
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
                itemCount: subjects.length,
                separatorBuilder: (context, index) => Divider(height: rs.height(12)),
                itemBuilder: (context, index) {
                  final s = subjects[index];
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
                            Text(
                              s.name,
                              style: TextStyle(
                                fontSize: rs.font(13),
                                fontWeight: FontWeight.bold,
                              ),
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
          label: Text(_isImporting ? 'Importing...' : 'Import Semester'),
        ),
      ],
    );
  }

  Future<void> _handleImport() async {
    setState(() {
      _isImporting = true;
    });

    try {
      final success = await SemesterShareService().importSharedSemesterPackage(
        widget.shareData,
        context,
        mergeIntoCurrent: _mergeIntoCurrent,
      );

      if (!mounted) return;
      Navigator.pop(context);

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
