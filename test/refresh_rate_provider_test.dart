import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendmate/features/settings/refresh_rate_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RefreshRateOption', () {
    test('targetHz mappings are correct', () {
      expect(RefreshRateOption.deviceDefault.targetHz, isNull);
      expect(RefreshRateOption.hz60.targetHz, 60);
      expect(RefreshRateOption.hz90.targetHz, 90);
      expect(RefreshRateOption.hz120.targetHz, 120);
    });

    test('label mappings are formatted cleanly', () {
      expect(RefreshRateOption.deviceDefault.label, 'Default');
      expect(RefreshRateOption.hz60.label, '60 Hz');
      expect(RefreshRateOption.hz90.label, '90 Hz');
      expect(RefreshRateOption.hz120.label, '120 Hz');
    });
  });

  group('RefreshRateProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to deviceDefault and initializes cleanly', () async {
      final provider = RefreshRateProvider();
      expect(provider.selectedOption, RefreshRateOption.deviceDefault);

      await provider.init();
      expect(provider.isInitialized, isTrue);
      expect(provider.selectedOption, RefreshRateOption.deviceDefault);
    });

    test('saves and loads preference properly', () async {
      final provider1 = RefreshRateProvider();
      await provider1.init();
      await provider1.setOption(RefreshRateOption.hz120);
      expect(provider1.selectedOption, RefreshRateOption.hz120);

      // Verify second provider reads the saved preference
      final provider2 = RefreshRateProvider();
      await provider2.init();
      expect(provider2.selectedOption, RefreshRateOption.hz120);
    });
  });
}
