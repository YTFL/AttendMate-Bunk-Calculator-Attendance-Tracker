import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/database_service.dart';
import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../../widgets/app_time_picker.dart';
import '../../widgets/day_cycle_background.dart';
import '../attendance/attendance_provider.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_overlay.dart';
import 'planned_leave_model.dart';

class LeavePlannerScreen extends StatefulWidget {
  const LeavePlannerScreen({super.key});

  @override
  State<LeavePlannerScreen> createState() => _LeavePlannerScreenState();
}

class _LeavePlannerScreenState extends State<LeavePlannerScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<PlannedLeave> _leaves = [];
  bool _isLoading = true;

  final GlobalKey _leavePlannerAddKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadLeaves();

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
    if (tutorialController.isActive && (tutorialController.currentStepIndex < 23 || tutorialController.currentStepIndex >= 24)) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    try {
      final tutorialController = Provider.of<TutorialController>(context, listen: false);
      tutorialController.removeListener(_onTutorialStepChanged);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadLeaves({bool showLoading = false}) async {
    if (showLoading || _leaves.isEmpty) {
      setState(() => _isLoading = true);
    }
    final leaves = await _databaseService.loadPlannedLeaves();
    if (mounted) {
      setState(() {
        _leaves = leaves;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    tutorialController.registerKey('key_leave_planner_add', _leavePlannerAddKey);

    final rs = context.rs;
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final subjects = subjectProvider.subjects;

    // Calculate aggregate impact across all leaves
    int totalImpactedClassesAll = 0;
    for (final leave in _leaves) {
      final sDate = DateTime(leave.startDate.year, leave.startDate.month, leave.startDate.day);
      final eDate = DateTime(leave.endDate.year, leave.endDate.month, leave.endDate.day);
      DateTime cur = sDate;
      while (!cur.isAfter(eDate)) {
        for (final s in subjects) {
          if (leave.affectedSubjectIds.isNotEmpty && !leave.affectedSubjectIds.contains(s.id)) continue;
          for (final slot in s.schedule) {
            if (slot.occursOnDate(cur)) {
              final slotStart = DateTime(cur.year, cur.month, cur.day, slot.startTime.hour, slot.startTime.minute);
              final slotEnd = DateTime(cur.year, cur.month, cur.day, slot.endTime.hour, slot.endTime.minute);
              if (slotStart.isBefore(leave.endDate) && slotEnd.isAfter(leave.startDate)) {
                totalImpactedClassesAll++;
              }
            }
          }
        }
        cur = cur.add(const Duration(days: 1));
      }
    }

    return TutorialOverlay(
      child: DayCycleBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              'Leave Planner',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: rs.font(17),
              ),
            ),
            centerTitle: true,
          ),
          floatingActionButton: KeyedSubtree(
            key: _leavePlannerAddKey,
            child: Padding(
              padding: EdgeInsets.only(bottom: rs.scale(80)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(rs.scale(26)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? const Color(0xFF1B1B22).withValues(alpha: 0.85)
                          : Colors.white.withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(rs.scale(26)),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: isDarkMode ? 0.35 : 0.25),
                        width: 1.0,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: subjects.isEmpty ? null : () => _showAddLeaveDialog(context, subjects),
                        borderRadius: BorderRadius.circular(rs.scale(26)),
                        child: Padding(
                          padding: rs.insetsSymmetric(horizontal: 18, vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.add_rounded, size: rs.scale(18), color: theme.colorScheme.primary),
                              ),
                              SizedBox(width: rs.width(8)),
                              Text(
                                'Add Leave',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: rs.font(13.5),
                                  color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator.adaptive())
              : _leaves.isEmpty
                  ? _buildEmptyState(rs, theme, isDarkMode)
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(rs.scale(16), rs.scale(12), rs.scale(16), rs.scale(140)),
                      itemCount: _leaves.length + 1, // 0 is the overview cockpit
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _buildOverviewCard(rs, isDarkMode, totalImpactedClassesAll);
                        }
                        final leave = _leaves[index - 1];
                        return _buildLeaveCard(context, rs, theme, isDarkMode, leave, subjects);
                      },
                    ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard(ResponsiveScale rs, bool isDarkMode, int totalImpacted) {
    final cardBg = isDarkMode
        ? const Color(0xFF14141C).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.75);
    final cardBorder = isDarkMode
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.60);
    final innerBorder = isDarkMode
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return Container(
      margin: EdgeInsets.only(bottom: rs.scale(14)),
      padding: rs.insetsAll(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(rs.scale(24)),
        border: Border.all(color: cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.20 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: totalImpacted > 0
                          ? (isDarkMode ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500))
                          : (isDarkMode ? const Color(0xFF34C759) : const Color(0xFF28A745)),
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: rs.width(8)),
                  Text(
                    'LEAVE FORECAST TELEMETRY',
                    style: GoogleFonts.inter(
                      fontSize: rs.font(10),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                    ),
                  ),
                ],
              ),
              SizedBox(height: rs.height(14)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'PLANNED LEAVES',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(9.5),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                            color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                          ),
                        ),
                        SizedBox(height: rs.height(5)),
                        Text(
                          '${_leaves.length}',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(19),
                            fontWeight: FontWeight.w800,
                            color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 0.8,
                    height: rs.height(28),
                    color: innerBorder,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'CLASSES MISSED',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(9.5),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                            color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                          ),
                        ),
                        SizedBox(height: rs.height(5)),
                        Text(
                          '$totalImpacted',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(19),
                            fontWeight: FontWeight.w800,
                            color: totalImpacted > 0
                                ? (isDarkMode ? const Color(0xFFFF9F0A) : const Color(0xFFD97706))
                                : (isDarkMode ? const Color(0xFF34C759) : const Color(0xFF28A745)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 0.8,
                    height: rs.height(28),
                    color: innerBorder,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'BUFFER STATUS',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(9.5),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                            color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                          ),
                        ),
                        SizedBox(height: rs.height(5)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: totalImpacted == 0
                                ? (isDarkMode ? const Color(0xFF34C759).withValues(alpha: 0.15) : const Color(0xFF28A745).withValues(alpha: 0.12))
                                : (isDarkMode ? const Color(0xFFFF9F0A).withValues(alpha: 0.15) : const Color(0xFFFF9500).withValues(alpha: 0.12)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            totalImpacted == 0 ? 'NOMINAL' : 'IMPACTED',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(11),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: totalImpacted == 0
                                  ? (isDarkMode ? const Color(0xFF34C759) : const Color(0xFF28A745))
                                  : (isDarkMode ? const Color(0xFFFF9F0A) : const Color(0xFFD97706)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }

  Widget _buildEmptyState(ResponsiveScale rs, ThemeData theme, bool isDarkMode) {
    return Center(
      child: Padding(
        padding: rs.insetsAll(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(rs.scale(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: rs.insetsAll(22),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.60),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                      width: 1.0,
                    ),
                  ),
                  child: Icon(
                    Icons.event_available_outlined,
                    size: rs.scale(44),
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            SizedBox(height: rs.height(22)),
            Text(
              'No Leaves Planned',
              style: GoogleFonts.inter(
                fontSize: rs.font(18),
                fontWeight: FontWeight.w800,
                color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
              ),
            ),
            SizedBox(height: rs.height(8)),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: rs.width(300)),
              child: Text(
                'Plan future absences or medical leaves to forecast their impact on your attendance buffer before taking time off.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: rs.font(13),
                  color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveCard(
    BuildContext context,
    ResponsiveScale rs,
    ThemeData theme,
    bool isDarkMode,
    PlannedLeave leave,
    List<Subject> subjects,
  ) {
    final startDate = DateTime(leave.startDate.year, leave.startDate.month, leave.startDate.day);
    final endDate = DateTime(leave.endDate.year, leave.endDate.month, leave.endDate.day);

    final cardBg = isDarkMode
        ? const Color(0xFF14141C).withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.75);
    final cardBorder = isDarkMode
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.60);
    final recessedBg = isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03);
    final innerBorder = isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06);

    // Calculate exact missed class counts per subject taking start/end times into account
    final Map<String, int> missedCountsPerSubject = {};
    int totalClassesMissed = 0;

    DateTime cur = startDate;
    while (!cur.isAfter(endDate)) {
      for (final s in subjects) {
        if (leave.affectedSubjectIds.isNotEmpty && !leave.affectedSubjectIds.contains(s.id)) continue;
        for (final slot in s.schedule) {
          if (slot.occursOnDate(cur)) {
            final slotStart = DateTime(cur.year, cur.month, cur.day, slot.startTime.hour, slot.startTime.minute);
            final slotEnd = DateTime(cur.year, cur.month, cur.day, slot.endTime.hour, slot.endTime.minute);
            if (slotStart.isBefore(leave.endDate) && slotEnd.isAfter(leave.startDate)) {
              final name = s.acronym ?? s.name;
              missedCountsPerSubject[name] = (missedCountsPerSubject[name] ?? 0) + 1;
              totalClassesMissed++;
            }
          }
        }
      }
      cur = cur.add(const Duration(days: 1));
    }

    final String missedBreakdownText = totalClassesMissed > 0
        ? missedCountsPerSubject.entries.map((e) => '${e.key} (${e.value})').join(', ')
        : 'No scheduled slots fall within this window';

    final isStartFullDay = leave.startDate.hour == 0 && leave.startDate.minute == 0;
    final isEndFullDay = leave.endDate.hour == 23 && leave.endDate.minute == 59;
    final startTimeStr = TimeOfDay.fromDateTime(leave.startDate).format(context);
    final endTimeStr = TimeOfDay.fromDateTime(leave.endDate).format(context);

    final String dateRangeDisplay;
    if (isStartFullDay && isEndFullDay) {
      if (leave.startDate.year == leave.endDate.year &&
          leave.startDate.month == leave.endDate.month &&
          leave.startDate.day == leave.endDate.day) {
        dateRangeDisplay = '${leave.startDate.day}/${leave.startDate.month}/${leave.startDate.year} (Full Day)';
      } else {
        dateRangeDisplay = '${leave.startDate.day}/${leave.startDate.month}/${leave.startDate.year} - ${leave.endDate.day}/${leave.endDate.month}/${leave.endDate.year} (Full Days)';
      }
    } else if (isStartFullDay) {
      dateRangeDisplay = '${leave.startDate.day}/${leave.startDate.month}/${leave.startDate.year} (Full Day) - ${leave.endDate.day}/${leave.endDate.month}/${leave.endDate.year} ($endTimeStr)';
    } else if (isEndFullDay) {
      dateRangeDisplay = '${leave.startDate.day}/${leave.startDate.month}/${leave.startDate.year} ($startTimeStr) - ${leave.endDate.day}/${leave.endDate.month}/${leave.endDate.year} (Full Day)';
    } else {
      dateRangeDisplay = '${leave.startDate.day}/${leave.startDate.month}/${leave.startDate.year} ($startTimeStr) - ${leave.endDate.day}/${leave.endDate.month}/${leave.endDate.year} ($endTimeStr)';
    }

    return Container(
      margin: EdgeInsets.only(bottom: rs.scale(12)),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(rs.scale(24)),
        border: Border.all(color: cardBorder, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.20 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
          child: Padding(
            padding: rs.insetsAll(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: rs.insetsAll(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(rs.scale(16)),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(
                        Icons.event_available_outlined,
                        color: theme.colorScheme.primary,
                        size: rs.scale(18),
                      ),
                    ),
                    SizedBox(width: rs.width(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            leave.name,
                            style: GoogleFonts.inter(
                              fontSize: rs.font(15),
                              fontWeight: FontWeight.w700,
                              color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: rs.height(3)),
                          Text(
                            dateRangeDisplay,
                            style: GoogleFonts.inter(
                              fontSize: rs.font(11.5),
                              fontWeight: FontWeight.w500,
                              color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(8),
                      ),
                      icon: Icon(Icons.edit_outlined, size: rs.scale(16)),
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                      onPressed: () => _showEditLeaveDialog(context, leave, subjects),
                    ),
                    SizedBox(width: rs.width(6)),
                    IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFFF453A).withValues(alpha: 0.12),
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(8),
                      ),
                      icon: Icon(Icons.delete_outline_rounded, size: rs.scale(16)),
                      color: const Color(0xFFFF453A),
                      onPressed: () => _confirmDeleteLeave(context, leave),
                    ),
                  ],
                ),
                SizedBox(height: rs.height(12)),
                // Recessed Impact Console
                Container(
                  padding: rs.insetsAll(12),
                  decoration: BoxDecoration(
                    color: recessedBg,
                    borderRadius: BorderRadius.circular(rs.scale(16)),
                    border: Border.all(color: innerBorder, width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: totalClassesMissed > 0
                                  ? (isDarkMode ? const Color(0xFFFF9F0A) : const Color(0xFFD97706))
                                  : (isDarkMode ? const Color(0xFF34C759) : const Color(0xFF28A745)),
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: rs.width(6)),
                          Text(
                            'CLASSES IMPACTED: $totalClassesMissed',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(11),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: totalClassesMissed > 0
                                  ? (isDarkMode ? const Color(0xFFFF9F0A) : const Color(0xFFD97706))
                                  : (isDarkMode ? const Color(0xFF34C759) : const Color(0xFF28A745)),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: rs.height(4)),
                      Text(
                        missedBreakdownText,
                        style: GoogleFonts.inter(
                          fontSize: rs.font(11.5),
                          color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }

  void _showAddLeaveDialog(BuildContext parentContext, List<Subject> subjects) {
    _showLeaveEditorDialog(parentContext: parentContext, subjects: subjects);
  }

  void _showEditLeaveDialog(BuildContext parentContext, PlannedLeave leave, List<Subject> subjects) {
    _showLeaveEditorDialog(parentContext: parentContext, subjects: subjects, leave: leave);
  }

  Future<DateTime?> _pickDateWithGlassTheme({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (context, child) {
        return Theme(
          data: theme.copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: theme.colorScheme.primary,
                    onPrimary: theme.colorScheme.onPrimary,
                    surface: const Color(0xFF14141A),
                    onSurface: Colors.white,
                  )
                : ColorScheme.light(
                    primary: theme.colorScheme.primary,
                    onPrimary: theme.colorScheme.onPrimary,
                    surface: Colors.white,
                    onSurface: const Color(0xFF1C1C1E),
                  ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
          child: child!,
        );
      },
    );
  }

  void _showLeaveEditorDialog({
    required BuildContext parentContext,
    required List<Subject> subjects,
    PlannedLeave? leave,
  }) {
    final rs = parentContext.rs;
    final isDarkMode = Theme.of(parentContext).brightness == Brightness.dark;
    final isEditing = leave != null;

    final nameController = TextEditingController(text: leave?.name ?? '');
    DateTime startDate = leave?.startDate ?? DateTime.now();
    DateTime endDate = leave?.endDate ?? DateTime.now().add(const Duration(days: 1));
    bool isStartFullDay = isEditing ? (startDate.hour == 0 && startDate.minute == 0) : true;
    bool isEndFullDay = isEditing ? (endDate.hour == 23 && endDate.minute == 59) : true;

    if (!isEditing) {
      startDate = DateTime(startDate.year, startDate.month, startDate.day, 0, 0);
      endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59);
    }

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final startTimeTod = TimeOfDay.fromDateTime(startDate);
            final endTimeTod = TimeOfDay.fromDateTime(endDate);

            return ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(rs.scale(26))),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color(0xFF121218).withValues(alpha: 0.72)
                        : Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(rs.scale(26))),
                    border: Border(
                      top: BorderSide(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.60),
                        width: 1.0,
                      ),
                    ),
                  ),
              padding: EdgeInsets.fromLTRB(
                rs.scale(20),
                rs.scale(12),
                rs.scale(20),
                MediaQuery.of(sheetCtx).viewInsets.bottom + rs.scale(24),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: rs.scale(36),
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white24 : Colors.black26,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    SizedBox(height: rs.height(14)),
                    // Header Row: Icon + Title + Close Button
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(rs.scale(12)),
                            border: Border.all(
                              color: isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                              width: 0.8,
                            ),
                          ),
                          child: Icon(
                            isEditing ? Icons.edit_calendar_rounded : Icons.event_available_rounded,
                            size: rs.scale(20),
                            color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                          ),
                        ),
                        SizedBox(width: rs.width(10)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isEditing ? 'Edit Planned Leave' : 'Plan New Leave',
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(17),
                                  fontWeight: FontWeight.w800,
                                  color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                                ),
                              ),
                              SizedBox(height: rs.height(2)),
                              Text(
                                'Forecast absence impact on your attendance buffer',
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(11.5),
                                  color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, size: rs.scale(20)),
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(18)),
                    Text(
                      'LEAVE REASON',
                      style: GoogleFonts.inter(
                        fontSize: rs.font(10),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                      ),
                    ),
                    SizedBox(height: rs.height(6)),
                    Container(
                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(rs.scale(12)),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.08),
                          width: 0.8,
                        ),
                      ),
                      child: TextField(
                        controller: nameController,
                        style: GoogleFonts.inter(
                          fontSize: rs.font(13.5),
                          fontWeight: FontWeight.w500,
                          color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Medical Leave, Hackathon, Travel',
                          hintStyle: GoogleFonts.inter(
                            fontSize: rs.font(13),
                            color: isDarkMode ? const Color(0xFF636366) : const Color(0xFF8E8E93),
                          ),
                          contentPadding: rs.insetsSymmetric(horizontal: 14, vertical: 12),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          filled: false,
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                    SizedBox(height: rs.height(16)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'START DATE & TIME',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(10),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setDialogState(() {
                              isStartFullDay = !isStartFullDay;
                              if (isStartFullDay) {
                                startDate = DateTime(startDate.year, startDate.month, startDate.day, 0, 0);
                              } else {
                                startDate = DateTime(startDate.year, startDate.month, startDate.day, 9, 0);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: Checkbox(
                                    value: isStartFullDay,
                                    activeColor: Theme.of(context).colorScheme.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setDialogState(() {
                                        isStartFullDay = val;
                                        if (isStartFullDay) {
                                          startDate = DateTime(startDate.year, startDate.month, startDate.day, 0, 0);
                                        } else {
                                          startDate = DateTime(startDate.year, startDate.month, startDate.day, 9, 0);
                                        }
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(width: rs.width(4)),
                                Text(
                                  'Full Day',
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(11.5),
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(6)),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: rs.insetsSymmetric(horizontal: 10, vertical: 10),
                              backgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                              side: BorderSide(
                                color: isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                                width: 0.8,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rs.scale(10))),
                            ),
                            icon: Icon(Icons.calendar_today_rounded, size: rs.scale(13), color: Theme.of(context).colorScheme.primary),
                            label: Text(
                              '${startDate.day}/${startDate.month}/${startDate.year}',
                              style: GoogleFonts.inter(fontSize: rs.font(11.5), fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.black87),
                            ),
                            onPressed: () async {
                              final picked = await _pickDateWithGlassTheme(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  final h = isStartFullDay ? 0 : startDate.hour;
                                  final m = isStartFullDay ? 0 : startDate.minute;
                                  startDate = DateTime(picked.year, picked.month, picked.day, h, m);
                                  if (endDate.isBefore(startDate)) {
                                    final endH = isEndFullDay ? 23 : startDate.hour + 2;
                                    final endM = isEndFullDay ? 59 : startDate.minute;
                                    endDate = DateTime(picked.year, picked.month, picked.day, endH, endM);
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        SizedBox(width: rs.width(8)),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: rs.insetsSymmetric(horizontal: 10, vertical: 10),
                              backgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                              side: BorderSide(
                                color: isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                                width: 0.8,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rs.scale(10))),
                            ),
                            icon: Icon(Icons.access_time_rounded, size: rs.scale(13), color: isDarkMode ? Colors.white70 : Colors.black54),
                            label: Text(
                              isStartFullDay ? 'All Day' : startTimeTod.format(context),
                              style: GoogleFonts.inter(fontSize: rs.font(11.5), fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.black87),
                            ),
                            onPressed: isStartFullDay
                                ? null
                                : () async {
                                    final picked = await showAppTimePicker(
                                      context: context,
                                      initialTime: startTimeTod,
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        startDate = DateTime(startDate.year, startDate.month, startDate.day, picked.hour, picked.minute);
                                        if (endDate.isBefore(startDate)) {
                                          endDate = startDate.add(const Duration(hours: 2));
                                        }
                                      });
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(14)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'END DATE & TIME',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(10),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setDialogState(() {
                              isEndFullDay = !isEndFullDay;
                              if (isEndFullDay) {
                                endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59);
                              } else {
                                endDate = DateTime(endDate.year, endDate.month, endDate.day, 17, 0);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: Checkbox(
                                    value: isEndFullDay,
                                    activeColor: Theme.of(context).colorScheme.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    onChanged: (val) {
                                      if (val == null) return;
                                      setDialogState(() {
                                        isEndFullDay = val;
                                        if (isEndFullDay) {
                                          endDate = DateTime(endDate.year, endDate.month, endDate.day, 23, 59);
                                        } else {
                                          endDate = DateTime(endDate.year, endDate.month, endDate.day, 17, 0);
                                        }
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(width: rs.width(4)),
                                Text(
                                  'Full Day',
                                  style: GoogleFonts.inter(
                                    fontSize: rs.font(11.5),
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(6)),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: rs.insetsSymmetric(horizontal: 10, vertical: 10),
                              backgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                              side: BorderSide(
                                color: isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                                width: 0.8,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rs.scale(10))),
                            ),
                            icon: Icon(Icons.calendar_today_rounded, size: rs.scale(13), color: Theme.of(context).colorScheme.primary),
                            label: Text(
                              '${endDate.day}/${endDate.month}/${endDate.year}',
                              style: GoogleFonts.inter(fontSize: rs.font(11.5), fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.black87),
                            ),
                            onPressed: () async {
                              final picked = await _pickDateWithGlassTheme(
                                context: context,
                                initialDate: endDate,
                                firstDate: startDate,
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() {
                                  final h = isEndFullDay ? 23 : endDate.hour;
                                  final m = isEndFullDay ? 59 : endDate.minute;
                                  endDate = DateTime(picked.year, picked.month, picked.day, h, m);
                                });
                              }
                            },
                          ),
                        ),
                        SizedBox(width: rs.width(8)),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: rs.insetsSymmetric(horizontal: 10, vertical: 10),
                              backgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                              side: BorderSide(
                                color: isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                                width: 0.8,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rs.scale(10))),
                            ),
                            icon: Icon(Icons.access_time_rounded, size: rs.scale(13), color: isDarkMode ? Colors.white70 : Colors.black54),
                            label: Text(
                              isEndFullDay ? 'All Day' : endTimeTod.format(context),
                              style: GoogleFonts.inter(fontSize: rs.font(11.5), fontWeight: FontWeight.w600, color: isDarkMode ? Colors.white : Colors.black87),
                            ),
                            onPressed: isEndFullDay
                                ? null
                                : () async {
                                    final picked = await showAppTimePicker(
                                      context: context,
                                      initialTime: endTimeTod,
                                    );
                                    if (picked != null) {
                                      setDialogState(() {
                                        endDate = DateTime(endDate.year, endDate.month, endDate.day, picked.hour, picked.minute);
                                      });
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(22)),
                    // Action Buttons Row (Flat styling, no glowing effects)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: rs.insetsSymmetric(vertical: 13),
                              side: BorderSide(
                                color: isDarkMode ? Colors.white.withValues(alpha: 0.16) : Colors.black.withValues(alpha: 0.12),
                                width: 0.8,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rs.scale(14))),
                            ),
                            onPressed: () => Navigator.of(sheetCtx).pop(),
                            child: Text(
                              'Cancel',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(13.5),
                                fontWeight: FontWeight.w600,
                                color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: rs.width(10)),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: rs.insetsSymmetric(vertical: 13),
                              backgroundColor: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                              foregroundColor: isDarkMode ? Colors.black : Colors.white,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rs.scale(14))),
                            ),
                            onPressed: () async {
                              final name = nameController.text.trim();
                              final messenger = ScaffoldMessenger.of(parentContext);
                              final nav = Navigator.of(sheetCtx);
                              final subjectProvider = Provider.of<SubjectProvider>(parentContext, listen: false);
                              final attendanceProvider = Provider.of<AttendanceProvider>(parentContext, listen: false);

                              if (name.isEmpty) {
                                messenger.showReplacingSnackBar(
                                  const SnackBar(content: Text('Please enter a leave reason.')),
                                );
                                return;
                              }

                              if (isEditing) {
                                final updatedLeave = PlannedLeave(
                                  id: leave.id,
                                  name: name,
                                  startDate: startDate,
                                  endDate: endDate,
                                  affectedSubjectIds: subjects.map((s) => s.id).toList(),
                                );
                                await _databaseService.savePlannedLeave(updatedLeave);
                                final allLeaves = await _databaseService.loadPlannedLeaves();
                                await attendanceProvider.cleanupPlannedLeaveAttendance(
                                  deletedLeave: leave,
                                  remainingLeaves: allLeaves,
                                  subjects: subjects,
                                );
                                await attendanceProvider.syncPlannedLeavesWithAttendance(
                                  plannedLeaves: [updatedLeave],
                                  subjects: subjects,
                                );
                                nav.pop();
                                _loadLeaves();
                                subjectProvider.scheduleAutoSync();
                                messenger.showReplacingSnackBar(
                                  SnackBar(content: Text('Leave "$name" updated.')),
                                );
                              } else {
                                final newLeave = PlannedLeave(
                                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                                  name: name,
                                  startDate: startDate,
                                  endDate: endDate,
                                  affectedSubjectIds: subjects.map((s) => s.id).toList(),
                                );
                                await _databaseService.savePlannedLeave(newLeave);
                                await attendanceProvider.syncPlannedLeavesWithAttendance(
                                  plannedLeaves: [newLeave],
                                  subjects: subjects,
                                );
                                nav.pop();
                                _loadLeaves();
                                subjectProvider.scheduleAutoSync();
                                messenger.showReplacingSnackBar(
                                  SnackBar(content: Text('Leave "$name" scheduled.')),
                                );
                              }
                            },
                            child: Text(
                              isEditing ? 'Update Leave' : 'Add Leave',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(13.5),
                                fontWeight: FontWeight.w700,
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
      },
    );
      },
    );
  }

  void _confirmDeleteLeave(BuildContext context, PlannedLeave leave) {
    final rs = context.rs;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
    final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF16161C) : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(rs.scale(26))),
            border: Border(
              top: BorderSide(
                color: isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            rs.scale(20),
            rs.scale(12),
            rs.scale(20),
            MediaQuery.of(sheetCtx).padding.bottom + rs.scale(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: rs.scale(36),
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: rs.height(18)),
              // Red Trash Badge + Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF453A).withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFF453A).withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: const Color(0xFFFF453A),
                      size: rs.scale(22),
                    ),
                  ),
                  SizedBox(width: rs.width(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delete Leave',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(17),
                            fontWeight: FontWeight.w800,
                            color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                          ),
                        ),
                        SizedBox(height: rs.height(2)),
                        Text(
                          'Remove scheduled absence projections',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(12),
                            color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: rs.height(16)),
              // Detailed Confirmation Card
              Container(
                padding: rs.insetsAll(14),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(rs.scale(16)),
                  border: Border.all(
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Are you sure you want to delete "${leave.name}"?',
                      style: GoogleFonts.inter(
                        fontSize: rs.font(13.5),
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : const Color(0xFF1C1C1E),
                      ),
                    ),
                    SizedBox(height: rs.height(6)),
                    Text(
                      'This will remove scheduled absence projections and restore your attendance forecast.',
                      style: GoogleFonts.inter(
                        fontSize: rs.font(12),
                        color: isDarkMode ? const Color(0xFF8E8E93) : const Color(0xFF636366),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: rs.height(20)),
              // Action Buttons Row: Cancel and Delete
              Row(
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(sheetCtx).pop(),
                        borderRadius: BorderRadius.circular(rs.scale(14)),
                        child: Container(
                          padding: rs.insetsSymmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(rs.scale(14)),
                            border: Border.all(
                              color: isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                              width: 0.8,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(13.5),
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: rs.width(10)),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () async {
                          final dialogNav = Navigator.of(sheetCtx);
                          await _databaseService.deletePlannedLeave(leave.id);
                          final remainingLeaves = await _databaseService.loadPlannedLeaves();
                          await attendanceProvider.cleanupPlannedLeaveAttendance(
                            deletedLeave: leave,
                            remainingLeaves: remainingLeaves,
                            subjects: subjectProvider.subjects,
                          );
                          dialogNav.pop();
                          _loadLeaves();
                          subjectProvider.scheduleAutoSync();
                        },
                        borderRadius: BorderRadius.circular(rs.scale(14)),
                        child: Container(
                          padding: rs.insetsSymmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF453A),
                            borderRadius: BorderRadius.circular(rs.scale(14)),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Delete Leave',
                            style: GoogleFonts.inter(
                              fontSize: rs.font(13.5),
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
