import '../../utils/attendance_math.dart';
import '../attendance/attendance_model.dart';
import '../planner/planned_leave_model.dart';
import '../semester/semester_model.dart';
import '../subject/subject_model.dart';

class SubjectProjectedAttendance {
  final int totalAttended;
  final int totalMarked;
  final int plannedMissedCount;
  final int assumedPresentCount;
  final double projectedPercentage;
  final bool hasActivePlannedLeave;
  final DateTime? latestLeaveEndDate;
  final DateTime? leaveStartDate;
  final String? leaveName;

  const SubjectProjectedAttendance({
    required this.totalAttended,
    required this.totalMarked,
    required this.plannedMissedCount,
    required this.assumedPresentCount,
    required this.projectedPercentage,
    required this.hasActivePlannedLeave,
    this.latestLeaveEndDate,
    this.leaveStartDate,
    this.leaveName,
  });
}

class SemesterProjectedAttendance {
  final int totalAttended;
  final int totalMarked;
  final int totalPlannedMissed;
  final int totalAssumedPresent;
  final double projectedPercentage;
  final double projectedSlack;
  final bool hasActivePlannedLeave;
  final DateTime? latestLeaveEndDate;
  final DateTime? leaveStartDate;
  final String? leaveName;

  const SemesterProjectedAttendance({
    required this.totalAttended,
    required this.totalMarked,
    required this.totalPlannedMissed,
    required this.totalAssumedPresent,
    required this.projectedPercentage,
    required this.projectedSlack,
    required this.hasActivePlannedLeave,
    this.latestLeaveEndDate,
    this.leaveStartDate,
    this.leaveName,
  });
}

class PostLeaveRecoveryResult {
  final int classesNeeded;
  final bool isAchievable;
  final int remainingAfterLeave;
  final double maxAchievablePercentage;
  final DateTime? targetRecoveryDate;

  const PostLeaveRecoveryResult({
    required this.classesNeeded,
    required this.isAchievable,
    required this.remainingAfterLeave,
    required this.maxAchievablePercentage,
    this.targetRecoveryDate,
  });
}

