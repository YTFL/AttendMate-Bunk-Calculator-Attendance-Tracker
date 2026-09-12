import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/backup_service.dart';
import '../../utils/attendance_import_utils.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../attendance/attendance_provider.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';

class ImportAttendanceScreen extends StatefulWidget {
  final String? initialText;
  final bool embedInUnifiedImport;

  const ImportAttendanceScreen({
    super.key,
    this.initialText,
    this.embedInUnifiedImport = false,
  });

  @override
  State<ImportAttendanceScreen> createState() => _ImportAttendanceScreenState();
}

class _ImportAttendanceScreenState extends State<ImportAttendanceScreen> {
  static const MethodChannel _fileImportChannel = MethodChannel('com.attendmate.app/file_import');
  final TextEditingController _textController = TextEditingController();

  String? _errorMessage;
  AttendanceImportResult? _parsedResult;
  Map<String, ParsedSubjectAttendanceBaseline> _computedBaselines = {};
  bool _applyAsBaseline = true;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.trim().isNotEmpty) {
      _textController.text = widget.initialText!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _processAttendanceContent(_textController.text);
        }
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Clipboard is empty.');
      }
      return;
    }
    setState(() {
      _textController.text = text;
      _errorMessage = null;
    });
    if (mounted) {
      SnackbarUtils.showSuccessSnackBar(context, 'Pasted from clipboard.');
    }
  }

  void _clearText() {
    setState(() {
      _textController.clear();
      _errorMessage = null;
      _parsedResult = null;
      _computedBaselines = {};
    });
  }

  Future<void> _handleFileImport() async {
    try {
      final Map<dynamic, dynamic>? result =
          await _fileImportChannel.invokeMethod('pickImportFile');
      if (result == null) return;

      final content = result['content'] as String?;
      final fileName = result['fileName'] as String?;
      if (content == null || content.trim().isEmpty) {
        if (mounted) {
          SnackbarUtils.showErrorSnackBar(context, 'The selected file is empty.');
        }
        return;
      }

      setState(() {
        _textController.text = content;
        _errorMessage = null;
      });
      _processAttendanceContent(content, fileName: fileName);
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'File import failed: $e');
      }
    }
  }

  void _processAttendanceContent(String content, {String? fileName}) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter or paste JSON or CSV attendance data';
        _parsedResult = null;
        _computedBaselines = {};
      });
      return;
    }

    try {
      final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
      final subjects = subjectProvider.subjects;
      final parsed = AttendanceImportUtils.parseContent(trimmed, subjects, fileName: fileName);

      if (parsed.errors.isNotEmpty && parsed.items.isEmpty && parsed.directBaselines.isEmpty) {
        setState(() {
          _errorMessage = parsed.errors.take(4).join('\n');
          _parsedResult = null;
          _computedBaselines = {};
        });
        return;
      }

      final computed = parsed.computeBaselinesPerSubject();
      if (computed.isEmpty && parsed.items.isEmpty) {
        setState(() {
          _errorMessage = 'No matching subject records found in the provided data.';
          _parsedResult = null;
          _computedBaselines = {};
        });
        return;
      }

      setState(() {
        _errorMessage = null;
        _parsedResult = parsed;
        _computedBaselines = computed;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Parsing failed: $e';
        _parsedResult = null;
        _computedBaselines = {};
      });
    }
  }

  Future<void> _editSubjectAttendance(String subjectId, ParsedSubjectAttendanceBaseline baseline) async {
    final heldCtrl = TextEditingController(text: '${baseline.classesHeld}');
    final attendedCtrl = TextEditingController(text: '${baseline.classesAttended}');
    final colorScheme = Theme.of(context).colorScheme;

    final edited = await showDialog<bool>(
      context: context,
      builder: (editCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Edit: ${baseline.subject.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: heldCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Total Classes Held',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: attendedCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Classes Attended',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(editCtx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final h = int.tryParse(heldCtrl.text.trim()) ?? baseline.classesHeld;
                final a = int.tryParse(attendedCtrl.text.trim()) ?? baseline.classesAttended;
                if (h >= 0 && a >= 0 && a <= h) {
                  Navigator.pop(editCtx, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (edited == true && mounted) {
      final updatedHeld = int.tryParse(heldCtrl.text.trim()) ?? baseline.classesHeld;
      final updatedAttended =
          (int.tryParse(attendedCtrl.text.trim()) ?? baseline.classesAttended).clamp(0, updatedHeld);

      setState(() {
        _computedBaselines[subjectId] = ParsedSubjectAttendanceBaseline(
          subject: baseline.subject,
          classesHeld: updatedHeld,
          classesAttended: updatedAttended,
        );
      });
    }
  }

  Future<void> _importAttendance() async {
    if (_computedBaselines.isEmpty && (_parsedResult == null || _parsedResult!.items.isEmpty)) {
      SnackbarUtils.showErrorSnackBar(context, 'No valid attendance data to import.');
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      final now = DateTime.now();
      final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
      final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);

      if (_applyAsBaseline || _parsedResult!.items.isEmpty) {
        // Apply as Manual Attendance Baseline
        for (final baseline in _computedBaselines.values) {
          await subjectProvider.updateManualAttendanceCounts(
            subjectId: baseline.subject.id,
            classesHeld: baseline.classesHeld,
            classesAttended: baseline.classesAttended,
            effectiveFrom: DateTime(now.year, now.month, now.day),
          );
        }
      } else {
        // Apply as individual granular records
        final records = _parsedResult!.matchedItems.map((i) => i.toAttendance()).toList();
        await attendanceProvider.markMultipleAttendance(records);
      }

      await BackupService().notifyDataChanged();

      if (!mounted) return;

      SnackbarUtils.showSuccessSnackBar(
        context,
        _applyAsBaseline
            ? 'Manual attendance baseline updated for ${_computedBaselines.length} subject(s).'
            : 'Successfully imported ${_parsedResult!.matchedItems.length} attendance record(s).',
      );

      _clearText();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showErrorSnackBar(context, 'Import failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  void _showSampleFormatDialog() {
    showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 5,
        child: AlertDialog(
          title: const Text('Attendance Import Formats'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: 'AI Prompt (Recommended)'),
                    Tab(text: 'Summary JSON'),
                    Tab(text: 'Summary CSV'),
                    Tab(text: 'JSON Logs'),
                    Tab(text: 'CSV Logs'),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 250,
                  child: TabBarView(
                    children: [
                      _buildTemplateView(AttendanceImportUtils.attendanceAiPrompt, 'AI Prompt'),
                      _buildTemplateView(AttendanceImportUtils.sampleSummaryJsonTemplate, 'Summary JSON'),
                      _buildTemplateView(AttendanceImportUtils.sampleSummaryCsvTemplate, 'Summary CSV'),
                      _buildTemplateView(AttendanceImportUtils.sampleJsonTemplate, 'JSON Logs'),
                      _buildTemplateView(AttendanceImportUtils.sampleCsvTemplate, 'CSV Logs'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateView(String template, String formatName) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                template,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: template));
            SnackbarUtils.showSuccessSnackBar(context, '$formatName copied to clipboard.');
          },
          icon: const Icon(Icons.copy, size: 14),
          label: Text('Copy $formatName'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rs = context.rs;
    final isDarkMode = theme.brightness == Brightness.dark;

    final bodyContent = SingleChildScrollView(
      padding: rs.insetsAll(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header & File Upload action
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Attendance Data (JSON / CSV)',
                style: TextStyle(
                  fontSize: rs.font(13.5),
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              TextButton.icon(
                onPressed: _handleFileImport,
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: const Text('Upload File', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Text Input with Embedded Dynamic In-Box Paste / Clear Button
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _textController,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;

              return Stack(
                children: [
                  TextFormField(
                    controller: _textController,
                    minLines: 8,
                    maxLines: 16,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'Paste JSON or CSV text here...\n[\n  {\n    "subject": "Mathematics",\n    "held": 24,\n    "attended": 20\n  }\n]',
                      hintStyle: TextStyle(fontSize: 11, color: theme.hintColor),
                      filled: true,
                      fillColor: isDarkMode
                          ? Colors.black.withValues(alpha: 0.25)
                          : Colors.grey.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.fromLTRB(14, 14, 80, 14),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: hasText ? _clearText : _pasteFromClipboard,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasText ? Icons.close_rounded : Icons.content_paste_rounded,
                                size: 14,
                                color: hasText ? colorScheme.error : colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hasText ? 'Clear' : 'Paste',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: hasText ? colorScheme.error : colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // Bottom Actions (View Format & Parse & Preview)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showSampleFormatDialog,
                  icon: const Icon(Icons.help_outline, size: 16),
                  label: const Text(
                    'View Format',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _processAttendanceContent(_textController.text),
                  icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                  label: const Text(
                    'Parse & Preview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),

          // Error Message Card
          if (_errorMessage != null) ...[
            SizedBox(height: rs.height(14)),
            _buildErrorMessageCard(context, rs),
          ],

          // Preview Section
          if (_computedBaselines.isNotEmpty || (_parsedResult != null && _parsedResult!.items.isNotEmpty)) ...[
            SizedBox(height: rs.height(20)),
            _buildPreviewSection(context, rs),
          ],

          SizedBox(height: rs.height(16)),
        ],
      ),
    );

    if (widget.embedInUnifiedImport) {
      return bodyContent;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Previous Attendance'),
        centerTitle: true,
      ),
      body: bodyContent,
    );
  }

  Widget _buildErrorMessageCard(BuildContext context, ResponsiveScale rs) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(rs.scale(14)),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(rs.scale(14)),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: theme.colorScheme.error,
            size: rs.scale(20),
          ),
          SizedBox(width: rs.width(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Parsing Error',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: rs.font(13.5),
                    color: theme.colorScheme.error,
                  ),
                ),
                SizedBox(height: rs.height(3)),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    fontSize: rs.font(12),
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSection(BuildContext context, ResponsiveScale rs) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final subjectCount = _computedBaselines.length;
    final hasLogs = _parsedResult != null && _parsedResult!.items.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Text(
              'Import Preview',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: rs.font(16),
                color: theme.colorScheme.onSurface,
              ),
            ),
            SizedBox(width: rs.width(8)),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: rs.width(8),
                vertical: rs.height(2),
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(rs.scale(10)),
              ),
              child: Text(
                '$subjectCount subjects',
                style: TextStyle(
                  fontSize: rs.font(11),
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: rs.height(12)),

        // Mode selector if granular items exist
        if (hasLogs) ...[
          Container(
            padding: EdgeInsets.all(rs.scale(14)),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(rs.scale(16)),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.12),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: rs.width(4), bottom: rs.height(10)),
                  child: Text(
                    'Import Target Mode',
                    style: TextStyle(
                      fontSize: rs.font(13),
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment<bool>(
                        value: true,
                        label: Text('Manual Baseline', style: TextStyle(fontSize: rs.font(12), fontWeight: FontWeight.w600)),
                        icon: Icon(Icons.tune_rounded, size: rs.scale(18)),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        label: Text('Class Logs (${_parsedResult!.matchedItems.length})', style: TextStyle(fontSize: rs.font(12), fontWeight: FontWeight.w600)),
                        icon: Icon(Icons.history_rounded, size: rs.scale(18)),
                      ),
                    ],
                    selected: <bool>{_applyAsBaseline},
                    style: ButtonStyle(
                      shape: WidgetStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(rs.scale(12)),
                        ),
                      ),
                    ),
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      setState(() {
                        _applyAsBaseline = selection.first;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: rs.height(12)),
        ],

        // Unmatched Subjects Warning Box
        if (_parsedResult != null && _parsedResult!.unmatchedSubjectNames.isNotEmpty) ...[
          Container(
            margin: EdgeInsets.only(bottom: rs.height(12)),
            padding: EdgeInsets.all(rs.scale(12)),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(rs.scale(12)),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700, size: rs.scale(18)),
                SizedBox(width: rs.width(8)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unmatched Subjects (${_parsedResult!.unmatchedSubjectNames.length})',
                        style: TextStyle(
                          fontSize: rs.font(12.5),
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade800,
                        ),
                      ),
                      SizedBox(height: rs.height(2)),
                      Text(
                        'The following subjects in the imported data could not be mapped to any existing subject: '
                        '${_parsedResult!.unmatchedSubjectNames.join(", ")}',
                        style: TextStyle(
                          fontSize: rs.font(11),
                          color: isDarkMode ? Colors.amber.shade200 : Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Subject comparison / baseline cards
        ..._computedBaselines.entries.map((entry) {
          final subjectId = entry.key;
          final baseline = entry.value;
          final sub = baseline.subject;

          final manual = sub.manualAttendanceOverride;
          int prevHeld = manual?.classesHeld ?? 0;
          int prevAttended = manual?.classesAttended ?? 0;

          if (manual == null) {
            final attProvider = Provider.of<AttendanceProvider>(context, listen: false);
            final records = attProvider.attendanceRecords.where((r) => r.subjectId == sub.id).toList();
            prevAttended = records.where((r) => r.status.name == 'attended').length;
            final absent = records.where((r) => r.status.name == 'absent').length;
            prevHeld = prevAttended + absent;
          }

          final prevPct = prevHeld > 0 ? (prevAttended / prevHeld) * 100 : 0.0;

          final newHeld = baseline.classesHeld;
          final newAttended = baseline.classesAttended;
          final newPct = baseline.percentage;

          final pctDiff = newPct - prevPct;

          return Container(
            margin: EdgeInsets.only(bottom: rs.height(10)),
            padding: EdgeInsets.all(rs.scale(14)),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(rs.scale(16)),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.12),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject name row with color dot and edit button
                Row(
                  children: [
                    Container(
                      width: rs.scale(14),
                      height: rs.scale(14),
                      decoration: BoxDecoration(
                        color: sub.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: rs.width(8)),
                    Expanded(
                      child: Text(
                        sub.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: rs.font(14.5),
                        ),
                      ),
                    ),
                    if (sub.acronym != null && sub.acronym!.isNotEmpty) ...[
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: rs.width(6),
                          vertical: rs.height(2),
                        ),
                        decoration: BoxDecoration(
                          color: sub.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(rs.scale(6)),
                        ),
                        child: Text(
                          sub.acronym!,
                          style: TextStyle(
                            fontSize: rs.font(10.5),
                            fontWeight: FontWeight.bold,
                            color: sub.color,
                          ),
                        ),
                      ),
                      SizedBox(width: rs.width(6)),
                    ],
                    InkWell(
                      borderRadius: BorderRadius.circular(rs.scale(6)),
                      onTap: () => _editSubjectAttendance(subjectId, baseline),
                      child: Container(
                        padding: EdgeInsets.all(rs.scale(4)),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(rs.scale(6)),
                          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                        ),
                        child: Tooltip(
                          message: 'Edit Attendance',
                          child: Icon(Icons.edit_outlined, size: rs.scale(15), color: theme.colorScheme.primary),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: rs.height(10)),

                // Previous vs Updated Comparison Table / Row
                Container(
                  padding: EdgeInsets.all(rs.scale(10)),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.black.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(rs.scale(10)),
                  ),
                  child: Row(
                    children: [
                      // Previous Attendance
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current',
                              style: TextStyle(
                                fontSize: rs.font(11),
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: rs.height(2)),
                            Text(
                              '$prevAttended / $prevHeld classes',
                              style: TextStyle(
                                fontSize: rs.font(12),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${prevPct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: rs.font(11),
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded, size: rs.scale(16), color: theme.colorScheme.outline),
                      SizedBox(width: rs.width(8)),
                      // Updated Attendance
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Imported',
                              style: TextStyle(
                                fontSize: rs.font(11),
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: rs.height(2)),
                            Text(
                              '$newAttended / $newHeld classes',
                              style: TextStyle(
                                fontSize: rs.font(12),
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '${newPct.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: rs.font(11),
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                if (pctDiff.abs() >= 0.1) ...[
                                  SizedBox(width: rs.width(4)),
                                  Text(
                                    '(${pctDiff >= 0 ? '+' : ''}${pctDiff.toStringAsFixed(1)}%)',
                                    style: TextStyle(
                                      fontSize: rs.font(10),
                                      fontWeight: FontWeight.w600,
                                      color: pctDiff >= 0 ? Colors.green : Colors.red,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),

        SizedBox(height: rs.height(14)),

        // Bottom Confirm & Apply Button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isImporting ? null : _importAttendance,
            icon: _isImporting
                ? SizedBox(
                    width: rs.scale(18),
                    height: rs.scale(18),
                    child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(Icons.check_circle_outline_rounded, size: rs.scale(20)),
            label: Text(
              _isImporting
                  ? 'Applying...'
                  : _applyAsBaseline
                      ? 'Confirm & Apply Baseline ($subjectCount Subjects)'
                      : 'Confirm & Import (${_parsedResult?.matchedItems.length ?? 0} Records)',
              style: TextStyle(
                fontSize: rs.font(14),
                fontWeight: FontWeight.bold,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: rs.height(14)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(rs.scale(12)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
