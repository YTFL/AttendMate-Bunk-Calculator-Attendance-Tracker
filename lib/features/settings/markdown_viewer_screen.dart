import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../utils/markdown_link_helper.dart';
import '../../widgets/day_cycle_background.dart';

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
    _markdownFuture = _loadAndSanitizeMarkdown();
  }

  Future<String> _loadAndSanitizeMarkdown() async {
    final raw = await rootBundle.loadString(widget.assetPath);
    // Strip web navigation artifacts like "[← Back to Home](index.html)" or "&larr; Back to Home"
    var clean = raw.replaceAll(
      RegExp(r'\[\s*(?:&larr;|←)?\s*Back to Home\s*\]\([^\)]*\)\s*\n?', caseSensitive: false),
      '',
    );
    clean = clean.replaceAll(
      RegExp(r'(?:&larr;|←)\s*Back to Home\s*\n?', caseSensitive: false),
      '',
    );
    return clean.trim();
  }

  IconData _getHeaderIcon() {
    final lower = widget.title.toLowerCase();
    if (lower.contains('privacy')) {
      return Icons.shield_outlined;
    } else if (lower.contains('term')) {
      return Icons.gavel_rounded;
    }
    return Icons.article_outlined;
  }

  String _getCategoryTag() {
    final lower = widget.title.toLowerCase();
    if (lower.contains('privacy')) {
      return 'Data & Privacy';
    } else if (lower.contains('term')) {
      return 'Terms of Use';
    }
    return 'Documentation';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DayCycleBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Custom Frosted Header Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    // Frosted Glass Back Button
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.10)
                                  : Colors.black.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : Colors.black.withValues(alpha: 0.08),
                                width: 0.8,
                              ),
                            ),
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Title & Category Badge
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _getHeaderIcon(),
                                      size: 11,
                                      color: isDark ? Colors.white70 : Colors.black54,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _getCategoryTag().toUpperCase(),
                                      style: GoogleFonts.inter(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: isDark ? Colors.white70 : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.title,
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),

              // Frosted Glass Content Body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF141622).withValues(alpha: 0.55)
                              : Colors.white.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 1.0,
                          ),
                        ),
                        child: FutureBuilder<String>(
                          future: _markdownFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              );
                            }

                            if (snapshot.hasError || !snapshot.hasData) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.error_outline_rounded,
                                        size: 40,
                                        color: isDark ? Colors.white38 : Colors.black38,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Failed to load document content.',
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white70 : Colors.black54,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            return Markdown(
                              data: snapshot.data!,
                              selectable: true,
                              softLineBreak: true,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                              styleSheet: MarkdownLinkHelper.buildStyleSheet(context).copyWith(
                                h1: GoogleFonts.inter(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  height: 1.4,
                                ),
                                h2: GoogleFonts.inter(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  height: 1.4,
                                ),
                                p: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  height: 1.6,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.85)
                                      : const Color(0xFF334155),
                                ),
                              ),
                              onTapLink: (text, href, title) {
                                MarkdownLinkHelper.openLink(context, href);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