class ProjectedAttendanceCalculator {
  /// Calculate projected attendance for a single subject up to the end of the next immediate planned leave.
  static SubjectProjectedAttendance calculateForSubject({
    required Subject subject,
    required List<Attendance> attendanceRecords,
    required Semester semester,
    required List<PlannedLeave> plannedLeaves,
    DateTime? now,
  }) {
    final referenceTime = now ?? DateTime.now();
    final today = DateTime(referenceTime.year, referenceTime.month, referenceTime.day);

    // Filter relevant planned leaves that affect this subject and haven't ended in the past
    final activeLeaves = plannedLeaves.where((leave) {
      final leaveEndDay = DateTime(leave.endDate.year, leave.endDate.month, leave.endDate.day);
      if (leaveEndDay.isBefore(today)) return false;
      if (leave.affectedSubjectIds.isNotEmpty && !leave.affectedSubjectIds.contains(subject.id)) {
        return false;
      }
      return true;
    }).toList();

    if (activeLeaves.isEmpty) {
      return const SubjectProjectedAttendance(
        totalAttended: 0,
        totalMarked: 0,
        plannedMissedCount: 0,
        assumedPresentCount: 0,
        projectedPercentage: 100.0,
        hasActivePlannedLeave: false,
      );
    }

    // Sort leaves by startDate ascending to pick the next immediate upcoming/ongoing leave
    activeLeaves.sort((a, b) => a.startDate.compareTo(b.startDate));
    final immediateLeave = activeLeaves.first;

    // Horizon is bounded by the end date of the immediate leave (and any overlapping leaves)
    DateTime horizonEndDate = immediateLeave.endDate;
    final leavesForHorizon = <PlannedLeave>[];
    for (final l in activeLeaves) {
      if (!l.startDate.isAfter(horizonEndDate)) {
        leavesForHorizon.add(l);
        if (l.endDate.isAfter(horizonEndDate)) {
          horizonEndDate = l.endDate;
        }
      }
    }

    final maxHorizonDate = horizonEndDate.isAfter(semester.endDate) ? semester.endDate : horizonEndDate;
    final maxHorizonDay = DateTime(maxHorizonDate.year, maxHorizonDate.month, maxHorizonDate.day, 23, 59, 59);

    // Determine counting start
    final manualOverride = subject.manualAttendanceOverride;
    DateTime countingStart = manualOverride?.effectiveFrom ?? semester.startDate;
    if (countingStart.isBefore(semester.startDate)) {
      countingStart = semester.startDate;
    }
    final countingStartDay = DateTime(countingStart.year, countingStart.month, countingStart.day);

    // Precompute lookup for explicit attendance records for this subject
    final Map<String, AttendanceStatus> recordLookup = {};
    for (final r in attendanceRecords) {
      if (r.subjectId != subject.id) continue;
      final dateKey = '${r.date.year}-${r.date.month}-${r.date.day}_${r.slotKey ?? ''}';
      recordLookup[dateKey] = r.status;
      if (r.slotKey == null || r.slotKey!.isEmpty) {
        recordLookup['${r.date.year}-${r.date.month}-${r.date.day}'] = r.status;
      }
    }

    int attended = manualOverride?.classesAttended ?? 0;
    int held = manualOverride?.classesHeld ?? 0;
    int plannedMissedCount = 0;
    int assumedPresentCount = 0;

    DateTime curDate = countingStartDay;
    while (!curDate.isAfter(maxHorizonDay)) {
      for (final slot in subject.schedule) {
        if (slot.occursOnDate(curDate)) {
          final slotStart = DateTime(curDate.year, curDate.month, curDate.day, slot.startTime.hour, slot.startTime.minute);
          final slotEnd = DateTime(curDate.year, curDate.month, curDate.day, slot.endTime.hour, slot.endTime.minute);

          if (slotStart.isAfter(maxHorizonDate)) continue;

          final dateKeyWithSlot = '${curDate.year}-${curDate.month}-${curDate.day}_${slot.slotKey}';
          final dateKeyNoSlot = '${curDate.year}-${curDate.month}-${curDate.day}';
          final explicitStatus = recordLookup[dateKeyWithSlot] ?? recordLookup[dateKeyNoSlot];

          if (explicitStatus != null) {
            // Explicitly marked by user
            if (explicitStatus == AttendanceStatus.attended) {
              attended++;
              held++;
            } else if (explicitStatus == AttendanceStatus.absent) {
              held++;
              final isCovered = leavesForHorizon.any((leave) =>
                slotStart.isBefore(leave.endDate) && slotEnd.isAfter(leave.startDate));
              if (isCovered) plannedMissedCount++;
            } else if (explicitStatus == AttendanceStatus.cancelled) {
              // Cancelled / Holiday: class not held
            }
          } else {
            // Unmarked slot
            final isCoveredByLeave = leavesForHorizon.any((leave) =>
              slotStart.isBefore(leave.endDate) && slotEnd.isAfter(leave.startDate));

            if (isCoveredByLeave) {
              // Falls in planned leave -> assumed missed
              held++;
              plannedMissedCount++;
            } else {
              // Upcoming class before or between leaves -> assume present!
              attended++;
              held++;
              assumedPresentCount++;
            }
          }
        }
      }
      curDate = curDate.add(const Duration(days: 1));
    }

    final double percentage = held == 0 ? 100.0 : (attended / held) * 100;

    return SubjectProjectedAttendance(
      totalAttended: attended,
      totalMarked: held,
      plannedMissedCount: plannedMissedCount,
      assumedPresentCount: assumedPresentCount,
      projectedPercentage: percentage,
      hasActivePlannedLeave: true,
      latestLeaveEndDate: maxHorizonDate,
      leaveStartDate: immediateLeave.startDate,
      leaveName: immediateLeave.name,
    );
  }

