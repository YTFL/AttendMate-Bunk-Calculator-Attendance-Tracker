import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../utils/markdown_helper.dart';
import '../../utils/markdown_link_helper.dart';

class MarkdownViewerScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const MarkdownViewerScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  @override
  State<MarkdownViewerScreen> createState() => _MarkdownViewerScreenState();
}

class _MarkdownViewerScreenState extends State<MarkdownViewerScreen> {
  late final Future<String> _markdownFuture;

  @override
  void initState() {
    super.initState();
    _markdownFuture = _loadMarkdown();
  }

  Future<String> _loadMarkdown() async {
    final raw = await rootBundle.loadString(widget.assetPath);
    return MarkdownHelper.prepareMarkdown(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: FutureBuilder<String>(
        future: _markdownFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Failed to load document content.',
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
            styleSheet: MarkdownHelper.buildStyleSheet(context),
            onTapLink: (text, href, title) {
              MarkdownLinkHelper.openLink(context, href);
            },
          );
        },
      ),
    );
  }
}
