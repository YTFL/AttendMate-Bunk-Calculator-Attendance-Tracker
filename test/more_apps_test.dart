import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:attendmate/features/settings/more_screen.dart';
import 'package:attendmate/features/settings/time_format_provider.dart';
import 'package:attendmate/features/tutorial/tutorial_controller.dart';
import 'package:attendmate/models/app_update_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'AttendMate',
      packageName: 'com.ytfl.attendmate',
      version: '2.4.0',
      buildNumber: '2033',
      buildSignature: '',
    );
  });

  test('AppUpdate cleanBuildNumber and normalizeBuildNumber strip ABI offsets', () {
    // arm64-v8a offset (+2000)
    expect(AppUpdate.cleanBuildNumber('2033'), equals('33'));
    expect(AppUpdate.normalizeBuildNumber(2033), equals(33));

    // armeabi-v7a offset (+1000)
    expect(AppUpdate.cleanBuildNumber('1033'), equals('33'));
    expect(AppUpdate.normalizeBuildNumber(1033), equals(33));

    // x86_64 offset (+3000)
    expect(AppUpdate.cleanBuildNumber('3033'), equals('33'));
    expect(AppUpdate.normalizeBuildNumber(3033), equals(33));

    // Non-split base build number (<1000)
    expect(AppUpdate.cleanBuildNumber('33'), equals('33'));
    expect(AppUpdate.normalizeBuildNumber(33), equals(33));

    // Non-numeric fallback
    expect(AppUpdate.cleanBuildNumber('Loading...'), equals('Loading...'));
  });

  testWidgets('MoreScreen displays "More apps by me" tile', (tester) async {
    final tutorialController = TutorialController();
    final timeFormatProvider = TimeFormatProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TutorialController>.value(value: tutorialController),
          ChangeNotifierProvider<TimeFormatProvider>.value(value: timeFormatProvider),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MoreScreen(),
          ),
        ),
      ),
    );

    await tester.pump();

    final titleFinder = find.text('More apps by me');
    await tester.scrollUntilVisible(titleFinder, 200);

    expect(titleFinder, findsOneWidget);
    expect(find.text('Explore other apps and projects on ytfl.github.io'), findsOneWidget);
    expect(find.byIcon(Icons.apps_rounded), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
  });

  testWidgets('MoreScreen displays cleaned build number without ABI prefix', (tester) async {
    final tutorialController = TutorialController();
    final timeFormatProvider = TimeFormatProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TutorialController>.value(value: tutorialController),
          ChangeNotifierProvider<TimeFormatProvider>.value(value: timeFormatProvider),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MoreScreen(),
          ),
        ),
      ),
    );

    // Pump to complete PackageInfo future
    await tester.pumpAndSettle();

    final versionFinder = find.text('v2.4.0 (Build 33)');
    await tester.scrollUntilVisible(versionFinder, 200);

    expect(versionFinder, findsOneWidget);
    expect(find.text('v2.4.0 (Build 2033)'), findsNothing);
  });
}
