class ParsedCoordinates {
  final double latitude;
  final double longitude;

  const ParsedCoordinates({
    required this.latitude,
    required this.longitude,
  });

  @override
  String toString() => '$latitude, $longitude';
}

class CoordinateParser {
  /// Parses latitude and longitude from various formats:
  /// - Plain decimal: "12.971598, 77.594566" or "12.971598 77.594566"
  /// - DMS (Degree Minutes Seconds): 12°58'17.8"N 77°35'40.4"E
  /// - Google Maps URLs:
  ///   - https://maps.google.com/?q=12.971598,77.594566
  ///   - https://www.google.com/maps/search/?api=1&query=12.971598,77.594566
  ///   - https://www.google.com/maps/@12.971598,77.594566,17z
  ///   - https://www.google.com/maps/place/.../@12.971598,77.594566,17z
  ///   - geo:12.971598,77.594566 or geo:0,0?q=12.971598,77.594566
  /// - Copied pin text: "Dropped pin near 12.971598, 77.594566"
  static ParsedCoordinates? parse(String? input) {
    if (input == null || input.trim().isEmpty) {
      return null;
    }

    final trimmed = input.trim();

    // 1. Try URL parameters (e.g. ?q=lat,lng or &query=lat,lng)
    final urlResult = _parseFromUrl(trimmed);
    if (urlResult != null) return urlResult;

    // 2. Try @lat,lng in Google Maps URLs (e.g. /@12.971598,77.594566)
    final atResult = _parseAtCoordinates(trimmed);
    if (atResult != null) return atResult;

    // 3. Try DMS format (e.g. 12°58'17.8"N 77°35'40.4"E)
    final dmsResult = _parseDms(trimmed);
    if (dmsResult != null) return dmsResult;

    // 4. Try standard decimal coordinates in string (e.g. 12.971598, 77.594566)
    final decimalResult = _parseDecimal(trimmed);
    if (decimalResult != null) return decimalResult;

    return null;
  }

  static ParsedCoordinates? _parseFromUrl(String text) {
    try {
      final uri = Uri.tryParse(text);
      if (uri != null) {
        // geo:0,0?q=lat,lng or geo:lat,lng
        if (uri.scheme == 'geo') {
          final queryParam = uri.queryParameters['q'];
          if (queryParam != null) {
            final fromQ = _parseDecimal(queryParam);
            if (fromQ != null) return fromQ;
          }
          final pathParts = uri.path.split(',');
          if (pathParts.length >= 2) {
            final lat = double.tryParse(pathParts[0].trim());
            final lng = double.tryParse(pathParts[1].trim());
            if (lat != null && lng != null && _isValid(lat, lng)) {
              return ParsedCoordinates(latitude: lat, longitude: lng);
            }
          }
        }

        // Standard HTTP / HTTPS URLs
        final q = uri.queryParameters['q'] ?? uri.queryParameters['query'];
        if (q != null) {
          final parsed = _parseDecimal(q);
          if (parsed != null) return parsed;
        }

        // Place parameter: /place/lat,lng or /place/name/@lat,lng
        final match = RegExp(r'/place/[^/]*@?(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(text);
        if (match != null) {
          final lat = double.tryParse(match.group(1)!);
          final lng = double.tryParse(match.group(2)!);
          if (lat != null && lng != null && _isValid(lat, lng)) {
            return ParsedCoordinates(latitude: lat, longitude: lng);
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static ParsedCoordinates? _parseAtCoordinates(String text) {
    // Matches @12.971598,77.594566
    final regex = RegExp(r'@(-?\d+\.\d+),\s*(-?\d+\.\d+)');
    final match = regex.firstMatch(text);
    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null && lng != null && _isValid(lat, lng)) {
        return ParsedCoordinates(latitude: lat, longitude: lng);
      }
    }
    return null;
  }

  static ParsedCoordinates? _parseDms(String text) {
    // Matches 12°58'17.8"N 77°35'40.4"E or 12° 58' 17.8" N, 77° 35' 40.4" E
    final dmsRegex = RegExp(
      r'(\d+)°\s*(\d+)[\x27\u2019\u2032]\s*([\d.]+)[\x22\u201D\u2033]?\s*([NSEWnsew])'
      r'[\s,]+'
      r'(\d+)°\s*(\d+)[\x27\u2019\u2032]\s*([\d.]+)[\x22\u201D\u2033]?\s*([NSEWnsew])',
    );

    final match = dmsRegex.firstMatch(text);
    if (match != null) {
      double d1 = double.parse(match.group(1)!);
      double m1 = double.parse(match.group(2)!);
      double s1 = double.parse(match.group(3)!);
      String dir1 = match.group(4)!.toUpperCase();

      double d2 = double.parse(match.group(5)!);
      double m2 = double.parse(match.group(6)!);
      double s2 = double.parse(match.group(7)!);
      String dir2 = match.group(8)!.toUpperCase();

      double val1 = d1 + (m1 / 60.0) + (s1 / 3600.0);
      if (dir1 == 'S' || dir1 == 'W') val1 = -val1;

      double val2 = d2 + (m2 / 60.0) + (s2 / 3600.0);
      if (dir2 == 'S' || dir2 == 'W') val2 = -val2;

      double lat, lng;
      if (dir1 == 'N' || dir1 == 'S') {
        lat = val1;
        lng = val2;
      } else {
        lat = val2;
        lng = val1;
      }

      if (_isValid(lat, lng)) {
        return ParsedCoordinates(latitude: lat, longitude: lng);
      }
    }
    return null;
  }

  static ParsedCoordinates? _parseDecimal(String text) {
    // Looks for two floating point numbers separated by a comma or space
    final regex = RegExp(r'(-?\d{1,3}\.\d+)\s*[,;\s]\s*(-?\d{1,3}\.\d+)');
    final matches = regex.allMatches(text);

    for (final match in matches) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);

      if (lat != null && lng != null && _isValid(lat, lng)) {
        return ParsedCoordinates(latitude: lat, longitude: lng);
      }
    }

    return null;
  }

  static bool _isValid(double lat, double lng) {
    return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;
  }
}
