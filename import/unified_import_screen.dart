import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/timetable_export_utils.dart';
import '../attendance/import_attendance_screen.dart';
import '../subject/import_timetable_screen.dart';
import '../subject/subject_provider.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_overlay.dart';

class UnifiedImportScreen extends StatefulWidget {
  final int initialTabIndex;
  final String? initialText;

  const UnifiedImportScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialText,
  });

  @override
  State<UnifiedImportScreen> createState() => _UnifiedImportScreenState();
}

class _UnifiedImportScreenState extends State<UnifiedImportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey _exportMenuKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: (widget.initialTabIndex >= 0 && widget.initialTabIndex < 2)
          ? widget.initialTabIndex
          : 0,
    );
    _tabController.addListener(_handleTabChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final tutorialController = Provider.of<TutorialController>(context, listen: false);
        tutorialController.addListener(_onTutorialStepChanged);
      }
    });
  }

  void _handleTabChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onTutorialStepChanged() {
    if (!mounted) return;
    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    if (tutorialController.isActive &&
        (tutorialController.currentStepIndex < 11 || tutorialController.currentStepIndex >= 13)) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    try {
      final tutorialController = Provider.of<TutorialController>(context, listen: false);
      tutorialController.removeListener(_onTutorialStepChanged);
    } catch (_) {}
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
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
            action: shouldOpen
                ? SnackBarAction(
                    label: 'Open',
                    onPressed: () async {
                      await OpenFilex.open(file.path);
                    },
                  )
                : null,
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

    final isTimetableTab = _tabController.index == 0;

    return TutorialOverlay(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              'Import Data',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: rs.font(18),
              ),
            ),
            elevation: 0,
            actions: [
              if (isTimetableTab)
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
                            Icon(
                              Icons.data_object_rounded,
                              size: rs.scale(18),
                              color: theme.colorScheme.primary,
                            ),
                            SizedBox(width: rs.width(12)),
                            Text('Export as JSON', style: TextStyle(fontSize: rs.font(13.5))),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'csv',
                        child: Row(
                          children: [
                            Icon(
                              Icons.table_chart_rounded,
                              size: rs.scale(18),
                              color: Colors.teal,
                            ),
                            SizedBox(width: rs.width(12)),
                            Text('Export as CSV', style: TextStyle(fontSize: rs.font(13.5))),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'pdf',
                        child: Row(
                          children: [
                            Icon(
                              Icons.picture_as_pdf_rounded,
                              size: rs.scale(18),
                              color: Colors.redAccent,
                            ),
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
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(
                  icon: Icon(Icons.table_chart_outlined),
                  text: 'Timetable',
                ),
                Tab(
                  icon: Icon(Icons.fact_check_outlined),
                  text: 'Attendance',
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              ImportTimetableScreen(
                initialText: widget.initialTabIndex == 0 ? widget.initialText : null,
                embedInUnifiedImport: true,
              ),
              ImportAttendanceScreen(
                initialText: widget.initialTabIndex == 1 ? widget.initialText : null,
                embedInUnifiedImport: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
