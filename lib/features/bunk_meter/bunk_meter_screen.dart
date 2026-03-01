import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.pending_actions, size: 50, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'Semester Yet to Begin',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your semester will start on $formattedDate. The bunk meter will be available from that date.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
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
      targetPercentage,
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
            padding: const EdgeInsets.all(12.0),
            margin: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
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
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                borderRadius: BorderRadius.circular(12.0),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
            ),
          ),
        ),
        // Show count of filtered results
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Text(
              'Found ${filteredSubjects.length} class${filteredSubjects.length == 1 ? '' : 'es'}',
              style: TextStyle(
                fontSize: 12,
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
                      Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No classes found',
                        style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Try a different search term',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
      key: ValueKey(Theme.of(context).brightness),
      itemCount: filteredSubjects.length,
      itemBuilder: (context, index) {
        final subject = filteredSubjects[index];

        // 1. Get total classes scheduled for the whole semester
        final totalClassesInSemester = subject.getTotalScheduledClasses(semester.startDate, semester.endDate);

        // 2. Get classes scheduled up to today
        final scheduledSoFar = subject.getTotalScheduledClasses(semester.startDate, endDate);

        // 3. Get attendance records for this subject up to today
        final recordsForSubject = attendanceProvider.attendanceRecords.where((record) {
          return record.subjectId == subject.id && !record.date.isAfter(endDate);
        }).toList();

        final attendedClasses = recordsForSubject
            .where((record) => record.status == AttendanceStatus.attended)
            .length;
        final absentClasses = recordsForSubject
            .where((record) => record.status == AttendanceStatus.absent)
            .length;
        final cancelledClasses = recordsForSubject
            .where((record) => record.status == AttendanceStatus.cancelled)
            .length;

        if (totalClassesInSemester == 0) {
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

        // 4. Calculate classes held so far (all scheduled classes excluding cancelled holidays)
        int classesHeldSoFar = scheduledSoFar - cancelledClasses;
        if (classesHeldSoFar < 0) {
          classesHeldSoFar = 0;
        }

        // 5. Calculate only marked classes (attended + absent) - unmarked classes are not considered
        final markedClasses = attendedClasses + absentClasses;

        // 6. Calculate the current attendance percentage based only on marked classes
        double currentPercentage = (markedClasses == 0)
            ? 100.0
            : (attendedClasses / markedClasses) * 100;

        // 7. Calculate future bunking ability or required attendance
        String message;
        Color messageColor;
        String compactStatus;

        final currentRatio = (markedClasses == 0)
            ? 1.0
            : (attendedClasses / markedClasses);

        final futureScheduled = totalClassesInSemester - scheduledSoFar;

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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStatColumn('Classes Held', classesHeldSoFar.toString()),
                        _buildStatColumn('Attended', attendedClasses.toString()),
                        _buildStatColumn('Bunked', absentClasses.toString()),
                        _buildStatColumn('Current %', '${currentPercentage.toStringAsFixed(1)}%'),
                      ],
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
    double targetPercentage,
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
    // Get attendance records for this subject up to today
    final recordsForSubject = attendanceProvider.attendanceRecords.where((record) {
      return record.subjectId == subject.id && !record.date.isAfter(endDate);
    }).toList();

    final attendedClasses = recordsForSubject
        .where((record) => record.status == AttendanceStatus.attended)
        .length;
    final absentClasses = recordsForSubject
        .where((record) => record.status == AttendanceStatus.absent)
        .length;

    // Only count marked classes (attended + absent), unmarked classes are not considered
    final markedClasses = attendedClasses + absentClasses;

    // Check if below target
    if (markedClasses == 0) {
      return false; // No classes marked yet, not below target
    }

    final currentRatio = attendedClasses / markedClasses;
    return currentRatio < targetPercentage;
  }
}