  /// Calculate overall semester projected attendance across all subjects up to next immediate leave.
  static SemesterProjectedAttendance calculateForSemester({
    required List<Subject> subjects,
    required List<Attendance> attendanceRecords,
    required Semester semester,
    required List<PlannedLeave> plannedLeaves,
    DateTime? now,
  }) {
    final referenceTime = now ?? DateTime.now();
    final today = DateTime(referenceTime.year, referenceTime.month, referenceTime.day);

    final activeLeaves = plannedLeaves.where((leave) {
      final leaveEndDay = DateTime(leave.endDate.year, leave.endDate.month, leave.endDate.day);
      return !leaveEndDay.isBefore(today);
    }).toList();

    if (activeLeaves.isEmpty || subjects.isEmpty) {
      return SemesterProjectedAttendance(
        totalAttended: 0,
        totalMarked: 0,
        totalPlannedMissed: 0,
        totalAssumedPresent: 0,
        projectedPercentage: 100.0,
        projectedSlack: 0.0,
        hasActivePlannedLeave: false,
      );
    }

    // Sort leaves by startDate ascending to pick the next immediate upcoming/ongoing leave
    activeLeaves.sort((a, b) => a.startDate.compareTo(b.startDate));
    final immediateLeave = activeLeaves.first;

    // Horizon is bounded by the end date of the immediate leave (and any overlapping leaves)
    DateTime globalHorizonEnd = immediateLeave.endDate;
    final leavesForHorizon = <PlannedLeave>[];
    for (final l in activeLeaves) {
      if (!l.startDate.isAfter(globalHorizonEnd)) {
        leavesForHorizon.add(l);
        if (l.endDate.isAfter(globalHorizonEnd)) {
          globalHorizonEnd = l.endDate;
        }
      }
    }

    final maxHorizonDate = globalHorizonEnd.isAfter(semester.endDate) ? semester.endDate : globalHorizonEnd;
    final maxHorizonDay = DateTime(maxHorizonDate.year, maxHorizonDate.month, maxHorizonDate.day, 23, 59, 59);

    int totalAttended = 0;
    int totalMarked = 0;
    int totalPlannedMissed = 0;
    int totalAssumedPresent = 0;

    for (final subject in subjects) {
      final manualOverride = subject.manualAttendanceOverride;
      DateTime countingStart = manualOverride?.effectiveFrom ?? semester.startDate;
      if (countingStart.isBefore(semester.startDate)) {
        countingStart = semester.startDate;
      }
      final countingStartDay = DateTime(countingStart.year, countingStart.month, countingStart.day);

      final Map<String, AttendanceStatus> recordLookup = {};
      for (final r in attendanceRecords) {
        if (r.subjectId != subject.id) continue;
        final dateKey = '${r.date.year}-${r.date.month}-${r.date.day}_${r.slotKey ?? ''}';
        recordLookup[dateKey] = r.status;
        if (r.slotKey == null || r.slotKey!.isEmpty) {
          recordLookup['${r.date.year}-${r.date.month}-${r.date.day}'] = r.status;
        }
      }

      int subjectAttended = manualOverride?.classesAttended ?? 0;
      int subjectHeld = manualOverride?.classesHeld ?? 0;

      final subjectLeaves = leavesForHorizon.where((leave) =>
        leave.affectedSubjectIds.isEmpty || leave.affectedSubjectIds.contains(subject.id)).toList();

      DateTime curDate = countingStartDay;
      while (!curDate.isAfter(maxHorizonDay)) {
        for (final slot in subject.schedule) {
          if (slot.occursOnDate(curDate)) {
            final slotStart = DateTime(curDate.year, curDate.month, curDate.day, slot.startTime.hour, slot.startTime.minute);
            final slotEnd = DateTime(curDate.year, curDate.month, curDate.day, slot.endTime.hour, slot.endTime.minute);

            if (slotStart.isAfter(maxHorizonDate)) continue;

            final dateKeyWithSlot = '${curDate.year}-${curDate.month}-${curDate.day}_${slot.slotKey}';
            final dateKeyNoSlot = '${curDate.year}-${curDate.month}-${curDate.day}';
            final explicitStatus = recordLookup[dateKeyWithSlot] ?? recordLookup[dateKeyNoSlot];

            if (explicitStatus != null) {
              if (explicitStatus == AttendanceStatus.attended) {
                subjectAttended++;
                subjectHeld++;
              } else if (explicitStatus == AttendanceStatus.absent) {
                subjectHeld++;
                final isCovered = subjectLeaves.any((leave) =>
                  slotStart.isBefore(leave.endDate) && slotEnd.isAfter(leave.startDate));
                if (isCovered) totalPlannedMissed++;
              }
              // Cancelled: not held
            } else {
              final isCoveredByLeave = subjectLeaves.any((leave) =>
                slotStart.isBefore(leave.endDate) && slotEnd.isAfter(leave.startDate));

              if (isCoveredByLeave) {
                subjectHeld++;
                totalPlannedMissed++;
              } else {
                subjectAttended++;
                subjectHeld++;
                totalAssumedPresent++;
              }
            }
          }
        }
        curDate = curDate.add(const Duration(days: 1));
      }

      totalAttended += subjectAttended;
      totalMarked += subjectHeld;
    }

    final double projectedPercentage = totalMarked == 0 ? 100.0 : (totalAttended / totalMarked) * 100;
    final double projectedSlack = projectedPercentage - semester.targetPercentage;

    return SemesterProjectedAttendance(
      totalAttended: totalAttended,
      totalMarked: totalMarked,
      totalPlannedMissed: totalPlannedMissed,
      totalAssumedPresent: totalAssumedPresent,
      projectedPercentage: projectedPercentage,
      projectedSlack: projectedSlack,
      hasActivePlannedLeave: true,
      latestLeaveEndDate: maxHorizonDate,
      leaveStartDate: immediateLeave.startDate,
      leaveName: immediateLeave.name,
    );
  }

