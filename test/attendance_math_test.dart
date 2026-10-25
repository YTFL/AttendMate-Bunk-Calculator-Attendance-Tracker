import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/utils/attendance_math.dart';

void main() {
  group('AttendanceMath Tests', () {
    group('calculateClassesNeededToReachTarget', () {
      test('returns 0 when marked is 0', () {
        expect(
          AttendanceMath.calculateClassesNeededToReachTarget(
            attended: 0,
            marked: 0,
            targetPercentage: 75.0,
          ),
          equals(0),
        );
      });

      test('returns 0 when already above target', () {
        expect(
          AttendanceMath.calculateClassesNeededToReachTarget(
            attended: 8,
            marked: 10,
            targetPercentage: 75.0,
          ),
          equals(0),
        );
      });

      test('returns 0 when attendance is exactly at target', () {
        expect(
          AttendanceMath.calculateClassesNeededToReachTarget(
            attended: 3,
            marked: 4,
            targetPercentage: 75.0,
          ),
          equals(0),
        );
      });

      test('returns 10 when 5/10 attended and target is 75%', () {
        // (5 + 10) / (10 + 10) = 15/20 = 75%
        expect(
          AttendanceMath.calculateClassesNeededToReachTarget(
            attended: 5,
            marked: 10,
            targetPercentage: 75.0,
          ),
          equals(10),
        );
      });

      test('returns 5 when 7/10 attended and target is 80%', () {
        // (7 + 5) / (10 + 5) = 12/15 = 80%
        expect(
          AttendanceMath.calculateClassesNeededToReachTarget(
            attended: 7,
            marked: 10,
            targetPercentage: 80.0,
          ),
          equals(5),
        );
      });

      test('returns 5 when 4/7 attended and target is 75%', () {
        // (4 + 5) / (7 + 5) = 9/12 = 75%
        expect(
          AttendanceMath.calculateClassesNeededToReachTarget(
            attended: 4,
            marked: 7,
            targetPercentage: 75.0,
          ),
          equals(5),
        );
      });

      test('returns 4 when 6/10 attended and target is 70%', () {
        // (6 + 4) / (10 + 4) = 10/14 = 71.4% >= 70%
        // (6 + 3) / (10 + 3) = 9/13 = 69.2% < 70%
        expect(
          AttendanceMath.calculateClassesNeededToReachTarget(
            attended: 6,
            marked: 10,
            targetPercentage: 70.0,
          ),
          equals(4),
        );
      });

      test('returns -1 when target is 100% and a class was missed', () {
        expect(
          AttendanceMath.calculateClassesNeededToReachTarget(
            attended: 9,
            marked: 10,
            targetPercentage: 100.0,
          ),
          equals(-1),
        );
      });
    });

    group('calculateBunkableClasses', () {
      test('returns 0 when marked is 0', () {
        expect(
          AttendanceMath.calculateBunkableClasses(
            attended: 0,
            marked: 0,
            targetPercentage: 75.0,
          ),
          equals(0),
        );
      });

      test('returns 0 when below target', () {
        expect(
          AttendanceMath.calculateBunkableClasses(
            attended: 5,
            marked: 10,
            targetPercentage: 75.0,
          ),
          equals(0),
        );
      });

      test('returns 0 when exactly at target', () {
        // 3/4 = 75%. Bunking 1 class gives 3/5 = 60% < 75%.
        expect(
          AttendanceMath.calculateBunkableClasses(
            attended: 3,
            marked: 4,
            targetPercentage: 75.0,
          ),
          equals(0),
        );
      });

      test('returns 0 when above target but bunking 1 class drops below target', () {
        // 8/10 = 80% > 75%. Bunking 1 class gives 8/11 = 72.7% < 75%.
        expect(
          AttendanceMath.calculateBunkableClasses(
            attended: 8,
            marked: 10,
            targetPercentage: 75.0,
          ),
          equals(0),
        );
      });

      test('returns 3 when 10/10 attended and target is 75%', () {
        // 10/(10 + 3) = 10/13 = 76.9% >= 75%
        // 10/(10 + 4) = 10/14 = 71.4% < 75%
        expect(
          AttendanceMath.calculateBunkableClasses(
            attended: 10,
            marked: 10,
            targetPercentage: 75.0,
          ),
          equals(3),
        );
      });

      test('returns 1 when 9/10 attended and target is 80%', () {
        // 9/(10 + 1) = 9/11 = 81.8% >= 80%
        // 9/(10 + 2) = 9/12 = 75.0% < 80%
        expect(
          AttendanceMath.calculateBunkableClasses(
            attended: 9,
            marked: 10,
            targetPercentage: 80.0,
          ),
          equals(1),
        );
      });
    });

    group('calculateBunkableDeficitOrSurplus', () {
      test('returns positive count when above target with bunkable classes', () {
        expect(
          AttendanceMath.calculateBunkableDeficitOrSurplus(
            attended: 10,
            marked: 10,
            targetPercentage: 75.0,
          ),
          equals(3),
        );
      });

      test('returns 0 when exactly at target', () {
        expect(
          AttendanceMath.calculateBunkableDeficitOrSurplus(
            attended: 3,
            marked: 4,
            targetPercentage: 75.0,
          ),
          equals(0),
        );
      });

      test('returns negative classes needed when below target', () {
        // 5/10 with 75% target needs 10 classes to reach 75% -> -10
        expect(
          AttendanceMath.calculateBunkableDeficitOrSurplus(
            attended: 5,
            marked: 10,
            targetPercentage: 75.0,
          ),
          equals(-10),
        );
      });

      test('returns -5 when 7/10 with 80% target', () {
        expect(
          AttendanceMath.calculateBunkableDeficitOrSurplus(
            attended: 7,
            marked: 10,
            targetPercentage: 80.0,
          ),
          equals(-5),
        );
      });
    });
  });
}
