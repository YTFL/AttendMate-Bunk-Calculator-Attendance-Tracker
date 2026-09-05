import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../../utils/string_extension.dart';
import '../semester/semester_provider.dart';
import '../settings/time_format_provider.dart';
import '../tutorial/tutorial_controller.dart';
import 'add_subject_screen.dart';
import 'edit_subject_screen.dart';
import 'subject_provider.dart';
import 'subject_model.dart';
import '../settings/setup_guide_screen.dart';

class SubjectScreen extends StatefulWidget {
  const SubjectScreen({super.key});

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  String _searchQuery = '';
  final Set<String> _collapsedSubjectIds = <String>{};
  final Set<String> _knownSubjectIds = <String>{};

  void _syncCollapsedState(List<Subject> subjects) {
    final currentIds = subjects.map((subject) => subject.id).toSet();

    for (final subject in subjects) {
      if (_knownSubjectIds.add(subject.id)) {
        _collapsedSubjectIds.add(subject.id);
      }
    }

    _knownSubjectIds.removeWhere((id) => !currentIds.contains(id));
    _collapsedSubjectIds.removeWhere((id) => !currentIds.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);
    final allSubjects = subjectProvider.subjects;
    final bool semesterEnded = semesterProvider.hasSemesterEnded;
    _syncCollapsedState(allSubjects);

    // Sort subjects alphabetically
    final subjects = List<Subject>.from(allSubjects)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final filteredSubjects = subjects.where((s) {
      final nameMatches = s.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final acronymMatches = (s.acronym ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
      return nameMatches || acronymMatches;
    }).toList();

    if (subjects.isEmpty) {
      return _buildNoSubjectsState(context, rs, semesterEnded, semesterProvider);
    }

    return Column(
      children: [
        if (semesterEnded)
          Container(
            padding: rs.insetsSymmetric(horizontal: 16, vertical: 12),
            color: Colors.orange.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange, size: rs.scale(20)),
                SizedBox(width: rs.width(8)),
                Expanded(
                  child: Text(
                    'Semester has ended. Viewing archived subjects.',
                    style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: rs.insetsAll(12),
          child: TextField(
            decoration: InputDecoration(
              labelText: 'Search Subjects',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(rs.scale(12)),
              ),
              contentPadding: rs.insetsSymmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),
        Expanded(
          child: filteredSubjects.isEmpty
              ? Center(
                  child: Text(
                    'No subjects found',
                    style: TextStyle(fontSize: rs.font(16), color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: rs.insetsSymmetric(horizontal: 12, vertical: 4),
                  itemCount: filteredSubjects.length,
                  itemBuilder: (context, index) {
                    final subject = filteredSubjects[index];
                    final sortedSchedule = _sortedSchedule(subject.activeSchedule);
                    final isExpanded = !_collapsedSubjectIds.contains(subject.id);

                    return _SubjectCardItem(
                      key: ValueKey(subject.id),
                      subject: subject,
                      sortedSchedule: sortedSchedule,
                      isExpanded: isExpanded,
                      onExpansionChanged: (expanded) {
                        setState(() {
                          if (expanded) {
                            _collapsedSubjectIds.remove(subject.id);
                          } else {
                            _collapsedSubjectIds.add(subject.id);
                          }
                        });
                      },
                      semesterEnded: semesterEnded,
                      onEdit: () {
                        FocusScope.of(context).unfocus();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditSubjectScreen(subject: subject),
                          ),
                        );
                      },
                      onDelete: () => _showDeleteConfirmation(context, subjectProvider, subject),
                      timeFormatProvider: timeFormatProvider,
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<TimeSlot> _sortedSchedule(List<TimeSlot> schedule) {
    final sortedSchedule = List<TimeSlot>.from(schedule);
    sortedSchedule.sort((a, b) {
      final dayCompare = a.day.index.compareTo(b.day.index);
      if (dayCompare != 0) return dayCompare;
      return _timeToDouble(a).compareTo(_timeToDouble(b));
    });
    return sortedSchedule;
  }

  double _timeToDouble(TimeSlot slot) {
    return slot.startTime.hour + (slot.startTime.minute / 60.0);
  }

  void _showDeleteConfirmation(BuildContext context, SubjectProvider provider, Subject subject) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : null,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete the subject "${subject.name}"? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(ctx).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
              onPressed: () {
                provider.deleteSubject(subject);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showReplacingSnackBar(
                  SnackBar(content: Text('"${subject.name}" deleted successfully.')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildNoSubjectsState(
    BuildContext context,
    ResponsiveScale rs,
    bool semesterEnded,
    SemesterProvider semesterProvider,
  ) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: rs.width(16),
        vertical: rs.height(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (semesterEnded && semesterProvider.semester != null) ...[
            Container(
              padding: rs.insetsAll(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: isDarkMode ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(rs.scale(12)),
                border: Border.all(
                  color: Colors.blue.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Colors.blue,
                    size: rs.scale(20),
                  ),
                  SizedBox(width: rs.width(10)),
                  Expanded(
                    child: Text(
                      'Semester ended on ${semesterProvider.semester!.endDate.day}/${semesterProvider.semester!.endDate.month}/${semesterProvider.semester!.endDate.year}. Viewing archived data.',
                      style: TextStyle(
                        color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade800,
                        fontWeight: FontWeight.w500,
                        fontSize: rs.font(12.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: rs.height(16)),
          ],

          // Primary Empty State Hero Card
          _buildEmptySubjectHeroCard(context, rs, semesterEnded),

          SizedBox(height: rs.height(16)),

          // Secondary Compact AI Import Suggestion
          _buildCompactAISuggestionCard(context, rs),
        ],
      ),
    );
  }

  Widget _buildEmptySubjectHeroCard(
    BuildContext context,
    ResponsiveScale rs,
    bool semesterEnded,
  ) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(rs.scale(24)),
      decoration: BoxDecoration(
        color: isDarkMode
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(rs.scale(20)),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.12),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.04),
            blurRadius: rs.scale(12),
            offset: Offset(0, rs.scale(4)),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: rs.scale(64),
            height: rs.scale(64),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                Icons.menu_book_rounded,
                size: rs.scale(32),
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          SizedBox(height: rs.height(16)),
          Text(
            'No Subjects Added Yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: rs.font(18),
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          SizedBox(height: rs.height(8)),
          Text(
            'Add your subjects and weekly timetable to start tracking attendance, calculate bunk allowances, and get class reminders.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: rs.font(13),
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
          SizedBox(height: rs.height(20)),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  vertical: rs.height(13),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(rs.scale(12)),
                ),
              ),
              icon: Icon(Icons.add_rounded, size: rs.scale(20)),
              label: Text(
                'Add Your First Subject',
                style: TextStyle(
                  fontSize: rs.font(14),
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: semesterEnded
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      final tutorialController = Provider.of<TutorialController>(context, listen: false);
                      if (tutorialController.isActive && tutorialController.currentStepIndex == 4) {
                        tutorialController.nextStep();
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AddSubjectScreen(),
                        ),
                      );
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAISuggestionCard(
    BuildContext context,
    ResponsiveScale rs,
  ) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(rs.scale(16)),
      decoration: BoxDecoration(
        color: isDarkMode
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25)
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(rs.scale(16)),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(rs.scale(6)),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(rs.scale(10)),
                ),
                child: Text(
                  'TIP',
                  style: TextStyle(
                    fontSize: rs.font(10),
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              SizedBox(width: rs.width(8)),
              Text(
                'Fast Setup with AI',
                style: TextStyle(
                  fontSize: rs.font(13.5),
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          SizedBox(height: rs.height(8)),
          Text(
            'Import your schedule in seconds! Take a screenshot of your timetable, copy our prompt, and let Gemini or ChatGPT set up your subjects.',
            style: TextStyle(
              fontSize: rs.font(12),
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
              height: 1.35,
            ),
          ),
          SizedBox(height: rs.height(10)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: rs.width(10),
                  vertical: rs.height(4),
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Text(
                'Learn How to Import',
                style: TextStyle(
                  fontSize: rs.font(12),
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              label: Icon(
                Icons.arrow_forward_rounded,
                size: rs.scale(14),
                color: theme.colorScheme.primary,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SetupGuideScreen(initialPage: 3),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectCardItem extends StatefulWidget {
  final Subject subject;
  final List<TimeSlot> sortedSchedule;
  final bool isExpanded;
  final ValueChanged<bool> onExpansionChanged;
  final bool semesterEnded;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final TimeFormatProvider timeFormatProvider;

  const _SubjectCardItem({
    super.key,
    required this.subject,
    required this.sortedSchedule,
    required this.isExpanded,
    required this.onExpansionChanged,
    required this.semesterEnded,
    required this.onEdit,
    required this.onDelete,
    required this.timeFormatProvider,
  });

  @override
  State<_SubjectCardItem> createState() => _SubjectCardItemState();
}

class _SubjectCardItemState extends State<_SubjectCardItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _iconTurns;
  late final Animation<double> _heightFactor;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: widget.isExpanded ? 1.0 : 0.0,
    );
    _iconTurns = _controller.drive(
      Tween<double>(begin: 0.0, end: 0.5).chain(
        CurveTween(curve: Curves.easeInOut),
      ),
    );
    _heightFactor = _controller.drive(
      CurveTween(curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant _SubjectCardItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    final newExpanded = !widget.isExpanded;
    if (newExpanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    widget.onExpansionChanged(newExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final subject = widget.subject;
    final sortedSchedule = widget.sortedSchedule;

    return Card(
      elevation: isDarkMode ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(rs.scale(12)),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: isDarkMode ? 0.25 : 0.15),
          width: 1,
        ),
      ),
      margin: EdgeInsets.only(bottom: rs.height(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(rs.scale(12)),
            onTap: _handleTap,
            child: Padding(
              padding: rs.insetsSymmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: rs.scale(20.6),
                    backgroundColor: subject.color,
                    child: Center(
                      child: Text(
                        subject.acronym ?? '',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        softWrap: true,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: rs.font(11),
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: rs.width(12)),
                  Expanded(
                    child: Text(
                      subject.name,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: rs.font(15)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit Subject',
                    onPressed: widget.semesterEnded ? null : widget.onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Delete Subject',
                    onPressed: widget.semesterEnded ? null : widget.onDelete,
                  ),
                  RotationTransition(
                    turns: _iconTurns,
                    child: Icon(
                      Icons.expand_more,
                      color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedBuilder(
              animation: _controller.view,
              builder: (context, child) {
                return Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _heightFactor.value,
                  child: child,
                );
              },
              child: Padding(
                padding: EdgeInsets.only(
                  left: rs.width(14),
                  right: rs.width(14),
                  bottom: rs.height(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(
                      height: rs.height(12),
                      thickness: 1,
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
                    ),
                    SizedBox(height: rs.height(4)),
                    if (sortedSchedule.isNotEmpty)
                      Wrap(
                        spacing: rs.width(4),
                        runSpacing: rs.height(3),
                        children: sortedSchedule.map((timeSlot) {
                          final dayLabel = timeSlot.specificDate == null
                              ? timeSlot.day.name.capitalize().substring(0, 3)
                              : '${timeSlot.day.name.capitalize().substring(0, 3)} ${timeSlot.specificDate!.day}/${timeSlot.specificDate!.month}';
                          final room = subject.getEffectiveRoom(timeSlot);
                          final roomText = room != null ? ' • $room' : '';
                          return Chip(
                            label: Text(
                              '$dayLabel: ${timeSlot.formatTimeRange(widget.timeFormatProvider.timeFormat)}$roomText',
                              style: TextStyle(fontSize: rs.font(10)),
                            ),
                            backgroundColor: subject.color.withAlpha(50),
                            padding: rs.insetsSymmetric(horizontal: 2),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      )
                    else
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: rs.height(4)),
                        child: Text(
                          'No schedule configured for this subject.',
                          style: TextStyle(
                            fontSize: rs.font(11),
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

