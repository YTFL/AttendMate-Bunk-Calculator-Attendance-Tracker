import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendmate/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('BackupService - Scheduled Target Time & Session Tracking', () {
    test('getScheduledBackupTargetTime returns null initially', () async {
      final service = BackupService();
      final target = await service.getScheduledBackupTargetTime();
      expect(target, isNull);
    });

    test('setScheduledBackupTargetTime persists target and reason in SharedPreferences', () async {
      final service = BackupService();
      final expectedTarget = DateTime(2026, 9, 12, 13, 0, 0);

      await service.setScheduledBackupTargetTime(expectedTarget, reason: 'Session changes');
      final retrievedTarget = await service.getScheduledBackupTargetTime();

      expect(retrievedTarget, isNotNull);
      expect(retrievedTarget!.millisecondsSinceEpoch, equals(expectedTarget.millisecondsSinceEpoch));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('backup_scheduled_target_time_ms'), equals(expectedTarget.millisecondsSinceEpoch));
      expect(prefs.getString('backup_scheduled_trigger_reason'), equals('Session changes'));
    });

    test('clearScheduledBackupTargetTime removes keys from SharedPreferences', () async {
      final service = BackupService();
      final target = DateTime(2026, 9, 12, 13, 0, 0);

      await service.setScheduledBackupTargetTime(target, reason: 'Session changes');
      expect(await service.getScheduledBackupTargetTime(), isNotNull);

      await service.clearScheduledBackupTargetTime();
      expect(await service.getScheduledBackupTargetTime(), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('backup_scheduled_target_time_ms'), isNull);
      expect(prefs.getString('backup_scheduled_trigger_reason'), isNull);
    });

    test('session change flag can be set and reset', () {
      final service = BackupService();
      service.resetSessionChangeFlag();
      expect(service.hasChangesInCurrentSession, isFalse);

      service.resetSessionChangeFlag();
      expect(service.hasChangesInCurrentSession, isFalse);
    });

    test('hasUnbackedDataChanges tracks dirty flag correctly', () async {
      final service = BackupService();
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('has_unbacked_data_changes', true);
      expect(await service.hasUnbackedDataChanges(), isTrue);

      await service.clearUnbackedDataChanges();
      expect(await service.hasUnbackedDataChanges(), isFalse);
    });
  });
}
