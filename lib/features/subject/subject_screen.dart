import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../utils/snackbar_utils.dart';
import '../../utils/string_extension.dart';
import '../semester/semester_provider.dart';
import '../settings/time_format_provider.dart';
import 'edit_subject_screen.dart';
import 'subject_provider.dart';
import 'subject_model.dart';

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
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final semesterProvider = Provider.of<SemesterProvider>(context);
    final timeFormatProvider = Provider.of<TimeFormatProvider>(context);
    final allSubjects = subjectProvider.subjects;
    final bool semesterEnded = semesterProvider.hasSemesterEnded;
    _syncCollapsedState(allSubjects);
    
    // Sort subjects alphabetically
    final sortedSubjects = List<Subject>.from(allSubjects)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    
    // Filter subjects based on search query
    final subjects = sortedSubjects.where((subject) {
      return subject.matchesSearchQuery(_searchQuery);
    }).toList();

    if (allSubjects.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'No subjects added yet. Tap the \'+\' button to add your first subject.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (semesterEnded && semesterProvider.semester != null)
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
                    'Semester ended on ${semesterProvider.semester!.endDate.day}/${semesterProvider.semester!.endDate.month}/${semesterProvider.semester!.endDate.year}. Viewing archived data.',
                    style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search subjects...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),
        if (subjects.isEmpty && _searchQuery.isNotEmpty)
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'No subjects found matching your search.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              key: ValueKey(Theme.of(context).brightness),
              padding: const EdgeInsets.all(8.0),
              itemCount: subjects.length,
              itemBuilder: (context, index) {
                final subject = subjects[index];
                final sortedSchedule = List<TimeSlot>.from(subject.schedule)
                  ..sort((a, b) {
                    int dayCompare = a.day.index.compareTo(b.day.index);
                    if (dayCompare != 0) return dayCompare;
                    double aTime = a.startTime.hour + a.startTime.minute / 60.0;
                    double bTime = b.startTime.hour + b.startTime.minute / 60.0;
                    return aTime.compareTo(bTime);
                  });

                final isDarkMode = Theme.of(context).brightness == Brightness.dark;

                return Card(
                  elevation: 2.0,
                  margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    side: BorderSide(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.2),
                      width: 1.0,
                    ),
                  ),
                  shadowColor: isDarkMode
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.black.withValues(alpha: 0.4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8.0),
                    onTap: () {
                      setState(() {
                        if (_collapsedSubjectIds.contains(subject.id)) {
                          _collapsedSubjectIds.remove(subject.id);
                        } else {
                          _collapsedSubjectIds.add(subject.id);
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
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit Subject',
                                onPressed: semesterEnded
                                    ? null
                                    : () {
                                        FocusScope.of(context).unfocus();
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => EditSubjectScreen(subject: subject),
                                          ),
                                        );
                                      },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: 'Delete Subject',
                                onPressed: semesterEnded
                                    ? null
                                    : () => _showDeleteConfirmation(context, subjectProvider, subject),
                              ),
                              Icon(
                                _collapsedSubjectIds.contains(subject.id)
                                    ? Icons.expand_more
                                    : Icons.expand_less,
                                color: Theme.of(context).iconTheme.color?.withValues(alpha: 0.7),
                              ),
                            ],
                          ),
                          if (!_collapsedSubjectIds.contains(subject.id) && sortedSchedule.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 4.0,
                              runSpacing: 3.0,
                              children: sortedSchedule.map((timeSlot) {
                                return Chip(
                                  label: Text(
                                    '${timeSlot.day.name.capitalize().substring(0, 3)}: ${timeSlot.formatTimeRange(timeFormatProvider.timeFormat)}',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  backgroundColor: subject.color.withAlpha(50),
                                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                );
                              }).toList(),
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

  void _showDeleteConfirmation(BuildContext context, SubjectProvider provider, Subject subject) {
    showDialog(
      context: context,
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
}
