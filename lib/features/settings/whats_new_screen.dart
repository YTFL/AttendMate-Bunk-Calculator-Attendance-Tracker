import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';

class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('What\'s New'),
      ),
      body: FutureBuilder<String>(
        future: _loadReleaseNotes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Failed to load release notes for this version.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return Markdown(
            data: snapshot.data!,
            selectable: true,
            softLineBreak: true,
            padding: const EdgeInsets.all(16),
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
          );
        },
      ),
    );
  }

  Future<String> _loadReleaseNotes() async {
    final markdown = await rootBundle.loadString('git_public/RELEASE_NOTES.md');
    return _sanitizeBundledReleaseNotes(markdown);
  }

  String _sanitizeBundledReleaseNotes(String markdown) {
    final normalized = markdown.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) return normalized;

    var lines = normalized.split('\n');
    lines = _removeTopMetadataBlock(lines);
    lines = _removeInstallationSection(lines);

    return lines.join('\n').trim();
  }

  List<String> _removeTopMetadataBlock(List<String> lines) {
    if (lines.isEmpty) return lines;

    final firstNonEmptyIndex = lines.indexWhere((line) => line.trim().isNotEmpty);
    if (firstNonEmptyIndex == -1) return lines;

    final firstNonEmpty = lines[firstNonEmptyIndex].trim();
    if (!firstNonEmpty.startsWith('# ')) {
      return lines;
    }

    final separatorIndex = lines.indexWhere(
      (line) => line.trim() == '---',
      firstNonEmptyIndex,
    );

    if (separatorIndex == -1) {
      return lines;
    }

    return lines.sublist(separatorIndex + 1);
  }

  List<String> _removeInstallationSection(List<String> lines) {
    if (lines.isEmpty) return lines;

    final installationHeaderRegex = RegExp(r'^##\s+.*installation', caseSensitive: false);
    final sectionHeaderRegex = RegExp(r'^##\s+');

    final startIndex = lines.indexWhere(
      (line) => installationHeaderRegex.hasMatch(line.trim()),
    );

    if (startIndex == -1) {
      return lines;
    }

    var endIndex = lines.length;
    for (var index = startIndex + 1; index < lines.length; index++) {
      if (sectionHeaderRegex.hasMatch(lines[index].trim())) {
        endIndex = index;
        break;
      }
    }

    return [
      ...lines.sublist(0, startIndex),
      ...lines.sublist(endIndex),
    ];
  }
}
