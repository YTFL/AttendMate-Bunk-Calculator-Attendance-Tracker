class LocationConfig {
  final String id;
  final String name;
  final String? block;
  final double? latitude;
  final double? longitude;

  LocationConfig({
    required this.id,
    required this.name,
    this.block,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'block': block,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory LocationConfig.fromMap(Map<String, dynamic> map) {
    return LocationConfig(
      id: map['id'] as String,
      name: map['name'] as String,
      block: map['block'] as String?,
      latitude: map['latitude'] != null ? (map['latitude'] as num).toDouble() : null,
      longitude: map['longitude'] != null ? (map['longitude'] as num).toDouble() : null,
    );
  }

  LocationConfig copyWith({
    String? id,
    String? name,
    String? block,
    double? latitude,
    double? longitude,
  }) {
    return LocationConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      block: block ?? this.block,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}