  /// Calculate how many continuous classes must be attended after immediate leave end date
  /// to reach the target attendance percentage.
  static PostLeaveRecoveryResult calculateClassesNeededAfterLeave({
    required List<Subject> subjects,
    required Semester semester,
    required int projectedAttended,
    required int projectedMarked,
    required DateTime leaveEndDate,
    double targetPercentage = 75.0,
  }) {
    final double targetRatio = targetPercentage / 100.0;
    final currentRatio = projectedMarked > 0 ? (projectedAttended / projectedMarked) : 1.0;

    // Solve for N continuous classes needed to reach target percentage
    final needed = AttendanceMath.calculateClassesNeededToReachTarget(
      attended: projectedAttended,
      marked: projectedMarked,
      targetPercentage: targetPercentage,
    );

    // Count remaining scheduled classes across all subjects strictly AFTER leaveEndDate
    int remainingAfterLeave = 0;
    DateTime? recoveryDate;
    final semesterEndDay = DateTime(semester.endDate.year, semester.endDate.month, semester.endDate.day, 23, 59, 59);

    DateTime curDate = DateTime(leaveEndDate.year, leaveEndDate.month, leaveEndDate.day).add(const Duration(days: 1));
    while (!curDate.isAfter(semesterEndDay)) {
      for (final subject in subjects) {
        for (final slot in subject.schedule) {
          if (slot.occursOnDate(curDate)) {
            final slotStart = DateTime(curDate.year, curDate.month, curDate.day, slot.startTime.hour, slot.startTime.minute);
            if (slotStart.isAfter(leaveEndDate)) {
              remainingAfterLeave++;
              if (needed != -1 && remainingAfterLeave == needed && recoveryDate == null) {
                recoveryDate = DateTime(curDate.year, curDate.month, curDate.day);
              }
            }
          }
        }
      }
      curDate = curDate.add(const Duration(days: 1));
    }

    if (currentRatio >= targetRatio) {
      return PostLeaveRecoveryResult(
        classesNeeded: 0,
        isAchievable: true,
        remainingAfterLeave: remainingAfterLeave,
        maxAchievablePercentage: currentRatio * 100.0,
      );
    }

    final isAchievable = needed != -1 && needed <= remainingAfterLeave;
    final maxAttainableAttended = projectedAttended + remainingAfterLeave;
    final maxAttainableMarked = projectedMarked + remainingAfterLeave;
    final maxAchievablePercentage = maxAttainableMarked == 0
        ? 100.0
        : (maxAttainableAttended / maxAttainableMarked) * 100.0;

    return PostLeaveRecoveryResult(
      classesNeeded: needed,
      isAchievable: isAchievable,
      remainingAfterLeave: remainingAfterLeave,
      maxAchievablePercentage: maxAchievablePercentage,
      targetRecoveryDate: isAchievable ? recoveryDate : null,
    );
  }
}
