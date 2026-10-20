import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../features/attendance/attendance_model.dart';
import '../../features/attendance/attendance_provider.dart';
import '../../features/planner/planned_leave_model.dart';
import '../../features/semester/semester_provider.dart';
import '../../features/settings/time_format_provider.dart';
import '../../features/subject/subject_model.dart';
import '../../features/subject/subject_provider.dart';
import '../../services/database_service.dart';
import '../../utils/responsive_scale.dart';
import '../../widgets/day_cycle_background.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_overlay.dart';
import 'calendar_utils.dart';

/// The 4 interactive timeline granularities ordered from widest to closest focus:
/// - semester: Complete 6 months of the semester (0.25x Ultra-wide)
/// - month: Full monthly calendar grid (0.5x Wide)
/// - week: 7-Day detailed calendar (1.0x Normal Close-up Focus - Default!)
/// - day: Macro single-day inspection (2.0x Macro)
enum TimelineGranularity { semester, month, week, day }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with TickerProviderStateMixin {
  late DateTime _selectedMonth;
  late DateTime _selectedDate;
  DayState? _selectedStateFilter;
  PageController? _monthPageController;
  late FixedExtentScrollController _monthWheelController;
  List<PlannedLeave> _plannedLeaves = [];
  TimelineGranularity _granularity = TimelineGranularity.week;

  late AnimationController _cameraZoomController;
  late Animation<double> _cameraZoomAnimation;
  late AnimationController _pinchSpringController;
  final ValueNotifier<double> _pinchScaleNotifier = ValueNotifier<double>(1.0);
  double _pinchSpringStartScale = 1.0;
  bool _isZoomingOut = false;

  // Multi-touch pinch tracking for smooth zoom with limits
  final Map<int, Offset> _activePointers = {};
  double _pinchStartDistance = 0.0;
  DateTime? _lastStepZoomTime;

  final GlobalKey _calendarHeaderKey = GlobalKey();
  final GlobalKey _calendarLegendKey = GlobalKey();
  final GlobalKey _calendarGridKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _granularity = TimelineGranularity.week;
    _monthWheelController = FixedExtentScrollController(initialItem: _selectedMonth.month - 1);

