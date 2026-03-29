import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../utils/responsive_scale.dart';
import '../../utils/snackbar_utils.dart';
import '../attendance/attendance_model.dart';
import '../attendance/attendance_provider.dart';
import '../subject/subject_model.dart';
import '../subject/subject_provider.dart';
import 'semester_model.dart';
import 'semester_provider.dart';

class SemesterScreen extends StatefulWidget {
  const SemesterScreen({super.key});

  @override
  State<SemesterScreen> createState() => _SemesterScreenState();
}

class _SemesterScreenState extends State<SemesterScreen> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _startDate;
  DateTime? _endDate;
  double? _targetPercentage;
  late TextEditingController _targetPercentageController;

  @override
  void initState() {
    super.initState();
    final semester = Provider.of<SemesterProvider>(
      context,
      listen: false,
    ).semester;
    _startDate = semester?.startDate;
    _endDate = semester?.endDate;
    _targetPercentage = semester?.targetPercentage;
    _targetPercentageController = TextEditingController(
      text: _targetPercentage?.toString() ?? '',
    );
  }

  bool _isEndDateAfterStart(DateTime? startDate, DateTime? endDate) {
    if (startDate == null || endDate == null) {
      return true;
    }
    return endDate.isAfter(startDate);
  }

  void _updateSemester() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      if (!_isEndDateAfterStart(_startDate, _endDate)) {
        ScaffoldMessenger.of(context).showReplacingSnackBar(
          const SnackBar(content: Text('End date must be after start date.')),
        );
        return;
      }
      if (_startDate != null && _endDate != null && _targetPercentage != null) {
        final updatedSemester = Semester(
          startDate: _startDate!,
          endDate: _endDate!,
          targetPercentage: _targetPercentage!,
        );
        Provider.of<SemesterProvider>(
          context,
          listen: false,
        ).updateSemester(updatedSemester);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final semesterProvider = Provider.of<SemesterProvider>(context);

    if (semesterProvider.semester == null) {
      return _buildCreateSemesterForm();
    } else {
      return _buildSemesterDetails();
    }
  }

  Widget _buildCreateSemesterForm() {
    final rs = context.rs;
    return Card(
      margin: rs.insetsAll(16),
      shape: _buildOutlinedCardShape(context),
      child: Padding(
        padding: rs.insetsAll(16),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Create a New Semester',
                style: TextStyle(
                  fontSize: rs.font(22),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: rs.height(16)),
              ElevatedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (date != null) {
                    setState(() {
                      _startDate = date;
                      if (_endDate != null && !_endDate!.isAfter(date)) {
                        _endDate = null;
                      }
                    });
                  }
                },
                icon: const Icon(Icons.calendar_today),
                label: Text(
                  _startDate == null
                      ? 'Select Start Date'
                      : DateFormat.yMMMd().format(_startDate!),
                ),
              ),
              SizedBox(height: rs.height(16)),
              ElevatedButton.icon(
                onPressed: _startDate == null
                    ? null
                    : () async {
                        final firstAllowed = _startDate!.add(
                          const Duration(days: 1),
                        );
                        final initial =
                            _endDate != null && _endDate!.isAfter(_startDate!)
                            ? _endDate!
                            : firstAllowed;
                        final date = await showDatePicker(
                          context: context,
                          initialDate: initial,
                          firstDate: firstAllowed,
                          lastDate: DateTime(2100),
                        );
                        if (date != null) {
                          setState(() {
                            _endDate = date;
                          });
                        }
                      },
                icon: const Icon(Icons.calendar_today),
                label: Text(
                  _endDate == null
                      ? 'Select End Date'
                      : DateFormat.yMMMd().format(_endDate!),
                ),
              ),
              SizedBox(height: rs.height(16)),
              TextFormField(
                controller: _targetPercentageController,
                decoration: const InputDecoration(
                  labelText: 'Target Percentage',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) =>
                    value!.isEmpty ? 'Please enter a target percentage' : null,
                onSaved: (value) => _targetPercentage = double.parse(value!),
              ),
              SizedBox(height: rs.height(24)),
              ElevatedButton(
                onPressed: _updateSemester,
                child: const Text('Create Semester'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSemesterDetails() {
    final rs = context.rs;
    final semesterProvider = Provider.of<SemesterProvider>(
      context,
      listen: false,
    );
    final subjectProvider = Provider.of<SubjectProvider>(context);
    final attendanceProvider = Provider.of<AttendanceProvider>(context);
    final bool semesterEnded = semesterProvider.hasSemesterEnded;
    final semester = semesterProvider.semester!;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Card(
            margin: rs.insetsAll(16),
            shape: _buildOutlinedCardShape(context),
            child: Padding(
              padding: rs.insetsAll(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildDatePickerField(
                            title: 'Semester Start Date',
                            date: _startDate,
                            onPressed: _startDate == null
                                ? null
                                : () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: _startDate!,
                                      firstDate: DateTime(2000),
                                      lastDate: _endDate != null
                                          ? (_endDate!
                                                    .subtract(
                                                      const Duration(days: 1),
                                                    )
                                                    .isBefore(DateTime(2000))
                                                ? DateTime(2000)
                                                : _endDate!.subtract(
                                                    const Duration(days: 1),
                                                  ))
                                          : DateTime(2100),
                                    );
                                    if (date != null) {
                                      setState(() {
                                        _startDate = date;
                                        if (_endDate != null &&
                                            !_endDate!.isAfter(date)) {
                                          _endDate = null;
                                        }
                                      });
                                      _updateSemester();
                                      if (!mounted) return;
                                      final firstAllowed = date.add(
                                        const Duration(days: 1),
                                      );
                                      final endDate = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            _endDate != null &&
                                                _endDate!.isAfter(date)
                                            ? _endDate!
                                            : firstAllowed,
                                        firstDate: firstAllowed,
                                        lastDate: DateTime(2100),
                                      );
                                      if (endDate != null) {
                                        setState(() {
                                          _endDate = endDate;
                                        });
                                        _updateSemester();
                                      }
                                    }
                                  },
                          ),
                        ),
                        SizedBox(width: rs.width(12)),
                        Expanded(
                          child: _buildDatePickerField(
                            title: 'Semester End Date',
                            date: _endDate,
                            onPressed: _endDate == null
                                ? null
                                : () async {
                                    final date = await showDatePicker(
                                      context: context,
                                      initialDate: _endDate!,
                                      firstDate: _startDate != null
                                          ? _startDate!.add(
                                              const Duration(days: 1),
                                            )
                                          : DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (date != null) {
                                      setState(() {
                                        _endDate = date;
                                      });
                                      _updateSemester();
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.height(20)),
                    TextFormField(
                      controller: _targetPercentageController,
                      decoration: const InputDecoration(
                        labelText: 'Target Percentage',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) => value!.isEmpty
                          ? 'Please enter a target percentage'
                          : null,
                      onSaved: (value) =>
                          _targetPercentage = double.parse(value!),
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          final percentage = double.tryParse(value);
                          if (percentage != null) {
                            _targetPercentage = percentage;
                            _updateSemester();
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildOverallSummary(
            semester: semester,
            semesterProvider: semesterProvider,
            subjectProvider: subjectProvider,
            attendanceProvider: attendanceProvider,
          ),
          if (semesterEnded)
            Container(
              padding: rs.insetsAll(12),
              margin: rs.insetsAll(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(rs.scale(8)),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange,
                        size: rs.scale(20),
                      ),
                      SizedBox(width: rs.width(8)),
                      Expanded(
                        child: Text(
                          'Semester has ended. You can view old data or start a new semester.',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: rs.height(12)),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Show the create new semester form
                      DateTime? newStartDate;
                      DateTime? newEndDate;
                      double? newTargetPercentage;

                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Start New Semester'),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Create a new semester with new dates and settings. This will clear all previous data.',
                                  style: TextStyle(fontSize: rs.font(14)),
                                ),
                                SizedBox(height: rs.height(16)),
                                StatefulBuilder(
                                  builder: (context, setDialogState) => Column(
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          final date = await showDatePicker(
                                            context: context,
                                            initialDate: DateTime.now(),
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime(2100),
                                          );
                                          if (date != null) {
                                            setDialogState(() {
                                              newStartDate = date;
                                              if (newEndDate != null &&
                                                  !newEndDate!.isAfter(date)) {
                                                newEndDate = null;
                                              }
                                            });
                                          }
                                        },
                                        icon: const Icon(Icons.calendar_today),
                                        label: Text(
                                          newStartDate == null
                                              ? 'Select Start Date'
                                              : DateFormat.yMMMd().format(
                                                  newStartDate!,
                                                ),
                                        ),
                                      ),
                                      SizedBox(height: rs.height(12)),
                                      ElevatedButton.icon(
                                        onPressed: newStartDate == null
                                            ? null
                                            : () async {
                                                final firstAllowed =
                                                    newStartDate!.add(
                                                      const Duration(days: 1),
                                                    );
                                                final initial =
                                                    newEndDate != null &&
                                                        newEndDate!.isAfter(
                                                          newStartDate!,
                                                        )
                                                    ? newEndDate!
                                                    : firstAllowed;
                                                final date =
                                                    await showDatePicker(
                                                      context: context,
                                                      initialDate: initial,
                                                      firstDate: firstAllowed,
                                                      lastDate: DateTime(2100),
                                                    );
                                                if (date != null) {
                                                  setDialogState(() {
                                                    newEndDate = date;
                                                  });
                                                }
                                              },
                                        icon: const Icon(Icons.calendar_today),
                                        label: Text(
                                          newEndDate == null
                                              ? 'Select End Date'
                                              : DateFormat.yMMMd().format(
                                                  newEndDate!,
                                                ),
                                        ),
                                      ),
                                      SizedBox(height: rs.height(12)),
                                      TextFormField(
                                        decoration: const InputDecoration(
                                          labelText: 'Target Percentage',
                                          border: OutlineInputBorder(),
                                        ),
                                        keyboardType: TextInputType.number,
                                        onChanged: (value) {
                                          if (value.isNotEmpty) {
                                            newTargetPercentage =
                                                double.tryParse(value);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                              },
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                // Validate that all fields are filled
                                if (newStartDate == null ||
                                    newEndDate == null ||
                                    newTargetPercentage == null) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showReplacingSnackBar(
                                    const SnackBar(
                                      content: Text('Please fill all fields'),
                                    ),
                                  );
                                  return;
                                }
                                if (!newEndDate!.isAfter(newStartDate!)) {
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showReplacingSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'End date must be after start date.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                Navigator.of(ctx).pop();

                                if (!mounted) return;

                                final newSemester = Semester(
                                  startDate: newStartDate!,
                                  endDate: newEndDate!,
                                  targetPercentage: newTargetPercentage!,
                                );

                                // Show confirmation dialog
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (confirmCtx) => AlertDialog(
                                    title: const Text('Confirm'),
                                    content: const Text(
                                      'This will clear all subjects and attendance data from the previous semester. This action cannot be undone. Do you want to continue?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(confirmCtx).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.of(confirmCtx).pop(true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        child: const Text('Clear Data & Start'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmed != true) return;
                                if (!mounted) return;

                                // Create new semester and clear data
                                await Provider.of<SemesterProvider>(
                                  context,
                                  listen: false,
                                ).createNewSemester(newSemester);

                                if (!mounted) return;

                                // Reload subject and attendance providers to reflect cleared data
                                await Provider.of<SubjectProvider>(
                                  context,
                                  listen: false,
                                ).reloadSubjects();

                                if (!mounted) return;

                                await Provider.of<AttendanceProvider>(
                                  context,
                                  listen: false,
                                ).reloadAttendance();

                                if (mounted) {
                                  // Update local state with new semester values
                                  setState(() {
                                    _startDate = newSemester.startDate;
                                    _endDate = newSemester.endDate;
                                    _targetPercentage =
                                        newSemester.targetPercentage;
                                    _targetPercentageController.text =
                                        newSemester.targetPercentage.toString();
                                  });

                                  ScaffoldMessenger.of(
                                    context,
                                  ).showReplacingSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'New semester created successfully!',
                                      ),
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text('Create & Clear Data'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Start New Semester'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverallSummary({
    required Semester semester,
    required SemesterProvider semesterProvider,
    required SubjectProvider subjectProvider,
    required AttendanceProvider attendanceProvider,
  }) {
    final rs = context.rs;
    final subjects = subjectProvider.subjects;

    if (!semesterProvider.hasSemesterStarted) {
      final startDate = semester.startDate;
      final formattedDate =
          '${startDate.day}/${startDate.month}/${startDate.year}';
      return Card(
        margin: rs.insetsAll(16),
        shape: _buildOutlinedCardShape(context),
        child: Padding(
          padding: rs.insetsAll(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Overall Semester Summary',
                style: TextStyle(
                  fontSize: rs.font(18),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: rs.height(8)),
              Text(
                'Semester starts on $formattedDate. Summary will appear once it begins.',
              ),
            ],
          ),
        ),
      );
    }

    if (subjects.isEmpty) {
      return Card(
        margin: rs.insetsAll(16),
        shape: _buildOutlinedCardShape(context),
        child: Padding(
          padding: rs.insetsAll(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Overall Semester Summary',
                style: TextStyle(
                  fontSize: rs.font(18),
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: rs.height(8)),
              const Text(
                'No subjects added yet. Add subjects to see your overall attendance.',
              ),
            ],
          ),
        ),
      );
    }

    final targetPercentage = semester.targetPercentage;
    final targetRatio = targetPercentage / 100;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDate = today.isAfter(semester.endDate) ? semester.endDate : today;

    int totalClassesInSemester = 0;
    int scheduledSoFar = 0;
    int totalHeld = 0;
    int totalMarked = 0;
    int totalAttended = 0;

    for (final subject in subjects) {
      final snapshot = _buildSemesterSubjectSnapshot(
        subject: subject,
        attendanceProvider: attendanceProvider,
        semester: semester,
        endDate: endDate,
      );

      totalClassesInSemester += snapshot.totalClassesInWindow;
      scheduledSoFar += snapshot.scheduledSoFarInWindow;
      totalHeld += snapshot.classesHeldSoFar;
      totalMarked += snapshot.markedClasses;
      totalAttended += snapshot.attendedClasses;
    }

    final bunkedSoFar = totalMarked > 0 ? (totalMarked - totalAttended) : 0;
    final currentPercentage = totalMarked == 0
        ? 100.0
        : (totalAttended / totalMarked) * 100;
    final slackPercentage = currentPercentage - targetPercentage;

    int futureScheduled = totalClassesInSemester - scheduledSoFar;
    if (futureScheduled < 0) {
      futureScheduled = 0;
    }

    final currentRatio = totalMarked == 0 ? 1.0 : (totalAttended / totalMarked);
    int bunkableRemaining = 0;
    int neededClasses = 0;
    bool targetAchievable = true;
    double maxAttainablePercentage = 0.0;

    if (targetRatio <= 0) {
      bunkableRemaining = futureScheduled;
    } else if (currentRatio >= targetRatio) {
      final maxAdditionalMarked = (totalAttended / targetRatio) - totalMarked;
      bunkableRemaining = maxAdditionalMarked.floor();
      if (bunkableRemaining < 0) {
        bunkableRemaining = 0;
      }
      if (bunkableRemaining > futureScheduled) {
        bunkableRemaining = futureScheduled;
      }
    } else if (targetRatio >= 1.0) {
      maxAttainablePercentage = (totalMarked + futureScheduled == 0)
          ? 100.0
          : ((totalAttended + futureScheduled) /
                    (totalMarked + futureScheduled)) *
                100;
      targetAchievable = maxAttainablePercentage >= targetPercentage;
    } else {
      final numerator = (targetRatio * totalMarked) - totalAttended;
      if (numerator > 0) {
        neededClasses = (numerator / (1 - targetRatio)).ceil();
      }
      if (neededClasses <= futureScheduled) {
        bunkableRemaining = futureScheduled - neededClasses;
      } else {
        targetAchievable = false;
        maxAttainablePercentage = (totalMarked + futureScheduled == 0)
            ? 100.0
            : ((totalAttended + futureScheduled) /
                      (totalMarked + futureScheduled)) *
                  100;
      }
    }

    String message;
    Color messageColor;

    if (targetRatio <= 0) {
      if (bunkableRemaining == 0) {
        message = 'You currently cannot bunk anymore classes';
      } else {
        message = 'You can bunk next $bunkableRemaining classes continously';
      }
      messageColor = Colors.green.shade700;
    } else if (currentRatio >= targetRatio) {
      if (bunkableRemaining == 0) {
        message = 'You currently cannot bunk anymore classes';
      } else {
        message = 'You can bunk next $bunkableRemaining classes continously';
      }
      messageColor = Colors.green.shade700;
    } else if (!targetAchievable) {
      message =
          'Target unreachable (max ${maxAttainablePercentage.toStringAsFixed(1)}%)';
      messageColor = Colors.red.shade700;
    } else if (targetRatio >= 1.0) {
      message = 'Must attend all remaining classes';
      messageColor = Colors.orange.shade700;
    } else {
      message = 'Must attend $neededClasses remaining classes';
      messageColor = Colors.orange.shade700;
    }

    final slackText =
        '${slackPercentage >= 0 ? '+' : ''}${slackPercentage.toStringAsFixed(1)}%';

    return Card(
      margin: rs.insetsAll(16),
      shape: _buildOutlinedCardShape(context),
      child: Padding(
        padding: rs.insetsAll(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Overall Semester Summary',
              style: TextStyle(
                fontSize: rs.font(18),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: rs.height(12)),
            Text(
              message,
              style: TextStyle(
                fontSize: rs.font(16),
                color: messageColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: rs.height(6)),
            Text(
              'Warning: Using the bunkable count from this semester summary may affect per-subject attendance. Overall attendance can remain above your target while individual subjects may fall below target.',
              style: TextStyle(
                fontSize: rs.font(12),
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),

            SizedBox(height: rs.height(16)),
            const Divider(),
            SizedBox(height: rs.height(12)),
            LayoutBuilder(
              builder: (context, constraints) {
                final spacing = rs.width(12);
                final itemWidth = (constraints.maxWidth - (spacing * 3)) / 4;
                return Row(
                  children: [
                    _buildSummaryStat(
                      'Held',
                      totalHeld.toString(),
                      width: itemWidth,
                    ),
                    SizedBox(width: spacing),
                    _buildSummaryStat(
                      'Attended',
                      totalAttended.toString(),
                      width: itemWidth,
                    ),
                    SizedBox(width: spacing),
                    _buildSummaryStat(
                      'Bunked',
                      bunkedSoFar.toString(),
                      width: itemWidth,
                    ),
                    SizedBox(width: spacing),
                    _buildSummaryStat(
                      'Current %',
                      '${currentPercentage.toStringAsFixed(1)}%',
                      width: itemWidth,
                    ),
                  ],
                );
              },
            ),
            SizedBox(height: rs.height(12)),
            LayoutBuilder(
              builder: (context, constraints) {
                final spacing = rs.width(12);
                final itemWidth = (constraints.maxWidth - (spacing * 3)) / 4;
                return Row(
                  children: [
                    _buildSummaryStat(
                      'Target %',
                      '${targetPercentage.toStringAsFixed(0)}%',
                      width: itemWidth,
                    ),
                    SizedBox(width: spacing),
                    _buildSummaryStat('Slack', slackText, width: itemWidth),
                    SizedBox(width: spacing),
                    _buildSummaryStat(
                      'Remaining',
                      futureScheduled.toString(),
                      width: itemWidth,
                    ),
                    SizedBox(width: spacing),
                    _buildSummaryStat(
                      'Bunkable',
                      bunkableRemaining.toString(),
                      width: itemWidth,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStat(String title, String value, {double? width}) {
    final rs = context.rs;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: rs.font(12), color: Colors.grey),
          ),
          SizedBox(height: rs.height(4)),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: rs.font(16),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  _SemesterSubjectSnapshot _buildSemesterSubjectSnapshot({
    required Subject subject,
    required AttendanceProvider attendanceProvider,
    required Semester semester,
    required DateTime endDate,
  }) {
    final manualOverride = subject.manualAttendanceOverride;
    DateTime countingStart =
        manualOverride?.effectiveFrom ?? semester.startDate;
    if (countingStart.isBefore(semester.startDate)) {
      countingStart = semester.startDate;
    }

    final recordsForSubject = attendanceProvider.attendanceRecords.where((
      record,
    ) {
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

    return _SemesterSubjectSnapshot(
      totalClassesInWindow: totalClassesInWindow,
      scheduledSoFarInWindow: scheduledSoFarInWindow,
      classesHeldSoFar: baselineHeld + heldPostOverride,
      attendedClasses: baselineAttended + attendedPostOverride,
      absentClasses: baselineAbsent + absentPostOverride,
      markedClasses: baselineHeld + attendedPostOverride + absentPostOverride,
    );
  }

  Widget _buildDatePickerField({
    required String title,
    required DateTime? date,
    required VoidCallback? onPressed,
  }) {
    final rs = context.rs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: rs.font(13)),
        ),
        SizedBox(height: rs.height(8)),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(Icons.calendar_today, size: rs.scale(18)),
            label: Text(
              date != null ? DateFormat.yMMMd().format(date) : 'Select Date',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: rs.font(13)),
            ),
          ),
        ),
      ],
    );
  }

  RoundedRectangleBorder _buildOutlinedCardShape(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8.0),
      side: BorderSide(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.35)
            : Colors.black.withValues(alpha: 0.2),
        width: 1.2,
      ),
    );
  }
}

class _SemesterSubjectSnapshot {
  final int totalClassesInWindow;
  final int scheduledSoFarInWindow;
  final int classesHeldSoFar;
  final int attendedClasses;
  final int absentClasses;
  final int markedClasses;

  const _SemesterSubjectSnapshot({
    required this.totalClassesInWindow,
    required this.scheduledSoFarInWindow,
    required this.classesHeldSoFar,
    required this.attendedClasses,
    required this.absentClasses,
    required this.markedClasses,
  });
}
