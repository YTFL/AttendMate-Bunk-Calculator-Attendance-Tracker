import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../semester/semester_provider.dart';
import 'tutorial_controller.dart';

class TutorialOverlay extends StatefulWidget {
  final Widget child;

  const TutorialOverlay({super.key, required this.child});

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.0, end: 10.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Rect? _getRectForTarget(GlobalKey? key, EdgeInsets padding) {
    if (key == null) return null;
    final context = key.currentContext;
    if (context == null) return null;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return null;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      offset.dx - padding.left,
      offset.dy - padding.top,
      size.width + padding.left + padding.right,
      size.height + padding.top + padding.bottom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<TutorialController>(context);

    return Stack(
      children: [
        widget.child,
        if (controller.isActive && controller.currentStep != null)
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, _) {
              final step = controller.currentStep!;
              final targetKey = controller.getKey(step.targetKeyName);
              final targetRect = _getRectForTarget(targetKey, step.targetPadding);
              final screenSize = MediaQuery.of(context).size;
              final theme = Theme.of(context);
              final isDarkMode = theme.brightness == Brightness.dark;

              final backdropColor = isDarkMode
                  ? Colors.black.withValues(alpha: 0.85)
                  : Colors.black.withValues(alpha: 0.72);

              return Stack(
                children: [
                  // Fullscreen Backdrop with Cutout Hole around target widget
                  if (targetRect != null) ...[
                    // Backdrop everywhere EXCEPT targetRect (so target receives real taps)
                    ClipPath(
                      clipper: InvertedRRectClipper(
                        rect: targetRect,
                        borderRadius: step.borderRadius,
                      ),
                      child: GestureDetector(
                        onTap: () {
                          // Tap outside target bounds - prompt user to tap highlighted target or next
                        },
                        child: Container(
                          width: screenSize.width,
                          height: screenSize.height,
                          color: backdropColor,
                        ),
                      ),
                    ),



                    // Pulsing Highlight Border around target cutout
                    Positioned.fromRect(
                      rect: targetRect.inflate(_pulseAnimation.value / 2),
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: step.borderRadius,
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: (0.9 - _pulseAnimation.value / 18).clamp(0.3, 0.9),
                              ),
                              width: 3.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Full Backdrop when no specific target widget
                    GestureDetector(
                      onTap: () => controller.nextStep(),
                      child: Container(
                        width: screenSize.width,
                        height: screenSize.height,
                        color: backdropColor,
                      ),
                    ),
                  ],

                  // Pointing Arrow (Theme Aligned)
                  if (targetRect != null)
                    _buildPointerArrow(theme, targetRect, screenSize),

                  // Callout Card (Theme Aligned)
                  _buildCalloutCard(context, theme, controller, step, targetRect, screenSize),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _buildPointerArrow(ThemeData theme, Rect targetRect, Size screenSize) {
    final bool positionAbove = targetRect.top > screenSize.height * 0.45;
    final double arrowX = targetRect.center.dx.clamp(36.0, screenSize.width - 36.0);
    final double arrowY = positionAbove ? targetRect.top - 20 : targetRect.bottom + 20;

    return Positioned(
      left: arrowX - 16,
      top: arrowY - 16,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: positionAbove ? math.pi : 0,
          child: Icon(
            Icons.arrow_downward_rounded,
            color: theme.colorScheme.primary,
            size: 34,
          ),
        ),
      ),
    );
  }

  Widget _buildCalloutCard(
    BuildContext context,
    ThemeData theme,
    TutorialController controller,
    TutorialStep step,
    Rect? targetRect,
    Size screenSize,
  ) {
    bool positionAbove = step.preferPositionAbove;
    if (!positionAbove && targetRect != null) {
      positionAbove = targetRect.top > screenSize.height * 0.45;
    }

    final double topMargin = MediaQuery.of(context).padding.top + 16;
    final double bottomMargin = MediaQuery.of(context).padding.bottom + 16;

    double? cardTop;
    double? cardBottom;

    if (targetRect == null) {
      cardTop = (screenSize.height - 240) / 2;
    } else if (step.preferPositionAbove) {
      cardTop = topMargin + 12;
    } else if (positionAbove) {
      cardBottom = (screenSize.height - targetRect.top) + 24;
      if (cardBottom > screenSize.height - topMargin - 160) {
        cardBottom = screenSize.height - topMargin - 160;
      }
    } else {
      cardTop = targetRect.bottom + 24;
      if (cardTop > screenSize.height - bottomMargin - 180) {
        cardTop = screenSize.height - bottomMargin - 180;
      }
    }

    final isDark = theme.brightness == Brightness.dark;

    return Positioned(
      left: 16,
      right: 16,
      top: cardTop,
      bottom: cardBottom,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'STEP ${controller.currentStepIndex + 1} OF ${controller.totalSteps}',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => controller.skipTutorial(),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.textTheme.bodySmall?.color ?? Colors.grey,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(50, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Skip Tour'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                step.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ) ?? const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                step.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.4,
                  fontSize: 14,
                ) ?? const TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (controller.currentStepIndex > 0)
                    OutlinedButton(
                      onPressed: () => _handleStepPrevious(context, controller, step),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurface,
                        side: BorderSide(
                          color: theme.dividerColor,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Back'),
                    )
                  else
                    const SizedBox.shrink(),
                  Builder(
                    builder: (context) {
                      final semesterProvider = Provider.of<SemesterProvider>(context);
                      final isBlocked = step.isActionRequired && semesterProvider.semester == null;

                      return ElevatedButton(
                        onPressed: isBlocked ? null : () => _handleStepNext(context, controller, step),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          disabledBackgroundColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                          disabledForegroundColor: theme.colorScheme.onPrimary.withValues(alpha: 0.5),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: isBlocked ? 0 : 2,
                        ),
                        child: Text(
                          isBlocked
                              ? 'Create Semester First'
                              : (controller.currentStepIndex == controller.totalSteps - 1
                                  ? 'Finish'
                                  : 'Next ➔'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleStepNext(
    BuildContext context,
    TutorialController controller,
    TutorialStep step,
  ) {
    controller.nextStep();
  }

  void _handleStepPrevious(
    BuildContext context,
    TutorialController controller,
    TutorialStep step,
  ) {
    controller.previousStep();
  }
}

/// Custom Clipper that clips out a rounded rectangle hole from the backdrop path
class InvertedRRectClipper extends CustomClipper<Path> {
  final Rect rect;
  final BorderRadius borderRadius;

  InvertedRRectClipper({
    required this.rect,
    required this.borderRadius,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final holeRRect = RRect.fromRectAndCorners(
      rect,
      topLeft: borderRadius.topLeft,
      topRight: borderRadius.topRight,
      bottomLeft: borderRadius.bottomLeft,
      bottomRight: borderRadius.bottomRight,
    );

    final holePath = Path()..addRRect(holeRRect);

    return Path.combine(PathOperation.difference, path, holePath);
  }

  @override
  bool shouldReclip(covariant InvertedRRectClipper oldClipper) {
    return oldClipper.rect != rect || oldClipper.borderRadius != borderRadius;
  }
}
