import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../services/semester_share_service.dart';
import '../../utils/error_utils.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/timetable_export_utils.dart';
import '../../utils/timetable_import_utils.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_overlay.dart';

class ImportTimetableScreen extends StatefulWidget {
  final String? initialText;
  final bool embedInUnifiedImport;

  const ImportTimetableScreen({
    super.key,
    this.initialText,
    this.embedInUnifiedImport = false,
  });

  @override
  State<ImportTimetableScreen> createState() => _ImportTimetableScreenState();
}

class _ImportTimetableScreenState extends State<ImportTimetableScreen> {
  static const MethodChannel _fileImportChannel = MethodChannel('com.attendmate.app/file_import');

  final _inputTextController = TextEditingController();
  final GlobalKey _importInputKey = GlobalKey();
  final GlobalKey _exportMenuKey = GlobalKey();
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

    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
    if (subjectProvider.subjects.isEmpty) {
      _isMidSemesterUpdate = false;
    }

    if (widget.initialText != null && widget.initialText!.trim().isNotEmpty) {
      _inputTextController.text = widget.initialText!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _parseAndValidateInput();
        }
      });
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
    if (tutorialController.isActive && (tutorialController.currentStepIndex < 11 || tutorialController.currentStepIndex >= 13)) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    try {
      final tutorialController = Provider.of<TutorialController>(context, listen: false);
      tutorialController.removeListener(_onTutorialStepChanged);
    } catch (_) {}
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
      final decoded = jsonDecode(inputText);
      if (decoded is Map<String, dynamic>) {
        final type = SemesterShareService().detectFileType(decoded);
        if (type == ImportFileType.semesterShare || type == ImportFileType.fullBackup) {
          SemesterShareService().processOpenedJsonContent(inputText, context);
          return;
        }
      }
    } catch (_) {}

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
            '${result.newSubjects} new'
            '${result.retiredSubjects > 0 ? ', ${result.retiredSubjects} retired' : ''}.',
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

  Future<void> _editImportedSubject(Subject subject) async {
    final nameCtrl = TextEditingController(text: subject.name);
    final acronymCtrl = TextEditingController(text: subject.acronym ?? '');
    final targetCtrl = TextEditingController(text: '${subject.targetAttendance}');
    final colorScheme = Theme.of(context).colorScheme;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Edit Subject Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Subject Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: acronymCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Acronym / Code (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: targetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Target Attendance (%)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isNotEmpty) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (updated == true && mounted) {
      final newName = nameCtrl.text.trim();
      final newAcronym = acronymCtrl.text.trim().isEmpty ? null : acronymCtrl.text.trim();
      final newTarget = int.tryParse(targetCtrl.text.trim()) ?? subject.targetAttendance;

      setState(() {
        if (_importedSubjects != null) {
          final index = _importedSubjects!.indexWhere((s) => s.id == subject.id);
          if (index != -1) {
            _importedSubjects![index] = _importedSubjects![index].copyWith(
              name: newName,
              acronym: newAcronym,
              targetAttendance: newTarget,
            );
          } else {
            // Match by name
            final nameIdx = _importedSubjects!.indexWhere((s) => s.name == subject.name);
            if (nameIdx != -1) {
              _importedSubjects![nameIdx] = _importedSubjects![nameIdx].copyWith(
                name: newName,
                acronym: newAcronym,
                targetAttendance: newTarget,
              );
            }
          }
          if (_isMidSemesterUpdate) {
            _midSemesterChanges = _buildMidSemesterChangePreview(_importedSubjects!);
          }
        }
      });
    }
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
              subject: imported,
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
            subject: imported,
          ),
        );
      }
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

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(content: Text('Clipboard is empty')),
        );
      }
      return;
    }
    setState(() {
      _inputTextController.text = text;
      _errorMessage = null;
      _importedSubjects = null;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('Pasted from clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _showSampleFormatDialog() {
    showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 3,
        child: AlertDialog(
          title: const Text('Timetable Import Formats'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    Tab(text: 'JSON Format'),
                    Tab(text: 'CSV Format'),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 250,
                  child: TabBarView(
                    children: [
                      _buildTemplateView(TimetableImportUtils.timetableAiPrompt, 'AI Prompt'),
                      _buildTemplateView(_getJsonFormatReference(), 'JSON'),
                      _buildTemplateView(_getCsvFormatReference(), 'CSV'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
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
            ScaffoldMessenger.of(context).showReplacingSnackBar(
              SnackBar(
                content: Text('$formatName template copied to clipboard'),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 2),
              ),
            );
          },
          icon: const Icon(Icons.copy, size: 14),
          label: Text('Copy $formatName Template'),
        ),
      ],
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

      try {
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          final type = SemesterShareService().detectFileType(decoded);
          if (type == ImportFileType.semesterShare || type == ImportFileType.fullBackup) {
            await SemesterShareService().processOpenedJsonContent(content, context);
            return;
          }
        }
      } catch (_) {}

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
      if (isUserCancellation(e)) {
        return;
      }

      ScaffoldMessenger.of(context).showReplacingSnackBar(
        SnackBar(
          content: Text(formatUserFriendlyErrorMessage(e, defaultPrefix: 'Failed to upload file')),
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
    final rs = context.rs;
    final theme = Theme.of(context);

    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    tutorialController.registerKey('key_export_menu', _exportMenuKey);
    tutorialController.registerKey('key_import_input', _importInputKey);

    final content = SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(rs.scale(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mode Selector Section
          _buildModeSelectorCard(context, rs),

          SizedBox(height: rs.height(16)),

          // Effective Date Picker (Mid-Semester Mode)
          if (_isMidSemesterUpdate) ...[
            _buildEffectiveDatePickerCard(context, rs),
            SizedBox(height: rs.height(16)),
          ],

          // Data Input Section
          _buildDataInputSection(context, rs),

          SizedBox(height: rs.height(16)),

          // Parse & Clear Actions
          _buildParseActionsRow(context, rs),

          // Error Message Card
          if (_errorMessage != null) ...[
            SizedBox(height: rs.height(14)),
            _buildErrorMessageCard(context, rs),
          ],

          // Preview Section
          if (_importedSubjects != null && _importedSubjects!.isNotEmpty) ...[
            SizedBox(height: rs.height(20)),
            _buildPreviewSection(context, rs),
          ],

          SizedBox(height: rs.height(16)),
        ],
      ),
    );

    if (widget.embedInUnifiedImport) {
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: content,
      );
    }

    return TutorialOverlay(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              'Import & Export Timetable',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: rs.font(18),
              ),
            ),
            elevation: 0,
            actions: [
              KeyedSubtree(
                key: _exportMenuKey,
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.ios_share_rounded, size: rs.scale(22)),
                  tooltip: 'Export Options',
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
                    PopupMenuItem<String>(
                      value: 'json',
                      child: Row(
                        children: [
                          Icon(Icons.data_object_rounded, size: rs.scale(18), color: theme.colorScheme.primary),
                          SizedBox(width: rs.width(12)),
                          Text('Export as JSON', style: TextStyle(fontSize: rs.font(13.5))),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'csv',
                      child: Row(
                        children: [
                          Icon(Icons.table_chart_rounded, size: rs.scale(18), color: Colors.teal),
                          SizedBox(width: rs.width(12)),
                          Text('Export as CSV', style: TextStyle(fontSize: rs.font(13.5))),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'pdf',
                      child: Row(
                        children: [
                          Icon(Icons.picture_as_pdf_rounded, size: rs.scale(18), color: Colors.redAccent),
                          SizedBox(width: rs.width(12)),
                          Text('Export as PDF', style: TextStyle(fontSize: rs.font(13.5))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: rs.width(4)),
            ],
          ),
          body: content,
        ),
      ),
    );
  }

  Widget _buildModeSelectorCard(BuildContext context, ResponsiveScale rs) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
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
              'Import Mode',
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
                  label: Text('Update Mid-Semester', style: TextStyle(fontSize: rs.font(12), fontWeight: FontWeight.w600)),
                  icon: Icon(Icons.update_rounded, size: rs.scale(18)),
                ),
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Add As New Subjects', style: TextStyle(fontSize: rs.font(12), fontWeight: FontWeight.w600)),
                  icon: Icon(Icons.playlist_add_rounded, size: rs.scale(18)),
                ),
              ],
              selected: <bool>{_isMidSemesterUpdate},
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
                  _isMidSemesterUpdate = selection.first;
                  if (_isMidSemesterUpdate && _importedSubjects != null) {
                    _midSemesterChanges = _buildMidSemesterChangePreview(_importedSubjects!);
                  } else {
                    _midSemesterChanges = [];
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEffectiveDatePickerCard(BuildContext context, ResponsiveScale rs) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(rs.scale(16)),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(rs.scale(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(rs.scale(16)),
          onTap: _pickEffectiveFromDate,
          child: Padding(
            padding: EdgeInsets.all(rs.scale(14)),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(rs.scale(10)),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(rs.scale(12)),
                  ),
                  child: Icon(
                    Icons.event_available_rounded,
                    color: theme.colorScheme.primary,
                    size: rs.scale(22),
                  ),
                ),
                SizedBox(width: rs.width(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Apply Updated Timetable From',
                        style: TextStyle(
                          fontSize: rs.font(13.5),
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: rs.height(3)),
                      Text(
                        'Classes prior to ${_formatDate(_effectiveFromDate)} remain locked to old schedule',
                        style: TextStyle(
                          fontSize: rs.font(11),
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: rs.width(8)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: rs.width(10),
                    vertical: rs.height(5),
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(rs.scale(10)),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatDate(_effectiveFromDate),
                        style: TextStyle(
                          fontSize: rs.font(11.5),
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      SizedBox(width: rs.width(4)),
                      Icon(
                        Icons.edit_calendar_rounded,
                        size: rs.scale(14),
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataInputSection(BuildContext context, ResponsiveScale rs) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Timetable Data (JSON / CSV)',
              style: TextStyle(
                fontSize: rs.font(13.5),
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            TextButton.icon(
              onPressed: _pickAndLoadImportFile,
              icon: Icon(Icons.upload_file_rounded, size: rs.scale(16)),
              label: Text(
                'Upload File',
                style: TextStyle(
                  fontSize: rs.font(12),
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: rs.width(8),
                  vertical: rs.height(4),
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        SizedBox(height: rs.height(6)),
        KeyedSubtree(
          key: _importInputKey,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _inputTextController,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              return Stack(
                children: [
                  TextFormField(
                    controller: _inputTextController,
                    minLines: 8,
                    maxLines: 16,
                    decoration: InputDecoration(
                      hintText: 'Paste your JSON or CSV text data here...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(rs.scale(14)),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.15),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(rs.scale(14)),
                        borderSide: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.15),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(rs.scale(14)),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: isDarkMode
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.grey.withValues(alpha: 0.06),
                      contentPadding: EdgeInsets.fromLTRB(rs.scale(14), rs.scale(14), rs.scale(85), rs.scale(14)),
                    ),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: rs.font(12),
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Positioned(
                    top: rs.scale(8),
                    right: rs.scale(8),
                    child: Material(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(rs.scale(8)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(rs.scale(8)),
                        onTap: hasText ? _clearInput : _pasteFromClipboard,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: rs.scale(8), vertical: rs.scale(5)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasText ? Icons.close_rounded : Icons.content_paste_rounded,
                                size: rs.scale(14),
                                color: hasText ? theme.colorScheme.error : theme.colorScheme.primary,
                              ),
                              SizedBox(width: rs.scale(4)),
                              Text(
                                hasText ? 'Clear' : 'Paste',
                                style: TextStyle(
                                  fontSize: rs.font(11),
                                  fontWeight: FontWeight.bold,
                                  color: hasText ? theme.colorScheme.error : theme.colorScheme.primary,
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
        ),
      ],
    );
  }

  Widget _buildParseActionsRow(BuildContext context, ResponsiveScale rs) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _showSampleFormatDialog,
            icon: Icon(Icons.help_outline_rounded, size: rs.scale(16)),
            label: Text(
              'View Format',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: rs.font(12), fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: rs.height(13)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(rs.scale(12)),
              ),
            ),
          ),
        ),
        SizedBox(width: rs.width(10)),
        Expanded(
          child: FilledButton.icon(
            onPressed: _parseAndValidateInput,
            icon: Icon(Icons.auto_fix_high_rounded, size: rs.scale(18)),
            label: Text(
              'Parse & Preview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: rs.font(13.5),
                fontWeight: FontWeight.bold,
              ),
            ),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: rs.height(13)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(rs.scale(12)),
              ),
            ),
          ),
        ),
      ],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _isMidSemesterUpdate ? 'Changed Slots Preview' : 'Import Preview',
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
                _isMidSemesterUpdate
                    ? '${_midSemesterChanges.length} changes'
                    : '${_importedSubjects!.length} subjects',
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
        if (_isMidSemesterUpdate && _midSemesterChanges.isEmpty)
          Container(
            padding: EdgeInsets.all(rs.scale(14)),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(rs.scale(14)),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Colors.blue, size: rs.scale(20)),
                SizedBox(width: rs.width(10)),
                Expanded(
                  child: Text(
                    'No slot changes detected from ${_formatDate(_effectiveFromDate)}.\n'
                    'Only modified or new slots are shown in this mode.',
                    style: TextStyle(fontSize: rs.font(12), color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
          ),
        if (_isMidSemesterUpdate)
          ..._midSemesterChanges.map((change) {
            final (kindLabel, kindColor) = switch (change.kind) {
              _MidSemesterChangeKind.added => ('Added', const Color(0xFF2E7D32)),
              _MidSemesterChangeKind.updated => ('Updated', const Color(0xFFED6C02)),
              _MidSemesterChangeKind.retired => ('Retired', const Color(0xFFD32F2F)),
            };

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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          change.heading,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: rs.font(14.5),
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: rs.width(8),
                          vertical: rs.height(3),
                        ),
                        decoration: BoxDecoration(
                          color: kindColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(rs.scale(8)),
                          border: Border.all(color: kindColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          kindLabel,
                          style: TextStyle(
                            fontSize: rs.font(11),
                            fontWeight: FontWeight.bold,
                            color: kindColor,
                          ),
                        ),
                      ),
                      SizedBox(width: rs.width(6)),
                      InkWell(
                        borderRadius: BorderRadius.circular(rs.scale(6)),
                        onTap: () => _editImportedSubject(change.subject),
                        child: Container(
                          padding: EdgeInsets.all(rs.scale(4)),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(rs.scale(6)),
                            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                          ),
                          child: Tooltip(
                            message: 'Edit Subject',
                            child: Icon(Icons.edit_outlined, size: rs.scale(15), color: theme.colorScheme.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: rs.height(8)),
                  Text(
                    'Previous Slots:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: rs.font(11.5),
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                  SizedBox(height: rs.height(4)),
                  _buildSlotWrap(change.beforeSlots, rs, context),
                  SizedBox(height: rs.height(8)),
                  Text(
                    'Updated Slots:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: rs.font(11.5),
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  SizedBox(height: rs.height(4)),
                  _buildSlotWrap(change.afterSlots, rs, context),
                ],
              ),
            );
          }),
        if (!_isMidSemesterUpdate)
          ..._importedSubjects!.map((subject) {
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
                  Row(
                    children: [
                      Container(
                        width: rs.scale(14),
                        height: rs.scale(14),
                        decoration: BoxDecoration(
                          color: subject.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: rs.width(8)),
                      Expanded(
                        child: Text(
                          subject.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: rs.font(14.5),
                          ),
                        ),
                      ),
                      if (subject.acronym != null && subject.acronym!.isNotEmpty) ...[
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: rs.width(6),
                            vertical: rs.height(2),
                          ),
                          decoration: BoxDecoration(
                            color: subject.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(rs.scale(6)),
                          ),
                          child: Text(
                            subject.acronym!,
                            style: TextStyle(
                              fontSize: rs.font(10.5),
                              fontWeight: FontWeight.bold,
                              color: subject.color,
                            ),
                          ),
                        ),
                        SizedBox(width: rs.width(6)),
                      ],
                      InkWell(
                        borderRadius: BorderRadius.circular(rs.scale(6)),
                        onTap: () => _editImportedSubject(subject),
                        child: Container(
                          padding: EdgeInsets.all(rs.scale(4)),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(rs.scale(6)),
                            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                          ),
                          child: Tooltip(
                            message: 'Edit Subject',
                            child: Icon(Icons.edit_outlined, size: rs.scale(15), color: theme.colorScheme.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: rs.height(8)),
                  Wrap(
                    spacing: rs.width(4),
                    runSpacing: rs.height(4),
                    children: subject.schedule.map((slot) {
                      return Chip(
                        label: Text(
                          '${slot.day.name.substring(0, 3).toUpperCase()}: ${slot.startTime.format(context)} - ${slot.endTime.format(context)}',
                          style: TextStyle(fontSize: rs.font(10.5)),
                        ),
                        backgroundColor: subject.color.withValues(alpha: 0.15),
                        padding: EdgeInsets.symmetric(horizontal: rs.width(4)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),
        SizedBox(height: rs.height(14)),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _importSubjects(),
            icon: Icon(Icons.check_circle_outline_rounded, size: rs.scale(20)),
            label: Text(
              _isMidSemesterUpdate
                  ? 'Apply Update From ${_formatDate(_effectiveFromDate)}'
                  : 'Import ${_importedSubjects!.length} Subject(s)',
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

  String _getJsonFormatReference() {
    return '''{
  "subjects": [
    {
      "name": "Mathematics",
      "acronym": "MTH",
      "room": "Room 101",
      "block": "Block A",
      "schedule": [
        {
          "day": "monday",
          "startTime": "09:00",
          "endTime": "10:30",
          "room": "Room 101",
          "block": "Block A"
        },
        {
          "day": "wednesday",
          "startTime": "14:00",
          "endTime": "15:30",
          "room": "Lab 2"
        }
      ]
    },
    {
      "name": "Physics",
      "acronym": "PHY",
      "room": "Hall 3",
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

  Widget _buildSlotWrap(List<TimeSlot> slots, ResponsiveScale rs, BuildContext context) {
    if (slots.isEmpty) {
      return Text(
        'No slots scheduled',
        style: TextStyle(
          color: Colors.grey,
          fontSize: rs.font(11.5),
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Wrap(
      spacing: rs.width(4),
      runSpacing: rs.height(4),
      children: slots.map((slot) {
        return Chip(
          label: Text(
            '${slot.day.name.substring(0, 3).toUpperCase()}: ${slot.startTime.format(context)} - ${slot.endTime.format(context)}',
            style: TextStyle(fontSize: rs.font(10.5)),
          ),
          padding: EdgeInsets.symmetric(horizontal: rs.width(4)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
  final Subject subject;

  const _MidSemesterChangePreview({
    required this.heading,
    required this.beforeSlots,
    required this.afterSlots,
    required this.kind,
    required this.subject,
  });
}
