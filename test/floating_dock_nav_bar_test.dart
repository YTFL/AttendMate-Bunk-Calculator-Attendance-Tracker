import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/features/home/floating_dock_nav_bar.dart';

void main() {
  group('FloatingDockNavBar Widget Tests', () {
    final testItems = [
      const FloatingDockItem(icon: Icons.today_rounded, label: 'Today'),
      const FloatingDockItem(icon: Icons.subject_rounded, label: 'Subjects'),
      const FloatingDockItem(icon: Icons.school_rounded, label: 'Semester'),
      const FloatingDockItem(icon: Icons.calculate_rounded, label: 'Bunk Meter'),
      const FloatingDockItem(icon: Icons.more_horiz_rounded, label: 'More'),
    ];

    testWidgets('renders all 5 navigation items and their labels', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            bottomNavigationBar: FloatingDockNavBar(
              selectedIndex: 0,
              onItemTapped: (_) {},
              items: testItems,
            ),
          ),
        ),
      );

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Subjects'), findsOneWidget);
      expect(find.text('Semester'), findsOneWidget);
      expect(find.text('Bunk Meter'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(find.byIcon(Icons.today_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    });

    testWidgets('triggers onItemTapped callback on item tap', (tester) async {
      int tappedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            bottomNavigationBar: FloatingDockNavBar(
              selectedIndex: 0,
              onItemTapped: (index) => tappedIndex = index,
              items: testItems,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Subjects'));
      await tester.pumpAndSettle();

      expect(tappedIndex, equals(1));

      await tester.tap(find.text('Bunk Meter'));
      await tester.pumpAndSettle();

      expect(tappedIndex, equals(3));
    });

    testWidgets('renders properly in dark mode without crashing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            bottomNavigationBar: FloatingDockNavBar(
              selectedIndex: 2,
              onItemTapped: (_) {},
              items: testItems,
            ),
          ),
        ),
      );

      expect(find.byType(FloatingDockNavBar), findsOneWidget);
      expect(find.text('Semester'), findsOneWidget);
    });

    testWidgets('hides dock when soft keyboard is active (viewInsets.bottom > 0)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              viewInsets: EdgeInsets.only(bottom: 300), // Simulate open keyboard
            ),
            child: Scaffold(
              bottomNavigationBar: FloatingDockNavBar(
                selectedIndex: 0,
                onItemTapped: (_) {},
                items: testItems,
              ),
            ),
          ),
        ),
      );

      // The dock should return SizedBox.shrink() and not display tab texts
      expect(find.text('Today'), findsNothing);
      expect(find.text('Subjects'), findsNothing);
    });

    testWidgets('pill highlight animates position when selectedIndex changes', (tester) async {
      int selectedIndex = 0;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                bottomNavigationBar: FloatingDockNavBar(
                  selectedIndex: selectedIndex,
                  onItemTapped: (index) {
                    setState(() {
                      selectedIndex = index;
                    });
                  },
                  items: testItems,
                ),
              ),
            );
          },
        ),
      );

      final pillFinder = find.byKey(const ValueKey('dock_sliding_pill'));
      expect(pillFinder, findsOneWidget);
      final initialOffset = tester.getTopLeft(pillFinder);

      // Tap on tab 2 ("Semester")
      await tester.tap(find.text('Semester'));
      await tester.pump(); // Start animation
      await tester.pump(const Duration(milliseconds: 140)); // Mid animation
      final midOffset = tester.getTopLeft(pillFinder);
      expect(midOffset.dx, greaterThan(initialOffset.dx));

      await tester.pumpAndSettle(); // End animation
      final finalOffset = tester.getTopLeft(pillFinder);
      expect(finalOffset.dx, greaterThan(midOffset.dx));
    });

    testWidgets('pill highlight has correct theme color (translucent black in light mode, translucent white in dark mode)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: Theme(
              data: ThemeData.light(),
              child: FloatingDockNavBar(
                key: const Key('light_dock'),
                selectedIndex: 0,
                onItemTapped: (_) {},
                items: testItems,
              ),
            ),
          ),
        ),
      );

      Container pillContainer = tester.widget(
        find.descendant(
          of: find.byKey(const ValueKey('dock_sliding_pill')),
          matching: find.byType(Container),
        ),
      );
      BoxDecoration decoration = pillContainer.decoration as BoxDecoration;
      expect(decoration.color, equals(Colors.black.withValues(alpha: 0.10)));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: Theme(
              data: ThemeData.dark(),
              child: FloatingDockNavBar(
                key: const Key('dark_dock'),
                selectedIndex: 0,
                onItemTapped: (_) {},
                items: testItems,
              ),
            ),
          ),
        ),
      );

      pillContainer = tester.widget(
        find.descendant(
          of: find.byKey(const ValueKey('dock_sliding_pill')),
          matching: find.byType(Container),
        ),
      );
      decoration = pillContainer.decoration as BoxDecoration;
      expect(decoration.color, equals(Colors.white.withValues(alpha: 0.18)));
    });
  });
}
