import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendmate/utils/markdown_helper.dart';

void main() {
  group('MarkdownHelper.prepareMarkdown Alert Transformation Tests', () {
    test('transforms > [!IMPORTANT] blockquote alerts', () {
      const input = '''> [!IMPORTANT]
> **Unified Calendar Synchronization**
> Content here.''';

      final output = MarkdownHelper.prepareMarkdown(input);
      expect(output, contains('> 🔔 **IMPORTANT**'));
      expect(output, contains('> **Unified Calendar Synchronization**'));
      expect(output, isNot(contains('[!IMPORTANT]')));
    });

    test('transforms > [!NOTE], [!TIP], [!WARNING], [!CAUTION] alerts', () {
      const input = '''> [!NOTE]
> note text
> [!TIP]
> tip text
> [!WARNING]
> warning text
> [!CAUTION]
> caution text''';

      final output = MarkdownHelper.prepareMarkdown(input);
      expect(output, contains('> ℹ️ **NOTE**'));
      expect(output, contains('> 💡 **TIP**'));
      expect(output, contains('> ⚠️ **WARNING**'));
      expect(output, contains('> 🛑 **CAUTION**'));
      expect(output, isNot(contains('[!NOTE]')));
      expect(output, isNot(contains('[!TIP]')));
      expect(output, isNot(contains('[!WARNING]')));
      expect(output, isNot(contains('[!CAUTION]')));
    });

    test('handles case-insensitivity', () {
      const input = '''> [!important]
> lower
> [!Important]
> title case''';

      final output = MarkdownHelper.prepareMarkdown(input);
      expect(output, contains('> 🔔 **IMPORTANT**'));
      expect(output, isNot(contains('[!important]')));
      expect(output, isNot(contains('[!Important]')));
    });

    test('handles alert with inline title on same line', () {
      const input = '> [!IMPORTANT] Critical Update Needed\n> Details follow.';

      final output = MarkdownHelper.prepareMarkdown(input);
      expect(output, contains('> 🔔 **IMPORTANT**: Critical Update Needed'));
      expect(output, isNot(contains('[!IMPORTANT]')));
    });

    test('handles standalone alert tag without blockquote prefix', () {
      const input = '[!WARNING]\nBe careful with this setting.';

      final output = MarkdownHelper.prepareMarkdown(input);
      expect(output, contains('⚠️ **WARNING**'));
      expect(output, isNot(contains('[!WARNING]')));
    });

    test('preserves empty or standard markdown without alerts', () {
      expect(MarkdownHelper.prepareMarkdown(''), equals(''));
      expect(
        MarkdownHelper.prepareMarkdown('Just regular markdown # Heading'),
        equals('Just regular markdown # Heading'),
      );
    });
  });

  group('MarkdownHelper.buildStyleSheet Tests', () {
    testWidgets('builds high-contrast style for dark theme', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      final style = MarkdownHelper.buildStyleSheet(capturedContext);
      expect(style.blockquoteDecoration, isNotNull);
      final deco = style.blockquoteDecoration as BoxDecoration;
      expect(deco.border, isNotNull);
      expect(deco.borderRadius, isNotNull);
      expect(style.blockquote?.color, isNotNull);
    });

    testWidgets('builds high-contrast style for light theme', (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      final style = MarkdownHelper.buildStyleSheet(capturedContext);
      expect(style.blockquoteDecoration, isNotNull);
      final deco = style.blockquoteDecoration as BoxDecoration;
      expect(deco.border, isNotNull);
      expect(deco.borderRadius, isNotNull);
      expect(style.blockquote?.color, isNotNull);
    });
  });
}
