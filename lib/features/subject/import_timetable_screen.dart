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
import '../../utils/time_format_utils.dart';
import 'package:intl/intl.dart';
import 'elective_selection_dialog.dart';
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
  List<SpecialClassImportItem> _importedSpecialClasses = [];
  List<_MidSemesterChangePreview> _midSemesterChanges = [];
  int _importModeIndex = 0; // 0: Update Mid-Semester Timetable, 1: Add New Subjects Mid-Semester, 2: Bulk Setup
  bool get _isMidSemesterUpdate => _importModeIndex == 0;
  late DateTime _effectiveFromDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _effectiveFromDate = DateTime(now.year, now.month, now.day);

    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
    if (subjectProvider.subjects.isEmpty) {
      _importModeIndex = 2; // Default to bulk if no subjects
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

  Future<void> _parseAndValidateInput() async {
    final inputText = _inputTextController.text.trim();
    
    if (inputText.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter or paste JSON or CSV data';
        _importedSubjects = null;
        _importedSpecialClasses = [];
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
      
      final pkg = TimetableImportUtils.parseInputToImportPackage(inputText, usedColors);

      if (pkg.effectiveFrom != null) {
        _effectiveFromDate = pkg.effectiveFrom!;
        if (_importModeIndex == 2) {
          _importModeIndex = 1;
        }
      }

      final subjectsToPreview = <Subject>[...pkg.standardSubjects];

      // If electives are present, prompt user for preference
      if (pkg.hasElectives && mounted) {
        final chosen = await ElectiveSelectionDialog.show(
          context,
          electiveSlots: pkg.electiveSlots,
        );
        if (chosen != null) {
          subjectsToPreview.addAll(chosen);
        }
      }

      final midSemesterChanges = _importModeIndex == 0
          ? _buildMidSemesterChangePreview(subjectsToPreview)
          : <_MidSemesterChangePreview>[];
      
      setState(() {
        _importedSubjects = subjectsToPreview;
        _importedSpecialClasses = pkg.specialClasses;
        _midSemesterChanges = midSemesterChanges;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _importedSubjects = null;
        _importedSpecialClasses = [];
        _midSemesterChanges = [];
      });
    }
  }

  Future<void> _importSubjects() async {
    final hasSubjects = _importedSubjects != null && _importedSubjects!.isNotEmpty;
    final hasSpecials = _importedSpecialClasses.isNotEmpty;

    if (!hasSubjects && !hasSpecials) {
      ScaffoldMessenger.of(context).showReplacingSnackBar(
        const SnackBar(
          content: Text('No valid subjects or special classes to import'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
    int importedCount = 0;
    int specialsCount = 0;

    if (hasSpecials) {
      specialsCount = await subjectProvider.importSpecialOneOffClasses(_importedSpecialClasses);
    }

    if (hasSubjects) {
      if (_importModeIndex == 0) {
        final result = await subjectProvider.applyTimetableUpdateFromDate(
          _importedSubjects!,
          _effectiveFromDate,
        );
        importedCount = result.matchedSubjects + result.newSubjects;
      } else if (_importModeIndex == 1) {
        importedCount = await subjectProvider.importNewSubjectsMidSemester(
          newSubjects: _importedSubjects!,
          effectiveFromDate: _effectiveFromDate,
        );
      } else {
        await subjectProvider.bulkImportSubjects(_importedSubjects!);
        importedCount = _importedSubjects!.length;
      }
    }

    if (!mounted) {
      return;
    }

    final parts = <String>[];
    if (importedCount > 0) parts.add('$importedCount subject(s)');
    if (specialsCount > 0) parts.add('$specialsCount special class(es)');

    ScaffoldMessenger.of(context).showReplacingSnackBar(
      SnackBar(
        content: Text('Successfully imported ${parts.join(" and ")}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );

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
      builder: (ctx) => const _SampleFormatDialogWidget(),
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
          if (_importModeIndex == 0 || _importModeIndex == 1) ...[
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
          if ((_importedSubjects != null && _importedSubjects!.isNotEmpty) || _importedSpecialClasses.isNotEmpty) ...[
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
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment<int>(
                  value: 0,
                  label: Text('Update Timetable', style: TextStyle(fontSize: rs.font(11.5), fontWeight: FontWeight.w600)),
                  icon: Icon(Icons.update_rounded, size: rs.scale(16)),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('Add Mid-Semester', style: TextStyle(fontSize: rs.font(11.5), fontWeight: FontWeight.w600)),
                  icon: Icon(Icons.post_add_rounded, size: rs.scale(16)),
                ),
                ButtonSegment<int>(
                  value: 2,
                  label: Text('Bulk Setup', style: TextStyle(fontSize: rs.font(11.5), fontWeight: FontWeight.w600)),
                  icon: Icon(Icons.playlist_add_rounded, size: rs.scale(16)),
                ),
              ],
              selected: <int>{_importModeIndex},
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
                  _importModeIndex = selection.first;
                  if (_importModeIndex == 0 && _importedSubjects != null) {
                    _midSemesterChanges = _buildMidSemesterChangePreview(_importedSubjects!);
                  } else {
                    _midSemesterChanges = [];
                  }
                });
              },
            ),
          ),
          if (_importModeIndex == 1) ...[
            SizedBox(height: rs.height(8)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: rs.width(4)),
              child: Text(
                'Preserves all your current subjects and attendance history. Only newly imported subjects will be added from the effective date.',
                style: TextStyle(
                  fontSize: rs.font(11),
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
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
                        _importModeIndex == 1
                            ? 'Add New Subjects Starting From'
                            : 'Apply Updated Timetable From',
                        style: TextStyle(
                          fontSize: rs.font(13.5),
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: rs.height(3)),
                      Text(
                        _importModeIndex == 1
                            ? 'New subjects will take effect starting ${_formatDate(_effectiveFromDate)}'
                            : 'Classes prior to ${_formatDate(_effectiveFromDate)} remain locked to old schedule',
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
        if (_importedSpecialClasses.isNotEmpty) ...[
          Container(
            padding: EdgeInsets.all(rs.scale(12)),
            margin: EdgeInsets.only(bottom: rs.height(14)),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(rs.scale(14)),
              border: Border.all(color: theme.colorScheme.tertiary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.event_note_rounded, size: rs.scale(18), color: theme.colorScheme.tertiary),
                    SizedBox(width: rs.width(8)),
                    Text(
                      'SPECIAL ONE-OFF CLASSES (${_importedSpecialClasses.length})',
                      style: TextStyle(
                        fontSize: rs.font(11.5),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: rs.height(8)),
                ..._importedSpecialClasses.map((item) {
                  final dateStr = item.slot.specificDate != null
                      ? DateFormat('EEE, dd MMM yyyy').format(item.slot.specificDate!)
                      : 'Specific Date';
                  final timeStr = TimeFormatUtils.formatTimeRange(item.slot.startTime, item.slot.endTime, TimeFormat.format12Hr);
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: rs.height(3)),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: rs.width(6), vertical: rs.height(2)),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(rs.scale(4)),
                          ),
                          child: Text(
                            dateStr,
                            style: TextStyle(fontSize: rs.font(11), fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(width: rs.width(8)),
                        Expanded(
                          child: Text(
                            item.displayName,
                            style: TextStyle(fontSize: rs.font(12.5), fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          timeStr,
                          style: TextStyle(fontSize: rs.font(11), color: theme.textTheme.bodySmall?.color),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
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
                      if (subject.isElective) ...[
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: rs.width(6),
                            vertical: rs.height(2),
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(rs.scale(6)),
                          ),
                          child: Text(
                            'Elective',
                            style: TextStyle(
                              fontSize: rs.font(10.5),
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
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


class _SampleFormatDialogWidget extends StatefulWidget {
  const _SampleFormatDialogWidget();

  @override
  State<_SampleFormatDialogWidget> createState() => _SampleFormatDialogWidgetState();
}

class _SampleFormatDialogWidgetState extends State<_SampleFormatDialogWidget> {
  int _promptCategory = 0; // 0: Master, 1: Special Classes, 2: Mid-Semester, 3: Electives
  int _jsonCategory = 0;   // 0: Master, 1: Special Classes, 2: Mid-Semester, 3: Electives

  String get _currentPromptText {
    switch (_promptCategory) {
      case 0: return TimetableImportUtils.timetableAiPromptMaster;
      case 1: return TimetableImportUtils.timetableAiPromptSpecialClasses;
      case 2: return TimetableImportUtils.timetableAiPromptMidSemester;
      case 3: return TimetableImportUtils.timetableAiPromptElectives;
      default: return TimetableImportUtils.timetableAiPromptMaster;
    }
  }

  String get _currentPromptName {
    switch (_promptCategory) {
      case 0: return 'Master Timetable AI Prompt';
      case 1: return 'Special One-Off Classes Prompt';
      case 2: return 'Mid-Semester New Subjects Prompt';
      case 3: return 'Electives Only Prompt';
      default: return 'AI Prompt';
    }
  }

  String get _currentJsonText {
    switch (_jsonCategory) {
      case 0: return TimetableImportUtils.formatJson(TimetableImportUtils.generateTemplateJsonMaster());
      case 1: return TimetableImportUtils.formatJson(TimetableImportUtils.generateTemplateJsonSpecialClasses());
      case 2: return TimetableImportUtils.formatJson(TimetableImportUtils.generateTemplateJsonMidSemester());
      case 3: return TimetableImportUtils.formatJson(TimetableImportUtils.generateTemplateJsonElectives());
      default: return TimetableImportUtils.formatJson(TimetableImportUtils.generateTemplateJsonMaster());
    }
  }

  String get _currentJsonName {
    switch (_jsonCategory) {
      case 0: return 'Master Timetable JSON';
      case 1: return 'Special Classes JSON';
      case 2: return 'Mid-Semester JSON';
      case 3: return 'Electives JSON';
      default: return 'JSON Template';
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
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
                  Tab(text: 'AI Prompts (Recommended)'),
                  Tab(text: 'JSON Schemas'),
                  Tab(text: 'CSV Format'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: TabBarView(
                  children: [
                    // Tab 1: AI Prompts
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildChoiceChip('All-in-One', 0, _promptCategory, (v) => setState(() => _promptCategory = v)),
                              const SizedBox(width: 6),
                              _buildChoiceChip('Special Classes', 1, _promptCategory, (v) => setState(() => _promptCategory = v)),
                              const SizedBox(width: 6),
                              _buildChoiceChip('Mid-Semester', 2, _promptCategory, (v) => setState(() => _promptCategory = v)),
                              const SizedBox(width: 6),
                              _buildChoiceChip('Electives', 3, _promptCategory, (v) => setState(() => _promptCategory = v)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(child: _buildCodeView(_currentPromptText)),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _currentPromptText));
                            ScaffoldMessenger.of(context).showReplacingSnackBar(
                              SnackBar(
                                content: Text('$_currentPromptName copied to clipboard'),
                                backgroundColor: Colors.blue,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 14),
                          label: Text('Copy $_currentPromptName'),
                        ),
                      ],
                    ),

                    // Tab 2: JSON Schemas
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildChoiceChip('Master', 0, _jsonCategory, (v) => setState(() => _jsonCategory = v)),
                              const SizedBox(width: 6),
                              _buildChoiceChip('Special Classes', 1, _jsonCategory, (v) => setState(() => _jsonCategory = v)),
                              const SizedBox(width: 6),
                              _buildChoiceChip('Mid-Semester', 2, _jsonCategory, (v) => setState(() => _jsonCategory = v)),
                              const SizedBox(width: 6),
                              _buildChoiceChip('Electives', 3, _jsonCategory, (v) => setState(() => _jsonCategory = v)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(child: _buildCodeView(_currentJsonText)),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _currentJsonText));
                            ScaffoldMessenger.of(context).showReplacingSnackBar(
                              SnackBar(
                                content: Text('$_currentJsonName copied to clipboard'),
                                backgroundColor: Colors.blue,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 14),
                          label: Text('Copy $_currentJsonName'),
                        ),
                      ],
                    ),

                    // Tab 3: CSV Format
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildCodeView(TimetableImportUtils.generateTemplateCsv())),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: TimetableImportUtils.generateTemplateCsv()));
                            ScaffoldMessenger.of(context).showReplacingSnackBar(
                              const SnackBar(
                                content: Text('CSV Template copied to clipboard'),
                                backgroundColor: Colors.blue,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('Copy CSV Template'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceChip(String label, int value, int current, ValueChanged<int> onSelected) {
    final isSelected = current == value;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      onSelected: (_) => onSelected(value),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildCodeView(String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ),
    );
  }
}
