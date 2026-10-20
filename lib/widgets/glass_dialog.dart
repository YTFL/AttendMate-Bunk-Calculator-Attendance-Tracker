import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A premium liquid-glass dialog featuring backdrop blur, specular borders,
/// and harmonious ambient gradient transparency.
class GlassDialog extends StatelessWidget {
  final Widget? icon;
  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? contentPadding;
  final double maxWidth;

  const GlassDialog({
    super.key,
    this.icon,
    this.title,
    this.content,
    this.actions,
    this.contentPadding,
    this.maxWidth = 360,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkMode
                      ? [
                          Colors.white.withValues(alpha: 0.12),
                          const Color(0xFF14141E).withValues(alpha: 0.40),
                          const Color(0xFF0C0C12).withValues(alpha: 0.55),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.88),
                          Colors.white.withValues(alpha: 0.68),
                        ],
                  stops: isDarkMode ? const [0.0, 0.4, 1.0] : const [0.0, 1.0],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.10),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
                    blurRadius: 36,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
            child: SingleChildScrollView(
              child: Padding(
                padding: contentPadding ?? const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (icon != null) ...[
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.16)
                                  : Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          child: icon,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (title != null) ...[
                      DefaultTextStyle(
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                        textAlign: icon != null ? TextAlign.center : TextAlign.start,
                        child: title!,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (content != null) ...[
                      DefaultTextStyle(
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                        child: content!,
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (actions != null && actions!.isNotEmpty) ...[
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: actions!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper function to show a frosted liquid glass dialog.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: isDarkMode ? 0.32 : 0.16),
    builder: (ctx) => builder(ctx),
  );
}
