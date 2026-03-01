class AppUpdate {
  final String version;
  final int buildNumber;
  final String changelog;

  AppUpdate({
    required this.version,
    required this.buildNumber,
    required this.changelog,
  });

  /// Parse JSON response from update.json
  factory AppUpdate.fromJson(Map<String, dynamic> json) {
    final buildNumberValue = json['buildNumber'];
    final parsedBuildNumber = switch (buildNumberValue) {
      int value => value,
      String value => int.tryParse(value) ?? 0,
      _ => 0,
    };

    return AppUpdate(
      version: json['version'] as String? ?? '0.0.0',
      buildNumber: parsedBuildNumber,
      changelog: json['changelog'] as String? ?? '',
    );
  }

  /// Compare versions: returns 1 if left > right, -1 if left < right, 0 if equal.
  static int compareVersions(String left, String right) {
    List<int> parseVersion(String version) {
      return version.split('.').map((part) {
        final normalizedPart = part.split('+')[0];
        final digits = RegExp(r'\d+').firstMatch(normalizedPart)?.group(0);
        return int.tryParse(digits ?? '') ?? 0;
      }).toList();
    }

    final leftParts = parseVersion(left);
    final rightParts = parseVersion(right);

    final maxLength = [leftParts.length, rightParts.length].reduce((a, b) => a > b ? a : b);
    while (leftParts.length < maxLength) {
      leftParts.add(0);
    }
    while (rightParts.length < maxLength) {
      rightParts.add(0);
    }

    for (int index = 0; index < maxLength; index++) {
      if (leftParts[index] > rightParts[index]) return 1;
      if (leftParts[index] < rightParts[index]) return -1;
    }

    return 0;
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'buildNumber': buildNumber,
      'changelog': changelog,
    };
  }

  /// Create a copy with some fields replaced
  AppUpdate copyWith({
    String? version,
    int? buildNumber,
    String? changelog,
  }) {
    return AppUpdate(
      version: version ?? this.version,
      buildNumber: buildNumber ?? this.buildNumber,
      changelog: changelog ?? this.changelog,
    );
  }

  /// Compare versions: returns true if other is greater than this
  /// Example: AppUpdate('1.0.0').isOlderThan(AppUpdate('1.0.1')) => true
  static bool isVersionGreater(String newVersion, String currentVersion) {
    return compareVersions(newVersion, currentVersion) > 0;
  }

  /// Get version string without build number
  get versionInfo => version;

  @override
  String toString() => 'AppUpdate(version: $version, buildNumber: $buildNumber, changelog: $changelog)';
}
