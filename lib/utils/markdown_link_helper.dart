import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'url_launcher_utils.dart';

class MarkdownLinkHelper {
  /// Open a markdown link (URL, mailto:, etc.)
  static Future<void> openLink(BuildContext context, String? href) async {
    if (href == null || href.trim().isEmpty) return;

    final result = await UrlLauncherUtils.launchExternalUrl(href, context: context);
    if (result == LaunchResult.failed && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open link: $href')),
      );
    }
  }

  /// Builds a cohesive, liquid-glass markdown stylesheet that respects the app's
  /// theme, eliminates unreadable blue blockquote boxes, and delivers optimal contrast.
  static MarkdownStyleSheet buildStyleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: GoogleFonts.inter(
        fontSize: 13.5,
        height: 1.5,
        color: colorScheme.onSurface.withValues(alpha: 0.88),
      ),
      h1: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
        height: 1.35,
      ),
      h2: GoogleFonts.inter(
        fontSize: 15.5,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
        height: 1.35,
      ),
      h3: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
        height: 1.35,
      ),
      listBullet: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.bold,
      ),
      strong: GoogleFonts.inter(
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurface,
      ),
      em: GoogleFonts.inter(
        fontStyle: FontStyle.italic,
        color: colorScheme.onSurface.withValues(alpha: 0.80),
      ),
      // Frosted liquid-glass blockquote: subtle background + primary left bar + specular border
      blockquote: GoogleFonts.inter(
        fontSize: 13,
        height: 1.45,
        fontStyle: FontStyle.italic,
        color: colorScheme.onSurface.withValues(alpha: 0.90),
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      blockquoteDecoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      // Codeblock in frosted glass container
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12.5,
        color: colorScheme.primary,
        backgroundColor: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            width: 1.0,
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
      ),
    );
  }
}

