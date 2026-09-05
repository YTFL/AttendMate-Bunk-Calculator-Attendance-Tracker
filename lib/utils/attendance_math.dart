class AttendanceMath {
  /// Calculates how many consecutive upcoming classes can be bunked while keeping
  /// attendance at or above [targetPercentage].
  ///
  /// Formula: k = floor((attended - targetRatio * marked) / targetRatio)
  /// Returns 0 if already below target or if no classes can be bunked.
  static int calculateBunkableClasses({
    required int attended,
    required int marked,
    required double targetPercentage,
  }) {
    if (marked == 0 || targetPercentage <= 0) return 0;
    final targetRatio = targetPercentage / 100.0;
    final currentRatio = attended / marked;
    if (currentRatio < targetRatio) return 0;

    int bunkable = ((attended - targetRatio * marked) / targetRatio + 1e-9).floor();
    if (bunkable < 0) bunkable = 0;
    while (bunkable > 0 && (attended / (marked + bunkable)) < targetRatio) {
      bunkable--;
    }
    while ((attended / (marked + bunkable + 1)) >= targetRatio) {
      bunkable++;
    }
    return bunkable;
  }

  /// Calculates how many consecutive upcoming classes must be attended to reach
  /// [targetPercentage].
  ///
  /// Formula: x = ceil((targetRatio * marked - attended) / (1 - targetRatio))
  /// Returns 0 if already at or above target.
  /// Returns -1 if target >= 100% and attendance < 100% (unreachable).
  static int calculateClassesNeededToReachTarget({
    required int attended,
    required int marked,
    required double targetPercentage,
  }) {
    if (marked == 0) return 0;
    final targetRatio = targetPercentage / 100.0;
    final currentRatio = attended / marked;
    if (currentRatio >= targetRatio) return 0;
    if (targetRatio >= 1.0) {
      // Cannot reach 100% if already missed classes
      return -1;
    }

    int needed = ((targetRatio * marked - attended) / (1.0 - targetRatio) - 1e-9).ceil();
    if (needed < 1) needed = 1;
    while ((attended + needed) / (marked + needed) < targetRatio) {
      needed++;
    }
    while (needed > 1 && (attended + needed - 1) / (marked + needed - 1) >= targetRatio) {
      needed--;
    }
    return needed;
  }

  /// Calculates the signed bunkable metric:
  /// - Positive (+k): number of classes you can safely bunk and remain >= target.
  /// - 0: attendance is exactly at target or no marked classes.
  /// - Negative (-x): number of consecutive classes you must attend to get back to target.
  static int calculateBunkableDeficitOrSurplus({
    required int attended,
    required int marked,
    required double targetPercentage,
  }) {
    if (marked == 0) return 0;
    final targetRatio = targetPercentage / 100.0;
    final currentRatio = attended / marked;

    if (currentRatio > targetRatio) {
      return calculateBunkableClasses(
        attended: attended,
        marked: marked,
        targetPercentage: targetPercentage,
      );
    } else if (currentRatio < targetRatio) {
      final needed = calculateClassesNeededToReachTarget(
        attended: attended,
        marked: marked,
        targetPercentage: targetPercentage,
      );
      if (needed == -1) {
        // Target is 100% and unattainable; deficit is at least marked - attended
        return -(marked - attended);
      }
      return -needed;
    } else {
      return 0;
    }
  }
}
