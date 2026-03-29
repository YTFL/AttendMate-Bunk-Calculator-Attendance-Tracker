import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/responsive_scale.dart';
import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';
import '../semester/semester_model.dart';
import '../semester/semester_provider.dart';
import '../../utils/string_extension.dart';

class BunkMeterScreen extends StatefulWidget {
  const BunkMeterScreen({super.key});

  @override
  State<BunkMeterScreen> createState() => _BunkMeterScreenState();
}

class _BunkMeterScreenState extends State<BunkMeterScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _expandedSubjectIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    // By using Provider.of, this widget will rebuild when SubjectProvider notifies its listeners
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final attendanceProvider = Provider.of<AttendanceProvider>(context);
    final subjects = subjectProvider.subjects;
    final semester = semesterProvider.semester;

    if (semester == null) {
      return const Center(child: Text('Please set a semester first.'));
    }

    // Check if the semester has started yet
    if (!semesterProvider.hasSemesterStarted) {
      final startDate = semester.startDate;
      final formattedDate = '${startDate.day}/${startDate.month}/${startDate.year}';
      return Center(
        child: Padding(
          padding: rs.insetsAll(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pending_actions, size: rs.scale(50), color: Colors.blue),
              SizedBox(height: rs.height(16)),
              Text(
                'Semester Yet to Begin',
                style: TextStyle(fontSize: rs.font(22), fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: rs.height(8)),
              Text(
                'Your semester will start on $formattedDate. The bunk meter will be available from that date.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: rs.font(16)),
              ),
            ],
          ),
        ),
      );
    }
    
    // Show info banner if semester has ended
    final bool semesterEnded = semesterProvider.hasSemesterEnded;

    if (subjects.isEmpty) {
      return const Center(child: Text('No subjects added yet.'));
    }

    final targetPercentage = semester.targetPercentage / 100;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day); // Normalize to midnight
    final endDate = today.isAfter(semester.endDate) ? semester.endDate : today;

    // Sort subjects: ones that need attendance first, then alphabetically
    final sortedSubjects = _getSortedSubjects(
      subjects,
      attendanceProvider,
      semester,
      endDate,
    );

    // Filter subjects based on search query
    final filteredSubjects = _searchQuery.isEmpty
        ? sortedSubjects
        : sortedSubjects.where((subject) {
            return subject.matchesSearchQuery(_searchQuery);
          }).toList();

    return Column(
      children: [
        if (semesterEnded)
          Container(
            padding: rs.insetsAll(12),
            margin: rs.insetsAll(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(rs.scale(8)),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: rs.scale(20)),
                SizedBox(width: rs.width(8)),
                Expanded(
                  child: Text(
                    'Semester ended on ${semester.endDate.day}/${semester.endDate.month}/${semester.endDate.year}. Showing final attendance data.',
                    style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        // Search field
        Padding(
          padding: rs.insetsSymmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search for a class...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(rs.scale(12)),
              ),
              contentPadding: rs.insetsSymmetric(vertical: 12),
            ),
          ),
        ),
        // Show count of filtered results
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: rs.insetsSymmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Found ${filteredSubjects.length} class${filteredSubjects.length == 1 ? '' : 'es'}',
              style: TextStyle(
                fontSize: rs.font(12),
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Expanded(
          child: filteredSubjects.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: rs.scale(64), color: Colors.grey.shade400),
                      SizedBox(height: rs.height(16)),
                      Text(
                        'No classes found',
                        style: TextStyle(fontSize: rs.font(18), color: Colors.grey.shade600),
                      ),
                      SizedBox(height: rs.height(8)),
                      Text(
                        'Try a different search term',
                        style: TextStyle(fontSize: rs.font(14), color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
      key: ValueKey(Theme.of(context).brightness),
      itemCount: filteredSubjects.length,
      itemBuilder: (context, index) {
        final subject = filteredSubjects[index];
        final snapshot = _buildAttendanceSnapshot(
          subject: subject,
          attendanceProvider: attendanceProvider,
          semester: semester,
          endDate: endDate,
        );

        if (snapshot.totalClassesInWindow == 0 && snapshot.classesHeldSoFar == 0) {
          final isDarkMode = Theme.of(context).brightness == Brightness.dark;
          final isExpanded = _expandedSubjectIds.contains(subject.id);
          return Card(
            elevation: 3.0,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
              side: BorderSide(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.4)
                    : Colors.black.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            shadowColor: isDarkMode
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.4),
            child: InkWell(
              borderRadius: BorderRadius.circular(8.0),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedSubjectIds.remove(subject.id);
                  } else {
                    _expandedSubjectIds.add(subject.id);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20.6,
                          backgroundColor: subject.color,
                          child: Center(
                            child: Text(
                              subject.acronym ?? '',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              softWrap: true,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            subject.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'No classes scheduled for this subject in the semester.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final classesHeldSoFar = snapshot.classesHeldSoFar;
        final attendedClasses = snapshot.attendedClasses;
        final absentClasses = snapshot.absentClasses;
        final markedClasses = snapshot.markedClasses;
        final currentPercentage =
            (markedClasses == 0) ? 100.0 : (attendedClasses / markedClasses) * 100;

        // Calculate future bunking ability or required attendance
        String message;
        Color messageColor;
        String compactStatus;

        final currentRatio = (markedClasses == 0)
            ? 1.0
            : (attendedClasses / markedClasses);

        int futureScheduled = snapshot.totalClassesInWindow - snapshot.scheduledSoFarInWindow;
        if (futureScheduled < 0) {
          futureScheduled = 0;
        }

        if (currentRatio >= targetPercentage) {
          // Already at or above target
          int bunkable = 0;
          int simulatedMarked = markedClasses;
          int simulatedAttended = attendedClasses;

          while (bunkable < futureScheduled) {
            final nextMarked = simulatedMarked + 1;
            final nextRatio = (nextMarked == 0) ? 1.0 : (simulatedAttended / nextMarked);
            if (nextRatio >= targetPercentage) {
              bunkable++;
              simulatedMarked = nextMarked;
            } else {
              break;
            }
          }

          if (bunkable == 0) {
            message = 'You currently cannot bunk anymore classes';
            compactStatus = 'Can\'t bunk';
          } else {
            message = 'You can bunk next $bunkable classes continously';
            compactStatus = 'Bunkable: $bunkable';
          }
          messageColor = Colors.green.shade700;
        } else {
          // Below target - need to attend more classes
          int neededClasses = 0;
          int simulatedMarked = markedClasses;
          int simulatedAttended = attendedClasses;

          // Calculate how many classes need to be attended
          while (simulatedMarked == 0 || (simulatedAttended / simulatedMarked) < targetPercentage) {
            simulatedMarked++;
            simulatedAttended++;
            neededClasses++;
          }

          // Check if target is achievable with remaining classes
          if (neededClasses <= futureScheduled) {
            message = 'Must attend next $neededClasses classes';
            compactStatus = 'Must attend: $neededClasses';
            messageColor = Colors.orange.shade700;
          } else {
            // Target is not achievable
            final maxAttainableFuture = attendedClasses + futureScheduled;
            final maxAttainableMarked = markedClasses + futureScheduled;
            final maxAttainablePercentage =
                (maxAttainableMarked == 0) ? 100.0 : (maxAttainableFuture / maxAttainableMarked) * 100;

            message = 'Target unreachable (max ${maxAttainablePercentage.toStringAsFixed(1)}%)';
            compactStatus = 'Can\'t reach target';
            messageColor = Colors.red.shade700;
          }
        }

        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final isExpanded = _expandedSubjectIds.contains(subject.id);

        return Card(
          elevation: 3.0,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          shadowColor: isDarkMode
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.4),
          child: InkWell(
            borderRadius: BorderRadius.circular(8.0),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedSubjectIds.remove(subject.id);
                } else {
                  _expandedSubjectIds.add(subject.id);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20.6,
                        backgroundColor: subject.color,
                        child: Center(
                          child: Text(
                            subject.acronym ?? subject.name.acronymFromName(),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            softWrap: true,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          subject.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isExpanded ? message : compactStatus,
                    style: TextStyle(fontSize: 14, color: messageColor, fontWeight: FontWeight.w600),
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    if (snapshot.manualOverride != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Manual baseline active from ${snapshot.countingStart.day}/${snapshot.countingStart.month}/${snapshot.countingStart.year}. Any attendance or timetable changes before this date are ignored in this card.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStatColumn('Classes Held', classesHeldSoFar.toString()),
                        _buildStatColumn('Attended', attendedClasses.toString()),
                        _buildStatColumn('Bunked', absentClasses.toString()),
                        _buildStatColumn('Current %', '${currentPercentage.toStringAsFixed(1)}%'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () => _showManualCountUpdateDialog(
                          subject: subject,
                          subjectProvider: subjectProvider,
                          currentHeld: classesHeldSoFar,
                          currentAttended: attendedClasses,
                          effectiveFrom: today,
                        ),
                        icon: const Icon(Icons.edit_calendar_outlined),
                        label: const Text('Update Counts Manually'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
          ),
        ),
      ],
    );
  }

  Widget _buildStatColumn(String title, String value) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// Sort subjects: ones that need attendance (below target) first, then alphabetically
  List<Subject> _getSortedSubjects(
    List<Subject> subjects,
    AttendanceProvider attendanceProvider,
    Semester semester,
    DateTime endDate,
  ) {
    final targetPercentageValue = semester.targetPercentage / 100;
    
    return List<Subject>.from(subjects)..sort((a, b) {
      final aNeeds = _needsAttendance(a, attendanceProvider, semester, endDate, targetPercentageValue);
      final bNeeds = _needsAttendance(b, attendanceProvider, semester, endDate, targetPercentageValue);

      // Classes that need attendance come first
      if (aNeeds != bNeeds) {
        return aNeeds ? -1 : 1;
      }

      // Within the same group, sort alphabetically
      return a.name.compareTo(b.name);
    });
  }

  /// Check if a subject needs attendance (is below target percentage)
  bool _needsAttendance(
    Subject subject,
    AttendanceProvider attendanceProvider,
    Semester semester,
    DateTime endDate,
    double targetPercentage,
  ) {
    final snapshot = _buildAttendanceSnapshot(
      subject: subject,
      attendanceProvider: attendanceProvider,
      semester: semester,
      endDate: endDate,
    );

    final attendedClasses = snapshot.attendedClasses;
    final markedClasses = snapshot.markedClasses;

    // Check if below target
    if (markedClasses == 0) {
      return false; // No classes marked yet, not below target
    }

    final currentRatio = attendedClasses / markedClasses;
    return currentRatio < targetPercentage;
  }

  _SubjectAttendanceSnapshot _buildAttendanceSnapshot({
    required Subject subject,
    required AttendanceProvider attendanceProvider,
    required Semester semester,
    required DateTime endDate,
  }) {
    final manualOverride = subject.manualAttendanceOverride;
    DateTime countingStart = manualOverride?.effectiveFrom ?? semester.startDate;
    if (countingStart.isBefore(semester.startDate)) {
      countingStart = semester.startDate;
    }

    final recordsForSubject = attendanceProvider.attendanceRecords.where((record) {
      if (record.subjectId != subject.id) {
        return false;
      }
      if (record.date.isAfter(endDate)) {
        return false;
      }
      if (record.date.isBefore(countingStart)) {
        return false;
      }
      return true;
    }).toList();

    final attendedPostOverride = recordsForSubject
        .where((record) => record.status == AttendanceStatus.attended)
        .length;
    final absentPostOverride = recordsForSubject
        .where((record) => record.status == AttendanceStatus.absent)
        .length;
    final cancelledPostOverride = recordsForSubject
        .where((record) => record.status == AttendanceStatus.cancelled)
        .length;

    final scheduledSoFarInWindow = countingStart.isAfter(endDate)
        ? 0
        : subject.getTotalScheduledClasses(countingStart, endDate);
    final totalClassesInWindow = countingStart.isAfter(semester.endDate)
        ? 0
        : subject.getTotalScheduledClasses(countingStart, semester.endDate);

    int heldPostOverride = scheduledSoFarInWindow - cancelledPostOverride;
    if (heldPostOverride < 0) {
      heldPostOverride = 0;
    }

    final baselineHeld = manualOverride?.classesHeld ?? 0;
    final baselineAttended = manualOverride?.classesAttended ?? 0;
    final baselineAbsent = manualOverride?.classesAbsent ?? 0;

    return _SubjectAttendanceSnapshot(
      totalClassesInWindow: totalClassesInWindow,
      scheduledSoFarInWindow: scheduledSoFarInWindow,
      classesHeldSoFar: baselineHeld + heldPostOverride,
      attendedClasses: baselineAttended + attendedPostOverride,
      absentClasses: baselineAbsent + absentPostOverride,
      markedClasses: baselineHeld + attendedPostOverride + absentPostOverride,
      countingStart: countingStart,
      manualOverride: manualOverride,
    );
  }

  Future<void> _showManualCountUpdateDialog({
    required Subject subject,
    required SubjectProvider subjectProvider,
    required int currentHeld,
    required int currentAttended,
    required DateTime effectiveFrom,
  }) async {
    final manualInput = await Navigator.of(context).push<_ManualCountInput>(
      MaterialPageRoute(
        builder: (context) => _ManualCountUpdatePage(
          subjectName: subject.name,
          effectiveFrom: effectiveFrom,
          initialHeld: currentHeld,
          initialAttended: currentAttended,
        ),
      ),
    );

    if (manualInput == null || !mounted) {
      return;
    }

    if (!mounted) {
      return;
    }

    await subjectProvider.updateManualAttendanceCounts(
      subjectId: subject.id,
      classesHeld: manualInput.held,
      classesAttended: manualInput.attended,
      effectiveFrom: effectiveFrom,
    );
  }
}

class _SubjectAttendanceSnapshot {
  final int totalClassesInWindow;
  final int scheduledSoFarInWindow;
  final int classesHeldSoFar;
  final int attendedClasses;
  final int absentClasses;
  final int markedClasses;
  final DateTime countingStart;
  final ManualAttendanceOverride? manualOverride;

  const _SubjectAttendanceSnapshot({
    required this.totalClassesInWindow,
    required this.scheduledSoFarInWindow,
    required this.classesHeldSoFar,
    required this.attendedClasses,
    required this.absentClasses,
    required this.markedClasses,
    required this.countingStart,
    required this.manualOverride,
  });
}

class _ManualCountInput {
  final int held;
  final int attended;

  const _ManualCountInput({
    required this.held,
    required this.attended,
  });
}

class _ManualCountUpdatePage extends StatefulWidget {
  final String subjectName;
  final DateTime effectiveFrom;
  final int initialHeld;
  final int initialAttended;

  const _ManualCountUpdatePage({
    required this.subjectName,
    required this.effectiveFrom,
    required this.initialHeld,
    required this.initialAttended,
  });

  @override
  State<_ManualCountUpdatePage> createState() => _ManualCountUpdatePageState();
}

class _ManualCountUpdatePageState extends State<_ManualCountUpdatePage> {
  late final TextEditingController _heldController;
  late final TextEditingController _attendedController;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _heldController = TextEditingController(text: widget.initialHeld.toString());
    _attendedController = TextEditingController(text: widget.initialAttended.toString());
  }

  @override
  void dispose() {
    _heldController.dispose();
    _attendedController.dispose();
    super.dispose();
  }

  void _save() {
    final held = int.tryParse(_heldController.text.trim());
    final attended = int.tryParse(_attendedController.text.trim());

    if (held == null || attended == null || held < 0 || attended < 0 || attended > held) {
      setState(() {
        _validationError = 'Enter valid counts. Attended must be between 0 and held.';
      });
      return;
    }

    Navigator.pop(context, _ManualCountInput(held: held, attended: attended));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Update ${widget.subjectName} Counts'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Warning: Updating class counts manually will ignore all attendance and timetable history before ${widget.effectiveFrom.day}/${widget.effectiveFrom.month}/${widget.effectiveFrom.year} for this subject in Bunk Meter.',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Set your baseline counts. From that day onward, future classes will be added normally.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _heldController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Classes Held',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _attendedController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Classes Attended',
                border: OutlineInputBorder(),
              ),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 12),
              Text(
                _validationError!,
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
            ],
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
