class Semester {
  final DateTime startDate;
  final DateTime endDate;
  final double targetPercentage;

  Semester({
    required this.startDate,
    required this.endDate,
    required this.targetPercentage,
  });

  factory Semester.fromJson(Map<String, dynamic> json) {
    return Semester(
      startDate: DateTime.parse(json['startDate']),
      endDate: DateTime.parse(json['endDate']),
      targetPercentage: json['targetPercentage'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'targetPercentage': targetPercentage,
    };
  }
}
