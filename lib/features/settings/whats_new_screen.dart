import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../services/update_service.dart';

class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key});

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  late final Future<String> _releaseNotesFuture;

  @override
  void initState() {
    super.initState();
    _releaseNotesFuture = _loadReleaseNotes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('What\'s New'),
      ),
      body: FutureBuilder<String>(
        future: _releaseNotesFuture,
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
    return UpdateService.sanitizeReleaseNotes(markdown);
  }
}
