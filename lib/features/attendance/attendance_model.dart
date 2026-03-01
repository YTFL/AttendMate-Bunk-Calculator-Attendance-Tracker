enum AttendanceStatus { attended, absent, cancelled }

class Attendance {
  final String subjectId;
  final DateTime date;
  final AttendanceStatus status;
  final String? slotKey;

  Attendance({
    required this.subjectId,
    required this.date,
    required this.status,
    this.slotKey,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      subjectId: json['subjectId'],
      date: DateTime.parse(json['date']),
      status: AttendanceStatus.values[json['status']],
      slotKey: json['slotKey'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'subjectId': subjectId,
      'date': date.toIso8601String(),
      'status': status.index,
      'slotKey': slotKey,
    };
  }
}
