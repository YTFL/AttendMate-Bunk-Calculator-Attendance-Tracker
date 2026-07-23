import 'dart:convert';

class PlannedLeave {
  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final List<String> affectedSubjectIds;

  PlannedLeave({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.affectedSubjectIds,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'affectedSubjectIds': jsonEncode(affectedSubjectIds),
    };
  }

  factory PlannedLeave.fromMap(Map<String, dynamic> map) {
    List<String> subjects = [];
    try {
      final decoded = jsonDecode(map['affectedSubjectIds'] as String);
      subjects = List<String>.from(decoded);
    } catch (_) {
      subjects = [];
    }
    return PlannedLeave(
      id: map['id'] as String,
      name: map['name'] as String,
      startDate: DateTime.parse(map['startDate'] as String),
      endDate: DateTime.parse(map['endDate'] as String),
      affectedSubjectIds: subjects,
    );
  }

  PlannedLeave copyWith({
    String? id,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? affectedSubjectIds,
  }) {
    return PlannedLeave(
      id: id ?? this.id,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      affectedSubjectIds: affectedSubjectIds ?? this.affectedSubjectIds,
    );
  }
}
