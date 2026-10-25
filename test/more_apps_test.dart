import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:attendmate/features/settings/more_screen.dart';
import 'package:attendmate/features/settings/time_format_provider.dart';
import 'package:attendmate/features/tutorial/tutorial_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'AttendMate',
      packageName: 'com.ytfl.attendmate',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
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
}
