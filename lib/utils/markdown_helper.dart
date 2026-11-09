import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class MarkdownHelper {
  /// Preprocesses markdown text by transforming GitHub-style alerts
  /// ([!NOTE], [!TIP], [!IMPORTANT], [!WARNING], [!CAUTION]) into beautiful,
  /// standard markdown headers with appropriate iconography and labels.
  static String prepareMarkdown(String markdown) {
    if (markdown.trim().isEmpty) return markdown;

    var normalized = markdown.replaceAll('\r\n', '\n');

    // 1. Transform blockquote alerts like:
    // > [!IMPORTANT]
    // > [!NOTE] Title
    final blockquoteAlertRegex = RegExp(
      r'^(\s*>\s*)\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\](?:\s+(.*))?$',
      multiLine: true,
      caseSensitive: false,
    );

    normalized = normalized.replaceAllMapped(blockquoteAlertRegex, (match) {
      final prefix = match.group(1) ?? '> ';
      final type = (match.group(2) ?? '').toUpperCase();
      final rest = match.group(3)?.trim();

      final alert = _getAlertDetails(type);
      final icon = alert.icon;
      final label = alert.label;

      if (rest != null && rest.isNotEmpty) {
        return '$prefix$icon **$label**: $rest\n$prefix';
      }
      return '$prefix$icon **$label**\n$prefix';
    });

    // 2. Transform standalone alerts outside blockquotes like:
    // [!IMPORTANT]
    final standaloneAlertRegex = RegExp(
      r'^(\s*)\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\](?:\s+(.*))?$',
      multiLine: true,
      caseSensitive: false,
    );

    normalized = normalized.replaceAllMapped(standaloneAlertRegex, (match) {
      final prefix = match.group(1) ?? '';
      final type = (match.group(2) ?? '').toUpperCase();
      final rest = match.group(3)?.trim();

      final alert = _getAlertDetails(type);
      final icon = alert.icon;
      final label = alert.label;

      if (rest != null && rest.isNotEmpty) {
        return '$prefix$icon **$label**: $rest';
      }
      return '$prefix$icon **$label**';
    });

    return normalized;
  }

  static ({String icon, String label}) _getAlertDetails(String type) {
    switch (type) {
      case 'NOTE':
        return (icon: 'ℹ️', label: 'NOTE');
      case 'TIP':
        return (icon: '💡', label: 'TIP');
      case 'IMPORTANT':
        return (icon: '🔔', label: 'IMPORTANT');
      case 'WARNING':
        return (icon: '⚠️', label: 'WARNING');
      case 'CAUTION':
        return (icon: '🛑', label: 'CAUTION');
      default:
        return (icon: '📌', label: type);
    }
  }

  /// Builds a cohesive, high-contrast MarkdownStyleSheet respecting
  /// dark and light mode, with properly styled blockquotes, code blocks,
  /// borders, and headers.
  static MarkdownStyleSheet buildStyleSheet(
    BuildContext context, {
    TextStyle? p,
    TextStyle? code,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseStyle = MarkdownStyleSheet.fromTheme(theme);

    final defaultTextColor = isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87;

    return baseStyle.copyWith(
      p: p ?? baseStyle.p?.copyWith(color: defaultTextColor, height: 1.5),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      blockquoteDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.grey.shade100,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: Border(
          left: BorderSide(
            color: isDark ? const Color(0xFF64B5F6) : theme.colorScheme.primary,
            width: 4.0,
          ),
          top: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
            width: 1.0,
          ),
          right: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
            width: 1.0,
          ),
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
            width: 1.0,
          ),
        ),
      ),
      blockquote: theme.textTheme.bodyMedium?.copyWith(
        color: defaultTextColor,
        height: 1.5,
      ),
      code: code ??
          theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: isDark ? const Color(0xFF81D4FA) : Colors.blue.shade900,
          ),
      codeblockDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      h1: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
    );
  }
}