    _cameraZoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1.0,
    );
    _cameraZoomAnimation = CurvedAnimation(
      parent: _cameraZoomController,
      curve: Curves.easeOutCubic,
    );

    _pinchSpringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _pinchSpringController.addListener(() {
      final curved = Curves.easeOutCubic.transform(_pinchSpringController.value);
      _pinchScaleNotifier.value = lerpDouble(_pinchSpringStartScale, 1.0, curved)!;
    });

    _loadPlannedLeaves();

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
    if (tutorialController.isActive &&
        (tutorialController.currentStepIndex < 16 || tutorialController.currentStepIndex >= 19)) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _loadPlannedLeaves() async {
    final leaves = await DatabaseService().loadPlannedLeaves();
    if (mounted) {
      setState(() {
        _plannedLeaves = leaves;
      });
      if (leaves.isNotEmpty) {
        final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
        final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
        if (subjectProvider.subjects.isNotEmpty) {
          await _autoMarkPlannedLeaves(leaves, subjectProvider.subjects, attendanceProvider);
        }
      }
    }
  }

  Future<void> _autoMarkPlannedLeaves(
    List<PlannedLeave> plannedLeaves,
    List<Subject> subjects,
    AttendanceProvider attendanceProvider,
  ) async {
    await attendanceProvider.syncPlannedLeavesWithAttendance(
      plannedLeaves: plannedLeaves,
      subjects: subjects,
    );
  }

  @override
  void dispose() {
    try {
      final tutorialController = Provider.of<TutorialController>(context, listen: false);
      tutorialController.removeListener(_onTutorialStepChanged);
    } catch (_) {}
    _monthPageController?.dispose();
    _monthWheelController.dispose();
    _cameraZoomController.dispose();
    _pinchSpringController.dispose();
    _pinchScaleNotifier.dispose();
    super.dispose();
  }

  void _setGranularityWithAnimation(TimelineGranularity newGranularity, {DateTime? targetMonth}) {
    if (_granularity == newGranularity && targetMonth == null) return;

    HapticFeedback.selectionClick();
    final bool zoomingOut = newGranularity.index < _granularity.index;

    setState(() {
      _isZoomingOut = zoomingOut;
      _granularity = newGranularity;
      _pinchScaleNotifier.value = 1.0;
      if (targetMonth != null) {
        _selectedMonth = DateTime(targetMonth.year, targetMonth.month, 1);
        _selectedDate = DateTime(targetMonth.year, targetMonth.month, 1);
        if (_monthPageController != null && _monthPageController!.hasClients) {
          _monthPageController!.jumpToPage(targetMonth.month - 1);
        }
        if (_monthWheelController.hasClients) {
          _monthWheelController.jumpToItem(targetMonth.month - 1);
        }
      }
    });

    _cameraZoomController.forward(from: 0.0);
  }

  void _stepZoomOut() {
    if (_granularity == TimelineGranularity.day) {
      _setGranularityWithAnimation(TimelineGranularity.week);
    } else if (_granularity == TimelineGranularity.week) {
      _setGranularityWithAnimation(TimelineGranularity.month);
    } else if (_granularity == TimelineGranularity.month) {
      _setGranularityWithAnimation(TimelineGranularity.semester);
    }
  }

  void _stepZoomIn() {
    if (_granularity == TimelineGranularity.semester) {
      _setGranularityWithAnimation(TimelineGranularity.month);
    } else if (_granularity == TimelineGranularity.month) {
      _setGranularityWithAnimation(TimelineGranularity.week);
    } else if (_granularity == TimelineGranularity.week) {
      _setGranularityWithAnimation(TimelineGranularity.day);
    }
  }

  void _animatePinchScaleToNeutral() {
    if ((_pinchScaleNotifier.value - 1.0).abs() < 0.002) {
      _pinchScaleNotifier.value = 1.0;
      return;
    }
    _pinchSpringStartScale = _pinchScaleNotifier.value;
    _pinchSpringController.forward(from: 0.0);
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length == 2) {
      final pts = _activePointers.values.toList();
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchSpringController.stop();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_activePointers.containsKey(event.pointer)) return;
    _activePointers[event.pointer] = event.position;

    if (_activePointers.length == 2) {
      final pts = _activePointers.values.toList();
      final currentDist = (pts[0] - pts[1]).distance;

      if (_pinchStartDistance <= 0.0) {
        _pinchStartDistance = currentDist;
        return;
      }

      if (_pinchStartDistance < 15.0) return;

      final rawRatio = currentDist / _pinchStartDistance;
      final now = DateTime.now();
      final msSinceLastStep = _lastStepZoomTime == null
          ? 9999
          : now.difference(_lastStepZoomTime!).inMilliseconds;

      // 1. Zoom In (spreading fingers apart, scale > 1.0)
      if (rawRatio > 1.0) {
        if (_granularity == TimelineGranularity.day) {
          // Limit reached: Cannot zoom in past Day view
          // Smooth rubber-band damping with a firm visual boundary limit
          final damped = 1.0 + (rawRatio - 1.0) * 0.12;
          _pinchScaleNotifier.value = damped.clamp(1.0, 1.07);
        } else {
          // Smooth live scaling while pinching
          _pinchScaleNotifier.value = rawRatio.clamp(0.92, 1.25);

          // Threshold to step to the next granularity
          if (rawRatio >= 1.16 && msSinceLastStep > 320) {
            _lastStepZoomTime = now;
            _pinchStartDistance = currentDist;
            _stepZoomIn();
          }
        }
      }
      // 2. Zoom Out (pinching fingers together, scale < 1.0)
      else if (rawRatio < 1.0) {
        if (_granularity == TimelineGranularity.semester) {
          // Limit reached: Cannot zoom out past Semester view
          // Smooth rubber-band damping with a firm visual boundary limit
          final damped = 1.0 - (1.0 - rawRatio) * 0.12;
          _pinchScaleNotifier.value = damped.clamp(0.93, 1.0);
        } else {
          // Smooth live scaling while pinching
          _pinchScaleNotifier.value = rawRatio.clamp(0.78, 1.08);

          // Threshold to step to the previous granularity
          if (rawRatio <= 0.84 && msSinceLastStep > 320) {
            _lastStepZoomTime = now;
            _pinchStartDistance = currentDist;
            _stepZoomOut();
          }
        }
      }
    }
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) {
      _pinchStartDistance = 0.0;
      _animatePinchScaleToNeutral();
    }
  }



  @override
  Widget build(BuildContext context) {
    final tutorialController = Provider.of<TutorialController>(context, listen: false);
    tutorialController.registerKey('key_calendar_header', _calendarHeaderKey);
    tutorialController.registerKey('key_calendar_legend', _calendarLegendKey);
    tutorialController.registerKey('key_calendar_grid', _calendarGridKey);

    final semesterProvider = Provider.of<SemesterProvider>(context);
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final attendanceProvider = Provider.of<AttendanceProvider>(context);

    if (semesterProvider.semester == null) {
      return const Scaffold(
        body: Center(child: Text('Semester not set')),
      );
    }

    final startDate = semesterProvider.semester!.startDate;
    final endDate = semesterProvider.semester!.endDate;

    final rs = context.rs;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final now = DateTime.now();
    final isShowingTodayMonth = _isSameMonthYear(_selectedMonth, now);

    // Provide all 12 months for the selected year to cycle through smoothly
    final monthPages = List.generate(12, (index) => DateTime(_selectedMonth.year, index + 1, 1));
    final selectedMonthIndex = _selectedMonth.month - 1;

    _monthPageController ??= PageController(initialPage: selectedMonthIndex);

    return TutorialOverlay(
      child: DayCycleBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              'Activity Calendar',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: rs.font(18),
                letterSpacing: -0.4,
              ),
            ),
            centerTitle: false,
            actions: [
              // Today shortcut button
              TextButton.icon(
                onPressed: () => _goToToday(),
                icon: Icon(
                  Icons.calendar_today_rounded,
                  size: rs.scale(14),
                  color: isShowingTodayMonth
                      ? (isDark ? Colors.white38 : Colors.black38)
                      : (isDark ? Colors.white : Colors.black),
                ),
                label: Text(
                  'Today',
                  style: GoogleFonts.inter(
                    fontSize: rs.font(13),
                    fontWeight: FontWeight.w600,
                    color: isShowingTodayMonth
                        ? (isDark ? Colors.white38 : Colors.black38)
                        : (isDark ? Colors.white : Colors.black),
                  ),
                ),
              ),
              SizedBox(width: rs.width(4)),
            ],
          ),
          body: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUpOrCancel,
            onPointerCancel: _onPointerUpOrCancel,
            child: Column(
              children: [
                // Camera Zoom Dial & Viewfinder Header
                Padding(
                  padding: EdgeInsets.fromLTRB(rs.width(16), rs.height(2), rs.width(16), rs.height(8)),
                  child: KeyedSubtree(
                    key: _calendarHeaderKey,
                    child: _buildControlsRow(context, startDate, endDate),
                  ),
                ),

                // Main Timeline View with Smooth Pinch-to-Zoom & Perspective Camera Animation
                Expanded(
                  child: KeyedSubtree(
                    key: _calendarGridKey,
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_cameraZoomAnimation, _pinchScaleNotifier]),
                        builder: (context, child) {
                          final t = _cameraZoomAnimation.value;
                          final isPinching = _activePointers.length >= 2;
                          final animScale = isPinching
                              ? 1.0
                              : (_isZoomingOut
                                  ? lerpDouble(1.06, 1.0, t)!
                                  : lerpDouble(0.94, 1.0, t)!);
                          final totalScale = animScale * _pinchScaleNotifier.value;
                          final opacity = lerpDouble(0.55, 1.0, t)!;
                          return Opacity(
                            opacity: opacity,
                            child: Transform.scale(
                              scale: totalScale,
                              child: child,
                            ),
                          );
                        },
                        child: _buildTimelineContent(
                          monthPages: monthPages,
                          startDate: startDate,
                          endDate: endDate,
                          subjects: subjectProvider.subjects,
                          attendanceRecords: attendanceProvider.attendanceRecords,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Top Context Header & Minimalist Granularity Dropdown Filter
  Widget _buildControlsRow(BuildContext context, DateTime startDate, DateTime endDate) {
    final rs = context.rs;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String periodTitle;
    IconData periodIcon;
    switch (_granularity) {
      case TimelineGranularity.semester:
        periodTitle = 'Semester (6 Months)';
        periodIcon = Icons.auto_awesome_mosaic_rounded;
        break;
      case TimelineGranularity.month:
        periodTitle = '${_selectedMonth.year}';
        periodIcon = Icons.calendar_view_month_rounded;
        break;
      case TimelineGranularity.week:
        periodTitle = 'Week of ${_getShortMonthName(_selectedDate.month)} ${_selectedDate.day}';
        periodIcon = Icons.view_week_rounded;
        break;
      case TimelineGranularity.day:
        periodTitle = '${_selectedDate.day} ${_getShortMonthName(_selectedDate.month)} ${_selectedDate.year}';
        periodIcon = Icons.today_rounded;
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left: Context Title & Icon
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: rs.insetsAll(4.5),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  periodIcon,
                  size: rs.scale(13),
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              SizedBox(width: rs.width(7)),
              Flexible(
                child: Text(
                  periodTitle,
                  style: GoogleFonts.inter(
                    fontSize: rs.font(14),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        SizedBox(width: rs.width(6)),

        // Right Actions: Status Filter Dropdown & Granularity Dropdown
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KeyedSubtree(
              key: _calendarLegendKey,
              child: _buildStatusFilterDropdown(context, rs, isDark),
            ),
            SizedBox(width: rs.width(6)),
            _buildGranularityDropdown(context, rs, isDark),
          ],
        ),
      ],
    );
  }

  /// Minimal, compact, and elegant dropdown menu for filtering attendance status
  Widget _buildStatusFilterDropdown(BuildContext context, ResponsiveScale rs, bool isDark) {
    String filterLabel;
    Color? filterColor;
    if (_selectedStateFilter == null) {
      filterLabel = 'Status';
      filterColor = null;
    } else {
      filterColor = CalendarUtils.getStateColor(_selectedStateFilter!);
      switch (_selectedStateFilter!) {
        case DayState.attendedFullDay:
          filterLabel = 'Present';
          break;
        case DayState.bunkedFullDay:
          filterLabel = 'Absent';
          break;
        case DayState.classesMarked:
          filterLabel = 'Mixed';
          break;
        case DayState.classesNotMarked:
          filterLabel = 'Unmarked';
          break;
        case DayState.plannedLeave:
          filterLabel = 'Leave';
          break;
        case DayState.holiday:
          filterLabel = 'Holiday';
          break;
        case DayState.futureClasses:
          filterLabel = 'Upcoming';
          break;
        case DayState.noClasses:
          filterLabel = 'Off';
          break;
        case DayState.locked:
          filterLabel = 'Locked';
          break;
      }
    }

    final options = <(DayState?, String, Color, IconData)>[
      (null, 'All Status', isDark ? Colors.white60 : Colors.black54, Icons.clear_all_rounded),
      (DayState.attendedFullDay, 'Present', CalendarUtils.getStateColor(DayState.attendedFullDay), Icons.check_rounded),
      (DayState.bunkedFullDay, 'Absent', CalendarUtils.getStateColor(DayState.bunkedFullDay), Icons.close_rounded),
      (DayState.classesMarked, 'Mixed', CalendarUtils.getStateColor(DayState.classesMarked), Icons.pie_chart_outline_rounded),
      (DayState.classesNotMarked, 'Unmarked', CalendarUtils.getStateColor(DayState.classesNotMarked), Icons.radio_button_unchecked_rounded),
      (DayState.plannedLeave, 'Leave', CalendarUtils.getStateColor(DayState.plannedLeave), Icons.event_busy_rounded),
      (DayState.holiday, 'Holiday', CalendarUtils.getStateColor(DayState.holiday), Icons.pause_circle_outline_rounded),
      (DayState.futureClasses, 'Upcoming', CalendarUtils.getStateColor(DayState.futureClasses), Icons.schedule_rounded),
      (DayState.noClasses, 'Off Day', CalendarUtils.getStateColor(DayState.noClasses), Icons.event_available_rounded),
    ];

    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: PopupMenuButton<DayState?>(
        tooltip: 'Filter Status',
        onSelected: (state) {
          HapticFeedback.selectionClick();
          setState(() => _selectedStateFilter = state);
        },
        offset: Offset(0, rs.height(36)),
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.65 : 0.2),
        color: isDark ? const Color(0xFF16161D) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rs.scale(14)),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        padding: EdgeInsets.zero,
        itemBuilder: (context) {
          return options.map((opt) {
            final isSelected = _selectedStateFilter == opt.$1;
            return PopupMenuItem<DayState?>(
              value: opt.$1,
              height: rs.height(40),
              padding: EdgeInsets.symmetric(horizontal: rs.width(12)),
              child: Row(
                children: [
                  if (opt.$1 == null)
                    Icon(
                      opt.$4,
                      size: rs.scale(15),
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.black)
                          : (isDark ? Colors.white54 : Colors.black45),
                    )
                  else
                    Container(
                      width: rs.scale(2.5),
                      height: rs.height(11),
                      decoration: BoxDecoration(
                        color: opt.$3,
                        borderRadius: BorderRadius.circular(rs.scale(1)),
                      ),
                    ),
                  SizedBox(width: rs.width(10)),
                  Expanded(
                    child: Text(
                      opt.$2,
                      style: GoogleFonts.inter(
                        fontSize: rs.font(12.5),
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? (isDark ? Colors.white : Colors.black)
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                  if (isSelected)
                    Container(
                      width: rs.scale(5),
                      height: rs.scale(5),
                      decoration: BoxDecoration(
                        color: opt.$1 == null
                            ? (isDark ? Colors.white : Colors.black)
                            : opt.$3,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            );
          }).toList();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(rs.scale(16)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: rs.width(9),
                vertical: rs.height(6),
              ),
              decoration: BoxDecoration(
                color: _selectedStateFilter != null
                    ? (filterColor?.withValues(alpha: isDark ? 0.16 : 0.10) ??
                        (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)))
                    : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04)),
                borderRadius: BorderRadius.circular(rs.scale(16)),
                border: Border.all(
                  color: _selectedStateFilter != null
                      ? (filterColor?.withValues(alpha: 0.45) ??
                          (isDark ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.09)))
                      : (isDark ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.09)),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selectedStateFilter != null && filterColor != null) ...[
                    Container(
                      width: rs.scale(2.5),
                      height: rs.height(10),
                      decoration: BoxDecoration(
                        color: filterColor,
                        borderRadius: BorderRadius.circular(rs.scale(1)),
                      ),
                    ),
                    SizedBox(width: rs.width(5)),
                  ] else ...[
                    Icon(
                      Icons.filter_list_rounded,
                      size: rs.scale(13),
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    SizedBox(width: rs.width(5)),
                  ],
                  Text(
                    filterLabel,
                    style: GoogleFonts.inter(
                      fontSize: rs.font(12),
                      fontWeight: _selectedStateFilter != null ? FontWeight.w700 : FontWeight.w600,
                      letterSpacing: -0.1,
                      color: _selectedStateFilter != null && filterColor != null
                          ? filterColor
                          : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  SizedBox(width: rs.width(3)),
                  if (_selectedStateFilter != null)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedStateFilter = null);
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: rs.width(2)),
                        child: Icon(
                          Icons.close_rounded,
                          size: rs.scale(13),
                          color: filterColor ?? (isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    )
                  else
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: rs.scale(16),
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Minimal, compact, and elegant dropdown menu for switching filters
  Widget _buildGranularityDropdown(BuildContext context, ResponsiveScale rs, bool isDark) {
    String activeLabel;
    IconData activeIcon;
    switch (_granularity) {
      case TimelineGranularity.semester:
        activeLabel = 'Semester';
        activeIcon = Icons.auto_awesome_mosaic_rounded;
        break;
      case TimelineGranularity.month:
        activeLabel = 'Monthly';
        activeIcon = Icons.calendar_view_month_rounded;
        break;
      case TimelineGranularity.week:
        activeLabel = 'Weekly';
        activeIcon = Icons.view_week_rounded;
        break;
      case TimelineGranularity.day:
        activeLabel = 'Daily';
        activeIcon = Icons.today_rounded;
        break;
    }

    final options = <(TimelineGranularity, String, IconData, String)>[
      (TimelineGranularity.week, 'Weekly', Icons.view_week_rounded, '7-day schedule view'),
      (TimelineGranularity.month, 'Monthly', Icons.calendar_view_month_rounded, '30-day activity heatmap'),
      (TimelineGranularity.semester, 'Semester', Icons.auto_awesome_mosaic_rounded, '6-month semester overview'),
      if (_granularity == TimelineGranularity.day)
        (TimelineGranularity.day, 'Daily Focus', Icons.today_rounded, 'Single day timeline view'),
    ];

    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: PopupMenuButton<TimelineGranularity>(
        tooltip: 'Filter View',
        onSelected: (granularity) {
          HapticFeedback.selectionClick();
          _setGranularityWithAnimation(granularity);
        },
        offset: Offset(0, rs.height(36)),
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.65 : 0.2),
        color: isDark ? const Color(0xFF16161D) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(rs.scale(14)),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        padding: EdgeInsets.zero,
        itemBuilder: (context) {
          return options.map((opt) {
            final isSelected = _granularity == opt.$1;
            return PopupMenuItem<TimelineGranularity>(
              value: opt.$1,
              height: rs.height(40),
              padding: EdgeInsets.symmetric(horizontal: rs.width(12)),
              child: Row(
                children: [
                  Icon(
                    opt.$3,
                    size: rs.scale(15),
                    color: isSelected
                        ? (isDark ? Colors.white : Colors.black)
                        : (isDark ? Colors.white54 : Colors.black45),
                  ),
                  SizedBox(width: rs.width(10)),
                  Expanded(
                    child: Text(
                      opt.$2,
                      style: GoogleFonts.inter(
                        fontSize: rs.font(12.5),
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? (isDark ? Colors.white : Colors.black)
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                  if (isSelected)
                    Container(
                      width: rs.scale(5),
                      height: rs.scale(5),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white : Colors.black,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            );
          }).toList();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(rs.scale(16)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: rs.width(10),
                vertical: rs.height(6),
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(rs.scale(16)),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.black.withValues(alpha: 0.09),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    activeIcon,
                    size: rs.scale(13),
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  SizedBox(width: rs.width(6)),
                  Text(
                    activeLabel,
                    style: GoogleFonts.inter(
                      fontSize: rs.font(12),
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  SizedBox(width: rs.width(4)),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: rs.scale(16),
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Vertical rolling wheel month picker (iOS clock / timer style) on the Current Month Header
  Widget _buildBigMonthWheel(BuildContext context, ResponsiveScale rs, bool isDark) {
    final selectedIndex = (_selectedMonth.month - 1).clamp(0, 11);

    return SizedBox(
      height: rs.height(44),
      child: ListWheelScrollView.useDelegate(
        controller: _monthWheelController,
        itemExtent: rs.height(38),
        diameterRatio: 1.4,
        perspective: 0.003,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (index) {
          HapticFeedback.selectionClick();
          final newMonth = DateTime(_selectedMonth.year, index + 1, 1);
          setState(() {
            _selectedMonth = newMonth;
            _selectedDate = DateTime(newMonth.year, newMonth.month, 1);
          });
          if (_monthPageController != null &&
              _monthPageController!.hasClients &&
              _monthPageController!.page?.round() != index) {
            _monthPageController!.animateToPage(
              index,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          }
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: 12,
          builder: (context, index) {
            final isCur = index == selectedIndex;
            return Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _getMonthName(index + 1),
                style: GoogleFonts.inter(
                  fontSize: isCur ? rs.font(28) : rs.font(22),
                  fontWeight: isCur ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: -0.6,
                  color: isCur
                      ? (isDark ? Colors.white : Colors.black)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.28)
                          : Colors.black.withValues(alpha: 0.28)),
                ),
                maxLines: 1,
              ),
            );
          },
        ),
      ),
    );
  }



  /// Switch between the 4 Timeline Views
  Widget _buildTimelineContent({
    required List<DateTime> monthPages,
    required DateTime startDate,
    required DateTime endDate,
    required List<Subject> subjects,
    required List<Attendance> attendanceRecords,
  }) {
    switch (_granularity) {
      case TimelineGranularity.semester:
        return _buildSemesterTimelineView(
          startDate: startDate,
          endDate: endDate,
          subjects: subjects,
          attendanceRecords: attendanceRecords,
        );
      case TimelineGranularity.month:
        return _buildMonthGridView(
          monthPages: monthPages,
          startDate: startDate,
          endDate: endDate,
          subjects: subjects,
          attendanceRecords: attendanceRecords,
        );
      case TimelineGranularity.week:
        return _buildWeekTimelineView(
          subjects: subjects,
          attendanceRecords: attendanceRecords,
        );
      case TimelineGranularity.day:
        return _buildDayTimelineView(
          subjects: subjects,
          attendanceRecords: attendanceRecords,
        );
    }
  }

  // ==========================================
  // 1. SEMESTER TIMELINE (Complete 6 Months Grid)
  // ==========================================
  Widget _buildSemesterTimelineView({
    required DateTime startDate,
    required DateTime endDate,
    required List<Subject> subjects,
    required List<Attendance> attendanceRecords,
  }) {
    final rs = context.rs;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Map<DateTime, List<Attendance>> indexedRecords = {};
    for (final record in attendanceRecords) {
      final norm = DateTime(record.date.year, record.date.month, record.date.day);
      indexedRecords.putIfAbsent(norm, () => []).add(record);
    }

    // Generate the 6 consecutive months covering the complete semester
    final semesterMonths = List.generate(6, (i) {
      final m = startDate.month + i;
      final yearOffset = (m - 1) ~/ 12;
      final monthInYear = ((m - 1) % 12) + 1;
      return DateTime(startDate.year + yearOffset, monthInYear, 1);
    });

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(rs.scale(16)),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: rs.height(14),
        crossAxisSpacing: rs.width(14),
        childAspectRatio: 1.15,
      ),
      itemCount: 6,
      itemBuilder: (context, mIndex) {
        final monthDate = semesterMonths[mIndex];
        final isSelected = _selectedMonth.year == monthDate.year && _selectedMonth.month == monthDate.month;

        // Calculate aggregate ratio for this semester month
        int totalHeld = 0;
        int totalAttended = 0;
        final lastDay = DateTime(monthDate.year, monthDate.month + 1, 0).day;
        for (int d = 1; d <= lastDay; d++) {
          final date = DateTime(monthDate.year, monthDate.month, d);
          final dayInfo = CalendarUtils.getDayState(
            date: date,
            subjects: subjects,
            attendanceRecords: attendanceRecords,
            indexedRecords: indexedRecords,
            plannedLeaves: _plannedLeaves,
          );
          totalHeld += dayInfo.classesCount;
          totalAttended += dayInfo.attendedCount;
        }
        final monthRatio = totalHeld > 0 ? (totalAttended / totalHeld) : 0.0;

        return GestureDetector(
          onTap: () {
            _setGranularityWithAnimation(TimelineGranularity.month, targetMonth: monthDate);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(rs.scale(20)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: EdgeInsets.all(rs.scale(14)),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.black.withValues(alpha: 0.08))
                      : (isDark
                          ? const Color(0xFF0F0F14).withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.58)),
                  borderRadius: BorderRadius.circular(rs.scale(20)),
                  border: Border.all(
                    color: isSelected
                        ? (isDark ? Colors.white : Colors.black)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.14)
                            : Colors.black.withValues(alpha: 0.08)),
                    width: isSelected ? 1.4 : 1.0,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _getMonthName(monthDate.month),
                          style: GoogleFonts.inter(
                            fontSize: rs.font(14.5),
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        Text(
                          '${monthDate.year}',
                          style: GoogleFonts.inter(
                            fontSize: rs.font(11),
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        CustomPaint(
                          size: Size(rs.scale(38), rs.scale(38)),
                          painter: _ActivityRingPainter(
                            ratio: monthRatio,
                            ringColor: const Color(0xFFFF8A00),
                            trackColor: isDark ? const Color(0xFF232328) : const Color(0xFFE4E4E8),
                            strokeWidth: rs.scale(3.8),
                          ),
                        ),
                        SizedBox(width: rs.width(12)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              totalHeld > 0 ? '${(monthRatio * 100).toInt()}%' : 'N/A',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(16.5),
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            Text(
                              totalHeld > 0 ? '$totalAttended/$totalHeld held' : 'No classes',
                              style: GoogleFonts.inter(
                                fontSize: rs.font(10.5),
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // 2. MONTH TIMELINE (Grid with Activity Rings)
  // ==========================================
  Widget _buildMonthGridView({
    required List<DateTime> monthPages,
    required DateTime startDate,
    required DateTime endDate,
    required List<Subject> subjects,
    required List<Attendance> attendanceRecords,
  }) {
    final rs = context.rs;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current Month Header - Interactive iOS Clock-style Vertical Wheel
        Padding(
          padding: EdgeInsets.only(
            left: rs.scale(20),
            right: rs.scale(16),
            top: rs.scale(4),
            bottom: rs.scale(6),
          ),
          child: _buildBigMonthWheel(context, rs, isDark),
        ),

        // 12 Months PageView Grid
        Expanded(
          child: PageView.builder(
            controller: _monthPageController,
            itemCount: monthPages.length,
            onPageChanged: (index) {
              setState(() {
                _selectedMonth = monthPages[index];
              });
              if (_monthWheelController.hasClients && _monthWheelController.selectedItem != index) {
                _monthWheelController.animateToItem(
                  index,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                );
              }
            },
            itemBuilder: (context, index) {
              final month = monthPages[index];
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    rs.scale(16),
                    0,
                    rs.scale(16),
                    rs.scale(24),
                  ),
                  child: _buildMonthCard(
                    month: month,
                    startDate: startDate,
                    endDate: endDate,
                    subjects: subjects,
                    attendanceRecords: attendanceRecords,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMonthCard({
    required DateTime month,
    required DateTime startDate,
    required DateTime endDate,
    required List<Subject> subjects,
    required List<Attendance> attendanceRecords,
  }) {
    final rs = context.rs;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final lastDayOfMonth = DateTime(month.year, month.month + 1, 0);

    final displayStartDate = firstDayOfMonth;
    final displayEndDate = lastDayOfMonth;

    final int daysInMonth = displayEndDate.difference(displayStartDate).inDays + 1;
    final int firstWeekday = displayStartDate.weekday;

    final Map<DateTime, List<Attendance>> indexedRecords = {};
    for (final record in attendanceRecords) {
      final normalizedDate = DateTime(record.date.year, record.date.month, record.date.day);
      indexedRecords.putIfAbsent(normalizedDate, () => []).add(record);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Single letter weekday headers: M  T  W  T  F  S  S
        Padding(
          padding: EdgeInsets.only(bottom: rs.height(10)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((letter) {
              return Expanded(
                child: Text(
                  letter,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: rs.font(12.5),
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // Days Grid with Activity Rings
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: rs.height(10),
            crossAxisSpacing: rs.width(4),
            childAspectRatio: 0.82,
          ),
          itemCount: (firstWeekday - 1) + daysInMonth,
          itemBuilder: (context, index) {
            if (index < firstWeekday - 1) {
              return const SizedBox.shrink();
            }

            final dayOffset = index - (firstWeekday - 1);
            final date = displayStartDate.add(Duration(days: dayOffset));

            final dayInfo = CalendarUtils.getDayState(
              date: date,
              subjects: subjects,
              attendanceRecords: attendanceRecords,
              indexedRecords: indexedRecords,
              plannedLeaves: _plannedLeaves,
            );

            return _buildDayRingCell(context, dayInfo);
          },
        ),
      ],
    );
  }

  Widget _buildDayRingCell(BuildContext context, CalendarDayInfo dayInfo) {
    final rs = context.rs;
    final now = DateTime.now();
    final isToday = CalendarUtils.isSameDay(dayInfo.date, now);
    final isSelected = CalendarUtils.isSameDay(_selectedDate, dayInfo.date);

    final matchesFilter = _selectedStateFilter == null || dayInfo.state == _selectedStateFilter;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final trackColor = isDark ? const Color(0xFF222227) : const Color(0xFFE5E5EB);

    Color ringColor;
    double progressRatio;

    switch (dayInfo.state) {
      case DayState.attendedFullDay:
        ringColor = const Color(0xFFFF8A00);
        progressRatio = 1.0;
        break;
      case DayState.classesMarked:
        ringColor = const Color(0xFFFF8A00);
        progressRatio = dayInfo.attendanceRatio > 0 ? dayInfo.attendanceRatio : 0.25;
        break;
      case DayState.bunkedFullDay:
        ringColor = const Color(0xFFEF4444);
        progressRatio = 1.0;
        break;
      case DayState.holiday:
        ringColor = const Color(0xFF8B5CF6);
        progressRatio = 1.0;
        break;
      case DayState.plannedLeave:
        ringColor = const Color(0xFF06B6D4);
        progressRatio = 1.0;
        break;
      case DayState.classesNotMarked:
        ringColor = const Color(0xFFF59E0B);
        progressRatio = 0.5;
        break;
      case DayState.futureClasses:
        ringColor = const Color(0xFF64748B);
        progressRatio = 0.0;
        break;
      case DayState.noClasses:
      case DayState.locked:
        ringColor = Colors.transparent;
        progressRatio = 0.0;
        break;
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedDate = dayInfo.date;
        });
        _showDayDetailsDialog(context, dayInfo);
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: matchesFilter ? 1.0 : 0.2,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(rs.scale(14)),
            border: Border.all(
              color: isSelected
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.28)
                      : Colors.black.withValues(alpha: 0.20))
                  : (isToday
                      ? (isDark
                          ? Colors.white.withValues(alpha: 0.35)
                          : Colors.black.withValues(alpha: 0.25))
                      : Colors.transparent),
              width: isSelected || isToday ? 1.2 : 0.0,
            ),
          ),
          padding: EdgeInsets.symmetric(vertical: rs.height(3)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${dayInfo.date.day}',
                style: GoogleFonts.inter(
                  fontSize: rs.font(12.5),
                  fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: rs.height(5)),
              CustomPaint(
                size: Size(rs.scale(22), rs.scale(22)),
                painter: _ActivityRingPainter(
                  ratio: progressRatio,
                  ringColor: ringColor,
                  trackColor: trackColor,
                  strokeWidth: rs.scale(3.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 3. WEEK TIMELINE (Interactive 7-Day Ribbon)
  // ==========================================
  Widget _buildWeekTimelineView({
    required List<Subject> subjects,
    required List<Attendance> attendanceRecords,
  }) {
    final rs = context.rs;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Determine week start (Monday) and week end (Sunday) of _selectedDate
    final weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
    final weekDays = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    final Map<DateTime, List<Attendance>> indexedRecords = {};
    for (final record in attendanceRecords) {
      final norm = DateTime(record.date.year, record.date.month, record.date.day);
      indexedRecords.putIfAbsent(norm, () => []).add(record);
    }

    return Padding(
      padding: EdgeInsets.all(rs.scale(16)),
      child: Column(
        children: [
          // Week Navigator Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedDate = _selectedDate.subtract(const Duration(days: 7));
                    _selectedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
                  });
                },
              ),
              Text(
                '${_formatShortMonthDay(weekDays.first)} – ${_formatShortMonthDay(weekDays.last)}',
                style: GoogleFonts.inter(
                  fontSize: rs.font(15),
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedDate = _selectedDate.add(const Duration(days: 7));
                    _selectedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
                  });
                },
              ),
            ],
          ),
          SizedBox(height: rs.height(10)),

          // 7 Day Cards
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: 7,
              itemBuilder: (context, index) {
                final date = weekDays[index];
                final dayInfo = CalendarUtils.getDayState(
                  date: date,
                  subjects: subjects,
                  attendanceRecords: attendanceRecords,
                  indexedRecords: indexedRecords,
                  plannedLeaves: _plannedLeaves,
                );
                final isSelected = CalendarUtils.isSameDay(date, _selectedDate);
                final stateColor = CalendarUtils.getStateColor(dayInfo.state);

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedDate = date;
                    });
                    _showDayDetailsDialog(context, dayInfo);
                  },
                  child: Container(
                    margin: EdgeInsets.only(bottom: rs.height(8)),
                    padding: EdgeInsets.symmetric(horizontal: rs.width(14), vertical: rs.height(10)),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark
                              ? Colors.white.withValues(alpha: 0.16)
                              : Colors.black.withValues(alpha: 0.08))
                          : (isDark
                              ? const Color(0xFF14141C).withValues(alpha: 0.65)
                              : Colors.white.withValues(alpha: 0.75)),
                      borderRadius: BorderRadius.circular(rs.scale(16)),
                      border: Border.all(
                        color: isSelected
                            ? (isDark ? Colors.white : Colors.black)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.14)
                                : Colors.white.withValues(alpha: 0.60)),
                        width: isSelected ? 1.2 : 0.9,
                      ),
                        ),
                        child: Row(
                          children: [
                            CustomPaint(
                              size: Size(rs.scale(26), rs.scale(26)),
                              painter: _ActivityRingPainter(
                                ratio: dayInfo.attendanceRatio > 0 ? dayInfo.attendanceRatio : (dayInfo.state == DayState.attendedFullDay ? 1.0 : 0.0),
                                ringColor: stateColor,
                                trackColor: isDark ? const Color(0xFF222227) : const Color(0xFFE5E5EB),
                                strokeWidth: rs.scale(3.2),
                              ),
                            ),
                            SizedBox(width: rs.width(12)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatTimelineDate(date),
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: rs.font(13.5),
                                      color: isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                  Text(
                                    dayInfo.classesCount > 0
                                        ? '${dayInfo.attendedCount} of ${dayInfo.classesCount} attended'
                                        : 'No classes',
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(11.5),
                                      color: isDark ? Colors.white54 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (dayInfo.state == DayState.noClasses)
                              Text(
                                'No classes',
                                style: GoogleFonts.inter(
                                  fontSize: rs.font(11),
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? const Color(0xFF52525B) : const Color(0xFFA1A1AA),
                                ),
                              )
                            else
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: rs.scale(2.5),
                                    height: rs.height(10),
                                    decoration: BoxDecoration(
                                      color: stateColor,
                                      borderRadius: BorderRadius.circular(rs.scale(1)),
                                    ),
                                  ),
                                  SizedBox(width: rs.width(5)),
                                  Text(
                                    _getStateLabel(dayInfo.state).toUpperCase(),
                                    style: GoogleFonts.inter(
                                      fontSize: rs.font(10),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: stateColor,
                                    ),
                                  ),
                                ],
                              ),
                          ],
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

  // ==========================================
  // 4. DAY TIMELINE (Focused Daily Schedule)
  // ==========================================
  Widget _buildDayTimelineView({
    required List<Subject> subjects,
    required List<Attendance> attendanceRecords,
  }) {
    final rs = context.rs;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final attendanceProvider = Provider.of<AttendanceProvider>(context);
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);

    final dayInfo = CalendarUtils.getDayState(
      date: _selectedDate,
      subjects: subjects,
      attendanceRecords: attendanceRecords,
      plannedLeaves: _plannedLeaves,
    );

    final classesForDay = _expandSubjectsBySlotForDay(
      dayInfo.subjectsWithClassesToday,
      _selectedDate,
    );

    return Padding(
      padding: EdgeInsets.all(rs.scale(16)),
      child: Column(
        children: [
          // Day Switcher Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                    _selectedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
                  });
                },
              ),
              Text(
                _formatDate(_selectedDate),
                style: GoogleFonts.inter(
                  fontSize: rs.font(15),
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedDate = _selectedDate.add(const Duration(days: 1));
                    _selectedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
                  });
                },
              ),
            ],
          ),
          SizedBox(height: rs.height(10)),

          // Classes List for this Day
          Expanded(
            child: classesForDay.isEmpty
                ? Center(
                    child: Text(
                      'No classes scheduled for this day',
                      style: GoogleFonts.inter(
                        fontSize: rs.font(13),
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: classesForDay.length,
                    itemBuilder: (context, index) {
                      final sub = classesForDay[index];
                      final slot = sub.schedule.first;
                      final slotKey = slot.slotKey;

                      final record = dayInfo.attendanceRecordsToday
                          .cast<Attendance?>()
                          .firstWhere(
                            (r) =>
                                r != null &&
                                r.subjectId == sub.id &&
                                (r.slotKey == null || r.slotKey == slotKey || r.slotKey!.isEmpty),
                            orElse: () => null,
                          );

                      return _buildSubjectAttendanceRow(
                        context,
                        sub,
                        record,
                        _selectedDate,
                        dayInfo.state,
                        attendanceProvider,
                        () => setState(() {}),
                        timeFormatProvider,
                        slotKey,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }



  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _selectedMonth = DateTime(now.year, now.month, 1);
      _selectedDate = DateTime(now.year, now.month, now.day);
      _granularity = TimelineGranularity.month;
    });

    if (_monthPageController != null && _monthPageController!.hasClients) {
      _monthPageController!.animateToPage(
        now.month - 1,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
    }
    if (_monthWheelController.hasClients && _monthWheelController.selectedItem != now.month - 1) {
      _monthWheelController.animateToItem(
        now.month - 1,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  bool _isSameMonthYear(DateTime first, DateTime second) {
    return first.year == second.year && first.month == second.month;
  }

  // --- Day Details Bottom Sheet Modal ---
  void _showDayDetailsDialog(BuildContext context, CalendarDayInfo dayInfo) {
    final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
    final subjectProvider = Provider.of<SubjectProvider>(context, listen: false);
    final semesterProvider = Provider.of<SemesterProvider>(context, listen: false);

    if (semesterProvider.semester == null) return;

    final startDate = semesterProvider.semester!.startDate;
    final endDate = semesterProvider.semester!.endDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildDayDetailsModal(
        context,
        dayInfo,
        subjectProvider,
        attendanceProvider,
        startDate,
        endDate,
      ),
    );
  }

  Widget _buildDayDetailsModal(
    BuildContext context,
    CalendarDayInfo dayInfo,
    SubjectProvider subjectProvider,
    AttendanceProvider attendanceProvider,
    DateTime startDate,
    DateTime endDate,
  ) {
    final rs = context.rs;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);

    final swipableDates = _getSwipableDayDates(
      currentDate: dayInfo.date,
      startDate: startDate,
      endDate: endDate,
      subjects: subjectProvider.subjects,
      attendanceRecords: attendanceProvider.attendanceRecords,
    );
    final initialPageIndex = swipableDates.indexWhere(
      (d) => CalendarUtils.isSameDay(d, dayInfo.date),
    );
    final dayPageController = PageController(
      initialPage: initialPageIndex < 0 ? 0 : initialPageIndex,
    );

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(rs.scale(28))),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0C0C12).withValues(alpha: 0.68)
                : Colors.white.withValues(alpha: 0.76),
            borderRadius: BorderRadius.vertical(top: Radius.circular(rs.scale(28))),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.black.withValues(alpha: 0.10),
              width: 1.0,
            ),
          ),
          child: Column(
            children: [
              SizedBox(height: rs.height(10)),
              Container(
                width: rs.width(36),
                height: rs.height(4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(rs.scale(2)),
                ),
              ),
              SizedBox(height: rs.height(6)),

              Expanded(
                child: PageView.builder(
                  controller: dayPageController,
                  itemCount: swipableDates.length,
                  itemBuilder: (context, pageIndex) {
                    final pageDate = swipableDates[pageIndex];
                    final pageDayInfo = CalendarUtils.getDayState(
                      date: pageDate,
                      subjects: subjectProvider.subjects,
                      attendanceRecords: attendanceProvider.attendanceRecords,
                      plannedLeaves: _plannedLeaves,
                    );
                    final classesForDay = _expandSubjectsBySlotForDay(
                      pageDayInfo.subjectsWithClassesToday,
                      pageDate,
                    );
                    final stateColor = CalendarUtils.getStateColor(pageDayInfo.state);

                    final activeLeave = _plannedLeaves.cast<PlannedLeave?>().firstWhere(
                          (leave) =>
                              leave != null &&
                              pageDate.isAfter(leave.startDate.subtract(const Duration(days: 1))) &&
                              pageDate.isBefore(leave.endDate),
                          orElse: () => null,
                        );

                    return StatefulBuilder(
                      builder: (context, setModalState) {
                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: rs.width(18)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _formatDate(pageDate),
                                          style: GoogleFonts.inter(
                                            fontSize: rs.font(17),
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.3,
                                            color: isDark ? Colors.white : Colors.black,
                                          ),
                                        ),
                                        SizedBox(height: rs.height(2)),
                                        Text(
                                          '${classesForDay.length} class(es) scheduled',
                                          style: GoogleFonts.inter(
                                            fontSize: rs.font(12.5),
                                            color: isDark ? Colors.white60 : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: rs.scale(2.5),
                                        height: rs.height(12),
                                        decoration: BoxDecoration(
                                          color: stateColor,
                                          borderRadius: BorderRadius.circular(rs.scale(1)),
                                        ),
                                      ),
                                      SizedBox(width: rs.width(6)),
                                      Text(
                                        _getStateLabel(pageDayInfo.state).toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: rs.font(11),
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.6,
                                          color: stateColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              if (activeLeave != null) ...[
                                SizedBox(height: rs.height(10)),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: rs.width(10),
                                    vertical: rs.height(7),
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(rs.scale(8)),
                                    border: Border.all(
                                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: rs.scale(2.5),
                                        height: rs.height(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF06B6D4),
                                          borderRadius: BorderRadius.circular(rs.scale(1)),
                                        ),
                                      ),
                                      SizedBox(width: rs.width(8)),
                                      Expanded(
                                        child: Text(
                                          'Leave: ${activeLeave.name}',
                                          style: GoogleFonts.inter(
                                            fontSize: rs.font(11.5),
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? Colors.white70 : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              SizedBox(height: rs.height(14)),

                              if (classesForDay.isNotEmpty)
                                Row(
                                  children: [
                                    _buildModalActionPill(
                                      label: 'All Present',
                                      icon: Icons.check_circle_outline_rounded,
                                      color: const Color(0xFFFF8A00),
                                      onPressed: () async {
                                        for (final sub in classesForDay) {
                                          final slotKey = sub.schedule.isNotEmpty
                                              ? sub.schedule.first.slotKey
                                              : '';
                                          await attendanceProvider.markAttendance(
                                            sub.id,
                                            pageDate,
                                            AttendanceStatus.attended,
                                            slotKey: slotKey,
                                          );
                                        }
                                        setModalState(() {});
                                      },
                                    ),
                                    SizedBox(width: rs.width(8)),
                                    _buildModalActionPill(
                                      label: 'All Absent',
                                      icon: Icons.highlight_off_rounded,
                                      color: const Color(0xFFEF4444),
                                      onPressed: () async {
                                        for (final sub in classesForDay) {
                                          final slotKey = sub.schedule.isNotEmpty
                                              ? sub.schedule.first.slotKey
                                              : '';
                                          await attendanceProvider.markAttendance(
                                            sub.id,
                                            pageDate,
                                            AttendanceStatus.absent,
                                            slotKey: slotKey,
                                          );
                                        }
                                        setModalState(() {});
                                      },
                                    ),
                                    SizedBox(width: rs.width(8)),
                                    _buildModalActionPill(
                                      label: 'Clear',
                                      icon: Icons.refresh_rounded,
                                      color: isDark ? Colors.white60 : Colors.black54,
                                      onPressed: () async {
                                        for (final sub in classesForDay) {
                                          final slotKey = sub.schedule.isNotEmpty
                                              ? sub.schedule.first.slotKey
                                              : '';
                                          await attendanceProvider.deleteRecordForSubjectOnDate(
                                            sub.id,
                                            pageDate,
                                            slotKey: slotKey,
                                          );
                                        }
                                        setModalState(() {});
                                      },
                                    ),
                                  ],
                                ),

                              SizedBox(height: rs.height(12)),

                              Expanded(
                                child: classesForDay.isEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.event_available_rounded,
                                              size: rs.scale(36),
                                              color: isDark ? Colors.white24 : Colors.black26,
                                            ),
                                            SizedBox(height: rs.height(8)),
                                            Text(
                                              'No classes on this day',
                                              style: GoogleFonts.inter(
                                                fontSize: rs.font(13),
                                                color: isDark ? Colors.white54 : Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: classesForDay.length,
                                        itemBuilder: (context, classIndex) {
                                          final sub = classesForDay[classIndex];
                                          final slot = sub.schedule.first;
                                          final slotKey = slot.slotKey;

                                          final record = pageDayInfo.attendanceRecordsToday
                                              .cast<Attendance?>()
                                              .firstWhere(
                                                (r) =>
                                                    r != null &&
                                                    r.subjectId == sub.id &&
                                                    (r.slotKey == null ||
                                                        r.slotKey == slotKey ||
                                                        r.slotKey!.isEmpty),
                                                orElse: () => null,
                                              );

                                          return _buildSubjectAttendanceRow(
                                            context,
                                            sub,
                                            record,
                                            pageDate,
                                            pageDayInfo.state,
                                            attendanceProvider,
                                            () => setModalState(() {}),
                                            timeFormatProvider,
                                            slotKey,
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModalActionPill({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final rs = context.rs;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: rs.height(7)),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(rs.scale(10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: rs.scale(12), color: color),
              SizedBox(width: rs.width(4)),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: rs.font(11),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectAttendanceRow(
    BuildContext context,
    Subject subject,
    Attendance? attendance,
    DateTime date,
    DayState dayState,
    AttendanceProvider attendanceProvider,
    VoidCallback onRefresh,
    TimeFormatProvider timeFormatProvider,
    String slotKey,
  ) {
    final rs = context.rs;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = attendance?.status;
    final isLocked = CalendarUtils.isLockedByManualOverride(subject, date);

    final timeSlot = CalendarUtils.getTimeSlotForDate(subject, date);
    final room = timeSlot != null ? subject.getEffectiveRoom(timeSlot) : null;
    final timeStr = timeSlot != null ? timeSlot.formatTimeRange(timeFormatProvider.timeFormat) : '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(rs.scale(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          margin: EdgeInsets.only(bottom: rs.height(8)),
          padding: EdgeInsets.symmetric(horizontal: rs.width(14), vertical: rs.height(10)),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF14141A).withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(rs.scale(16)),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.08),
              width: 0.9,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: rs.scale(36),
                height: rs.scale(36),
                decoration: BoxDecoration(
                  color: subject.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: subject.color,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(rs.scale(3.5)),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        subject.displayAcronym,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: subject.color,
                          fontWeight: FontWeight.w700,
                          fontSize: rs.font(11.5),
                          letterSpacing: 0.4,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: rs.width(12)),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.name,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: rs.font(13.5),
                        letterSpacing: -0.2,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: rs.height(2)),
                    Text(
                      room != null && room.isNotEmpty ? '$timeStr   Room $room' : timeStr,
                      style: GoogleFonts.inter(
                        fontSize: rs.font(11.5),
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),

              if (isLocked)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: rs.width(10), vertical: rs.height(5)),
                  decoration: BoxDecoration(
                    color: const Color(0xFF52525B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(rs.scale(12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: rs.scale(12), color: const Color(0xFF71717A)),
                      SizedBox(width: rs.width(4)),
                      Text(
                        'Locked',
                        style: GoogleFonts.inter(
                          fontSize: rs.font(11),
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF71717A),
                        ),
                      ),
                    ],
                  ),
                )
              else
                _buildAttendanceStatusPill(status, () async {
                  final newStatus = _getNextStatus(status);
                  if (newStatus == null) {
                    await attendanceProvider.deleteRecordForSubjectOnDate(
                      subject.id,
                      date,
                      slotKey: slotKey,
                    );
                  } else {
                    await attendanceProvider.markAttendance(
                      subject.id,
                      date,
                      newStatus,
                      slotKey: slotKey,
                    );
                  }
                  onRefresh();
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceStatusPill(AttendanceStatus? status, VoidCallback onTap) {
    final rs = context.rs;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgColor;
    String label;
    IconData icon;

    if (status == null) {
      bgColor = const Color(0xFFF59E0B);
      label = 'Mark';
      icon = Icons.help_outline_rounded;
    } else if (status == AttendanceStatus.attended) {
      bgColor = const Color(0xFFFF8A00);
      label = 'Present';
      icon = Icons.check_circle_outline_rounded;
    } else if (status == AttendanceStatus.absent) {
      bgColor = const Color(0xFFEF4444);
      label = 'Absent';
      icon = Icons.highlight_off_rounded;
    } else {
      bgColor = const Color(0xFF8B5CF6);
      label = 'Holiday';
      icon = Icons.celebration_rounded;
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: rs.width(9), vertical: rs.height(4)),
        decoration: BoxDecoration(
          color: bgColor.withValues(alpha: isDark ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(rs.scale(8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: rs.scale(12), color: bgColor),
            SizedBox(width: rs.width(4)),
            Text(
              label,
              style: GoogleFonts.inter(
                color: bgColor,
                fontSize: rs.font(11),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  AttendanceStatus? _getNextStatus(AttendanceStatus? currentStatus) {
    if (currentStatus == null) {
      return AttendanceStatus.attended;
    } else if (currentStatus == AttendanceStatus.attended) {
      return AttendanceStatus.absent;
    } else if (currentStatus == AttendanceStatus.absent) {
      return AttendanceStatus.cancelled;
    } else {
      return null;
    }
  }

  List<DateTime> _getSwipableDayDates({
    required DateTime currentDate,
    required DateTime startDate,
    required DateTime endDate,
    required List<Subject> subjects,
    required List<Attendance> attendanceRecords,
  }) {
    final classDates = <DateTime>[];
    var date = DateTime(startDate.year, startDate.month, startDate.day);
    final normalizedEndDate = DateTime(endDate.year, endDate.month, endDate.day);

    while (!date.isAfter(normalizedEndDate)) {
      int classesCount = 0;
      for (final subject in subjects) {
        for (final slot in subject.schedule) {
          if (slot.occursOnDate(date)) {
            classesCount++;
          }
        }
      }

      if (classesCount > 0) {
        classDates.add(date);
      }

      date = date.add(const Duration(days: 1));
    }

    final normalizedCurrent = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
    );

    if (classDates.any((d) => CalendarUtils.isSameDay(d, normalizedCurrent))) {
      return classDates;
    }

    if (classDates.isEmpty) {
      return [normalizedCurrent];
    }

    final combined = [...classDates, normalizedCurrent];
    combined.sort((a, b) => a.compareTo(b));

    final uniqueDates = <DateTime>[];
    for (final entry in combined) {
      if (uniqueDates.isEmpty || !CalendarUtils.isSameDay(uniqueDates.last, entry)) {
        uniqueDates.add(entry);
      }
    }

    return uniqueDates;
  }

  List<Subject> _expandSubjectsBySlotForDay(List<Subject> subjects, DateTime date) {
    final expandedSubjects = <Subject>[];

    for (final subject in subjects) {
      final slotsForDay = subject.schedule.where((slot) => slot.occursOnDate(date));
      for (final slot in slotsForDay) {
        expandedSubjects.add(subject.copyWith(schedule: [slot]));
      }
    }

    expandedSubjects.sort((a, b) {
      final aSlot = a.schedule.first;
      final bSlot = b.schedule.first;
      final aMinutes = aSlot.startTime.hour * 60 + aSlot.startTime.minute;
      final bMinutes = bSlot.startTime.hour * 60 + bSlot.startTime.minute;
      return aMinutes.compareTo(bMinutes);
    });

    return expandedSubjects;
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  String _getShortMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatTimelineDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
  }

  String _formatShortMonthDay(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _getStateLabel(DayState state) {
    switch (state) {
      case DayState.attendedFullDay:
        return 'Attended';
      case DayState.bunkedFullDay:
        return 'Bunked';
      case DayState.classesMarked:
        return 'Mixed';
      case DayState.classesNotMarked:
        return 'Unmarked';
      case DayState.holiday:
        return 'Holiday';
      case DayState.plannedLeave:
        return 'Leave';
      case DayState.futureClasses:
        return 'Upcoming';
      case DayState.noClasses:
        return 'No Classes';
      case DayState.locked:
        return 'Locked';
    }
  }
}

/// Custom painter for the day Activity Ring (donut arc)
class _ActivityRingPainter extends CustomPainter {
  final double ratio;
  final Color ringColor;
  final Color trackColor;
  final double strokeWidth;

  const _ActivityRingPainter({
    required this.ratio,
    required this.ringColor,
    required this.trackColor,
    this.strokeWidth = 3.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    if (ratio > 0 && ringColor != Colors.transparent) {
      final progressPaint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final sweepAngle = (ratio.clamp(0.0, 1.0)) * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ActivityRingPainter oldDelegate) {
    return oldDelegate.ratio != ratio ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
