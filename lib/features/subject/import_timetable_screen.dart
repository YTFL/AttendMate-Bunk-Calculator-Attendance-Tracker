import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_utils.dart';
import '../../utils/timetable_export_utils.dart';
import '../../utils/timetable_import_utils.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';

class ImportTimetableScreen extends StatefulWidget {
  const ImportTimetableScreen({super.key});

  @override
  State<ImportTimetableScreen> createState() => _ImportTimetableScreenState();
}

class _ImportTimetableScreenState extends State<ImportTimetableScreen> {
  static const MethodChannel _fileImportChannel = MethodChannel('com.attendmate.app/file_import');

  final _inputTextController = TextEditingController();
  String? _errorMessage;
  List<Subject>? _importedSubjects;
  List<_MidSemesterChangePreview> _midSemesterChanges = [];
  bool _isMidSemesterUpdate = true;
  late DateTime _effectiveFromDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _effectiveFromDate = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _inputTextController.dispose();
    super.dispose();
  }

  void _parseAndValidateInput() {
    final inputText = _inputTextController.text.trim();
    
    if (inputText.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter or paste JSON or CSV data';
        _importedSubjects = null;
      });
      return;
    }

    try {
      final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
      final usedColors = subjectProvider.subjects.map((s) => s.color).toSet();
      
      final subjects = TimetableImportUtils.parseInputToSubjects(inputText, usedColors);
      final midSemesterChanges = _isMidSemesterUpdate
          ? _buildMidSemesterChangePreview(subjects)
          : <_MidSemesterChangePreview>[];
      
      setState(() {
        _importedSubjects = subjects;
        _midSemesterChanges = midSemesterChanges;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _importedSubjects = null;
        _midSemesterChanges = [];
      });
    }
  }

  Future<void> _importSubjects() async {
    if (_importedSubjects == null || _importedSubjects!.isEmpty) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('No valid subjects to import'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);

    if (_isMidSemesterUpdate) {
      final result = await subjectProvider.applyTimetableUpdateFromDate(
        _importedSubjects!,
        _effectiveFromDate,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text(
            'Updated from ${_formatDate(_effectiveFromDate)}: '
            '${result.matchedSubjects} matched, '
            '${result.newSubjects} new, '
            '${result.retiredSubjects} retired.',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      await subjectProvider.bulkImportSubjects(_importedSubjects!);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text('Successfully imported ${_importedSubjects!.length} subject(s)'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    if (!mounted) {
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _pickEffectiveFromDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _effectiveFromDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Apply updated timetable from',
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _effectiveFromDate = DateTime(selected.year, selected.month, selected.day);
      if (_isMidSemesterUpdate && _importedSubjects != null) {
        _midSemesterChanges = _buildMidSemesterChangePreview(_importedSubjects!);
      }
    });
  }

  List<_MidSemesterChangePreview> _buildMidSemesterChangePreview(
    List<Subject> importedSubjects,
  ) {
    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
    final existingSubjects = List<Subject>.from(subjectProvider.subjects);
    final matchedExistingIds = <String>{};
    final changes = <_MidSemesterChangePreview>[];
    final effectiveDate = DateTime(
      _effectiveFromDate.year,
      _effectiveFromDate.month,
      _effectiveFromDate.day,
    );

    for (final imported in importedSubjects) {
      final existingIndex = _findMatchingExistingSubjectIndex(
        existingSubjects: existingSubjects,
        importedSubject: imported,
        matchedExistingIds: matchedExistingIds,
      );

      final afterSlots = _normalizedWeeklySlots(imported.schedule);

      if (existingIndex == -1) {
        if (afterSlots.isNotEmpty) {
          changes.add(
            _MidSemesterChangePreview(
              heading: imported.name,
              beforeSlots: const <TimeSlot>[],
              afterSlots: afterSlots,
              kind: _MidSemesterChangeKind.added,
            ),
          );
        }
        continue;
      }

      final existing = existingSubjects[existingIndex];
      matchedExistingIds.add(existing.id);
      final beforeSlots = _futureWeeklySlots(existing, effectiveDate);

      if (!_slotListsEqual(beforeSlots, afterSlots)) {
        changes.add(
          _MidSemesterChangePreview(
            heading: imported.name,
            beforeSlots: beforeSlots,
            afterSlots: afterSlots,
            kind: _MidSemesterChangeKind.updated,
          ),
        );
      }
    }

    for (final existing in existingSubjects) {
      if (matchedExistingIds.contains(existing.id)) {
        continue;
      }

      final beforeSlots = _futureWeeklySlots(existing, effectiveDate);
      if (beforeSlots.isEmpty) {
        continue;
      }

      changes.add(
        _MidSemesterChangePreview(
          heading: existing.name,
          beforeSlots: beforeSlots,
          afterSlots: const <TimeSlot>[],
          kind: _MidSemesterChangeKind.retired,
        ),
      );
    }

    return changes;
  }

  int _findMatchingExistingSubjectIndex({
    required List<Subject> existingSubjects,
    required Subject importedSubject,
    required Set<String> matchedExistingIds,
  }) {
    final importedAcronym = (importedSubject.acronym ?? '').trim().toLowerCase();
    if (importedAcronym.isNotEmpty) {
      final byAcronym = existingSubjects.indexWhere(
        (existing) =>
            !matchedExistingIds.contains(existing.id) &&
            (existing.acronym ?? '').trim().toLowerCase() == importedAcronym,
      );
      if (byAcronym != -1) {
        return byAcronym;
      }
    }

    final importedName = importedSubject.name.trim().toLowerCase();
    return existingSubjects.indexWhere(
      (existing) =>
          !matchedExistingIds.contains(existing.id) &&
          existing.name.trim().toLowerCase() == importedName,
    );
  }

  List<TimeSlot> _futureWeeklySlots(Subject subject, DateTime fromDate) {
    final weekly = subject.schedule.where((slot) => !slot.isSpecialClass).where((slot) {
      final until = normalizeDate(slot.effectiveUntil);
      return until == null || !until.isBefore(fromDate);
    }).toList();
    return _normalizedWeeklySlots(weekly);
  }

  List<TimeSlot> _normalizedWeeklySlots(List<TimeSlot> slots) {
    final unique = <String, TimeSlot>{};
    for (final slot in slots) {
      if (slot.isSpecialClass) {
        continue;
      }
      final key =
          '${slot.day.index}-${slot.startTime.hour}:${slot.startTime.minute}-${slot.endTime.hour}:${slot.endTime.minute}';
      unique[key] = TimeSlot(
        day: slot.day,
        startTime: slot.startTime,
        endTime: slot.endTime,
      );
    }

    final normalized = unique.values.toList();
    normalized.sort((a, b) {
      final dayCompare = a.day.index.compareTo(b.day.index);
      if (dayCompare != 0) {
        return dayCompare;
      }
      final aStart = a.startTime.hour * 60 + a.startTime.minute;
      final bStart = b.startTime.hour * 60 + b.startTime.minute;
      if (aStart != bStart) {
        return aStart.compareTo(bStart);
      }
      final aEnd = a.endTime.hour * 60 + a.endTime.minute;
      final bEnd = b.endTime.hour * 60 + b.endTime.minute;
      return aEnd.compareTo(bEnd);
    });

    return normalized;
  }

  bool _slotListsEqual(List<TimeSlot> a, List<TimeSlot> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.day != right.day ||
          left.startTime.hour != right.startTime.hour ||
          left.startTime.minute != right.startTime.minute ||
          left.endTime.hour != right.endTime.hour ||
          left.endTime.minute != right.endTime.minute) {
        return false;
      }
    }
    return true;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  void _copyJsonTemplate() {
    final formatRef = _getJsonFormatReference();
    Clipboard.setData(ClipboardData(text: formatRef));
    
    ScaffoldMessenger.of(context).showReplacingSnackBar(
      const SnackBar(
        content: Text('JSON format reference copied to clipboard'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _copyCsvTemplate() {
    final formatRef = _getCsvFormatReference();
    Clipboard.setData(ClipboardData(text: formatRef));

    ScaffoldMessenger.of(context).showReplacingSnackBar(
      const SnackBar(
        content: Text('CSV format reference copied to clipboard'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _clearInput() {
    setState(() {
      _inputTextController.clear();
      _errorMessage = null;
      _importedSubjects = null;
      _midSemesterChanges = [];
    });
  }

  Future<void> _pickAndLoadImportFile() async {
    try {
      final result = await _fileImportChannel.invokeMethod<dynamic>('pickImportFile');
      if (result == null) {
        return;
      }
      if (result is! Map) {
        throw Exception('Invalid file picker response.');
      }

      final fileName = result['name']?.toString() ?? 'import_file';
      final bytesDynamic = result['bytes'];
      final bytes = _coerceFileBytes(bytesDynamic);
      if (bytes.isEmpty) {
        throw Exception('Selected file is empty or unreadable.');
      }

      final content = _decodeImportFileBytes(bytes);

      final fileNameLower = fileName.toLowerCase();
      final isSupported = fileNameLower.endsWith('.json') || fileNameLower.endsWith('.csv');
      if (!isSupported) {
        throw Exception('Only .json and .csv files are supported.');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _inputTextController.text = content;
        _errorMessage = null;
        _importedSubjects = null;
      });

      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text('Loaded file: $fileName'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } on MissingPluginException {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('File import is available only in Android builds. Please run on Android and restart the app.'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text('Failed to upload file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _decodeImportFileBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  List<int> _coerceFileBytes(dynamic rawBytes) {
    if (rawBytes is Uint8List) {
      return rawBytes;
    }
    if (rawBytes is List) {
      return rawBytes.whereType<int>().toList();
    }
    return const <int>[];
  }

  void _exportAsJson() {
    final subjects = Provider.of<SubjectProvider>(context, listen: false).subjects;
    
    if (subjects.isEmpty) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('No subjects to export'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _performAsyncExport(
      onExport: () => TimetableExportUtils.exportAsJsonFile(subjects),
      label: 'JSON',
    );
  }

  void _exportAsCSV() {
    final subjects = Provider.of<SubjectProvider>(context, listen: false).subjects;
    
    if (subjects.isEmpty) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('No subjects to export'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _performAsyncExport(
      onExport: () => TimetableExportUtils.exportAsCsvFile(subjects),
      label: 'CSV',
    );
  }

  Future<void> _exportAsPDF() async {
    final subjects = Provider.of<SubjectProvider>(context, listen: false).subjects;
    
    if (subjects.isEmpty) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('No subjects to export'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await _performAsyncExport(
      onExport: () => TimetableExportUtils.exportAsPDF(subjects),
      label: 'PDF',
      shouldOpen: true,
    );
  }

  Future<void> _performAsyncExport({
    required Future<dynamic> Function() onExport,
    required String label,
    bool shouldOpen = false,
  }) async {
    try {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text('Saving $label file...'),
          duration: const Duration(seconds: 1),
        ),
      );

      final file = await onExport();
      
      if (mounted) {
        final fileName = file.path.split('/').last;
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text('$label saved: $fileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
            action: shouldOpen ? SnackBarAction(
              label: 'Open',
              onPressed: () async {
                await OpenFilex.open(file.path);
              },
            ) : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Import Timetable'),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'json') {
                  _exportAsJson();
                } else if (value == 'csv') {
                  _exportAsCSV();
                } else if (value == 'pdf') {
                  _exportAsPDF();
                }
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
                  value: 'json',
                  child: Row(
                    children: [
                      Icon(Icons.data_object, size: 18),
                      SizedBox(width: 12),
                      Text('Export as JSON'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'csv',
                  child: Row(
                    children: [
                      Icon(Icons.table_chart, size: 18),
                      SizedBox(width: 12),
                      Text('Export as CSV'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'pdf',
                  child: Row(
                    children: [
                      Icon(Icons.picture_as_pdf, size: 18),
                      SizedBox(width: 12),
                      Text('Export as PDF'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Instructions
                Card(
                  color: Colors.blue.withAlpha(25),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              'Import Instructions',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Paste valid JSON or CSV data, or use the import icon inside the text box to load a file. '
                          'Use "Update Mid-Semester" to apply a new timetable from a selected date '
                          'while keeping all classes before that date unchanged.',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _copyJsonTemplate,
                                icon: const Icon(Icons.content_copy, size: 18),
                                label: const Text('Copy JSON Reference'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _copyCsvTemplate,
                                icon: const Icon(Icons.table_chart, size: 18),
                                label: const Text('Copy CSV Reference'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Update Mid-Semester'),
                      icon: Icon(Icons.update),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Add As New Subjects'),
                      icon: Icon(Icons.playlist_add),
                    ),
                  ],
                  selected: <bool>{_isMidSemesterUpdate},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) {
                      return;
                    }
                    setState(() {
                      _isMidSemesterUpdate = selection.first;
                      if (_isMidSemesterUpdate && _importedSubjects != null) {
                        _midSemesterChanges =
                            _buildMidSemesterChangePreview(_importedSubjects!);
                      } else {
                        _midSemesterChanges = [];
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),

                if (_isMidSemesterUpdate)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.event_available),
                      title: const Text('Apply Updated Timetable From'),
                      subtitle: Text(
                        '${_formatDate(_effectiveFromDate)}\n'
                        'Classes before this date remain locked to the old timetable.',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.edit_calendar),
                      onTap: _pickEffectiveFromDate,
                    ),
                  ),
                if (_isMidSemesterUpdate) const SizedBox(height: 12),

                // JSON/CSV Input
                TextFormField(
                  controller: _inputTextController,
                  minLines: 12,
                  maxLines: 20,
                  decoration: InputDecoration(
                    labelText: 'JSON or CSV Data',
                    hintText: 'Paste your JSON or CSV data here...',
                    suffixIcon: IconButton(
                      tooltip: 'Import .json/.csv file',
                      onPressed: _pickAndLoadImportFile,
                      icon: const Icon(Icons.upload_file),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey.withValues(alpha: 0.1),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 12),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _parseAndValidateInput,
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Parse & Preview'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _clearInput,
                      icon: const Icon(Icons.clear, size: 18),
                      label: const Text('Clear'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Error Message
                if (_errorMessage != null)
                  Card(
                    color: Colors.red.withAlpha(25),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Error',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Preview
                if (_importedSubjects != null && _importedSubjects!.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        _isMidSemesterUpdate
                            ? 'Changed Slots Preview'
                            : 'Preview',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_isMidSemesterUpdate && _midSemesterChanges.isEmpty)
                        Card(
                          color: Colors.blue.withAlpha(20),
                          child: const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: Text(
                              'No slot changes detected from the selected date.\n'
                              'Only changed slots are shown in this mode.',
                            ),
                          ),
                        ),
                      if (_isMidSemesterUpdate)
                        ..._midSemesterChanges.map((change) {
                          final kindLabel = switch (change.kind) {
                            _MidSemesterChangeKind.added => 'Added',
                            _MidSemesterChangeKind.updated => 'Updated',
                            _MidSemesterChangeKind.retired => 'Retired',
                          };

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          change.heading,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Chip(
                                        label: Text(kindLabel),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Before',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 6),
                                  _buildSlotWrap(change.beforeSlots),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'After',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 6),
                                  _buildSlotWrap(change.afterSlots),
                                ],
                              ),
                            ),
                          );
                        }),
                      if (!_isMidSemesterUpdate)
                        ..._importedSubjects!.map((subject) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: subject.color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          subject.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: subject.schedule.map((slot) {
                                      return Chip(
                                        label: Text(
                                          '${slot.day.name.substring(0, 3).toUpperCase()}: ${slot.startTime.format(context)} - ${slot.endTime.format(context)}',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        backgroundColor: subject.color.withAlpha(50),
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        visualDensity: VisualDensity.compact,
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _importSubjects(),
                          icon: const Icon(Icons.download, size: 18),
                          label: Text(
                            _isMidSemesterUpdate
                                ? 'Update From ${_formatDate(_effectiveFromDate)}'
                                : 'Import ${_importedSubjects!.length} Subject(s)',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),

                // Format Help
                const SizedBox(height: 24),
                ExpansionTile(
                  title: const Text('JSON Format Reference'),
                  children: [
                    Container(
                        color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.grey.withValues(alpha: 0.1),
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          _getJsonFormatReference(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  title: const Text('CSV Format Reference'),
                  children: [
                    Container(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.grey.withValues(alpha: 0.1),
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          _getCsvFormatReference(),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getJsonFormatReference() {
    return '''{
  "subjects": [
    {
      "name": "Mathematics",
      "acronym": "MTH",
      "schedule": [
        {
          "day": "monday",
          "startTime": "09:00",
          "endTime": "10:30"
        },
        {
          "day": "wednesday",
          "startTime": "14:00",
          "endTime": "15:30"
        }
      ]
    },
    {
      "name": "Physics",
      "acronym": "PHY",
      "schedule": [
        {
          "day": "tuesday",
          "startTime": "09:00",
          "endTime": "10:30"
        }
      ]
    }
  ]
}''';
  }

  String _getCsvFormatReference() {
    return TimetableImportUtils.generateTemplateCsv();
  }

  Widget _buildSlotWrap(List<TimeSlot> slots) {
    if (slots.isEmpty) {
      return const Text(
        'No slots',
        style: TextStyle(color: Colors.grey),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: slots.map((slot) {
        return Chip(
          label: Text(
            '${slot.day.name.substring(0, 3).toUpperCase()}: ${slot.startTime.format(context)} - ${slot.endTime.format(context)}',
            style: const TextStyle(fontSize: 11),
          ),
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }
}

enum _MidSemesterChangeKind {
  added,
  updated,
  retired,
}

class _MidSemesterChangePreview {
  final String heading;
  final List<TimeSlot> beforeSlots;
  final List<TimeSlot> afterSlots;
  final _MidSemesterChangeKind kind;

  const _MidSemesterChangePreview({
    required this.heading,
    required this.beforeSlots,
    required this.afterSlots,
    required this.kind,
  });
}
