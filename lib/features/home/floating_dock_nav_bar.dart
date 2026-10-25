import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FloatingDockItem {
  final Key? key;
  final IconData icon;
  final String label;

  const FloatingDockItem({
    this.key,
    required this.icon,
    required this.label,
  });
}

class FloatingDockNavBar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final List<FloatingDockItem> items;

  const FloatingDockNavBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
    required this.items,
  });

  @override
  State<FloatingDockNavBar> createState() => _FloatingDockNavBarState();
}

class _FloatingDockNavBarState extends State<FloatingDockNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late double _startPosIndex;
  late double _targetPosIndex;
  double _currentVirtualPos = 0.0;

  @override
  void initState() {
    super.initState();
    _startPosIndex = widget.selectedIndex.toDouble();
    _targetPosIndex = widget.selectedIndex.toDouble();
    _currentVirtualPos = widget.selectedIndex.toDouble();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: 1.0,
    );
  }

  @override
  void didUpdateWidget(FloatingDockNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      if (_controller.isAnimating) {
        _startPosIndex = _currentVirtualPos;
      } else {
        _startPosIndex = oldWidget.selectedIndex.toDouble();
      }
      _targetPosIndex = widget.selectedIndex.toDouble();
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hide dock when keyboard is visible to maximize screen real estate
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    if (bottomInset > 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark ||
        theme.colorScheme.brightness == Brightness.dark;
    final bottomPadding = math.max(MediaQuery.paddingOf(context).bottom, 12.0);

    // Frosted glass effect decreased by ~70%:
    // Micro blur (sigma 6.0 instead of 20.0) and ultra-minimal translucent background tint
    // Ultra-subtle frosted glass dock background colors per theme (nearly clear)
    final dockBgColor = isDark
        ? Colors.white.withValues(alpha: 0.01)
        : Colors.white.withValues(alpha: 0.015);

    final dockBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.035);

    // Translucent pill highlight styling per theme
    final pillColor = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.10);
    final pillBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.06);

    // Colors for active and inactive items
    final selectedItemColor = isDark ? Colors.white : Colors.black;
    final unselectedItemColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.42);

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          bottom: bottomPadding,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.08 : 0.02),
                blurRadius: 16.0,
                spreadRadius: 0.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28.0),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
              child: Container(
                height: 64.0,
                decoration: BoxDecoration(
                  color: dockBgColor,
                  borderRadius: BorderRadius.circular(28.0),
                  border: Border.all(
                    color: dockBorderColor,
                    width: 0.8,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const horizontalPadding = 6.0;
                    const nominalHeight = 54.0;
                    const dockHeight = 64.0;
                    final totalWidth = constraints.maxWidth;
                    final contentWidth = totalWidth - (horizontalPadding * 2);
                    final count = widget.items.isEmpty ? 1 : widget.items.length;
                    final itemWidth = contentWidth / count;
                    const pillInset = 2.0;
                    final standardWidth = math.max(0.0, itemWidth - (pillInset * 2));

                    double posForIndex(double idx) {
                      return horizontalPadding + (idx * itemWidth) + pillInset;
                    }

                    return AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final t = _controller.value;
                        final movingRight = _targetPosIndex >= _startPosIndex;
                        final distance = (_targetPosIndex - _startPosIndex).abs();

                        final double leadingProgress;
                        final double trailingProgress;

                        if (distance == 0.0 || t >= 1.0) {
                          leadingProgress = 1.0;
                          trailingProgress = 1.0;
                        } else {
                          // Liquid stretch: leading edge rushes forward like honey, trailing edge lags with viscosity
                          leadingProgress = const Interval(
                            0.0,
                            0.72,
                            curve: Curves.easeOutCubic,
                          ).transform(t);
                          trailingProgress = const Interval(
                            0.18,
                            1.0,
                            curve: Curves.easeOutCubic,
                          ).transform(t);
                        }

                        final double pillLeft;
                        final double pillRight;

                        if (movingRight) {
                          final startL = posForIndex(_startPosIndex);
                          final targetL = posForIndex(_targetPosIndex);
                          final delta = targetL - startL;
                          pillRight = startL + standardWidth + (delta * leadingProgress);
                          pillLeft = startL + (delta * trailingProgress);
                        } else {
                          final startL = posForIndex(_startPosIndex);
                          final targetL = posForIndex(_targetPosIndex);
                          final delta = startL - targetL;
                          pillLeft = startL - (delta * leadingProgress);
                          pillRight = startL + standardWidth - (delta * trailingProgress);
                        }

                        final pillWidth = math.max(standardWidth, pillRight - pillLeft);

                        // Track virtual position for fluid interrupted transitions
                        final pillCenter = pillLeft + (pillWidth / 2.0);
                        _currentVirtualPos =
                            (pillCenter - horizontalPadding - (standardWidth / 2.0)) / itemWidth;

                        // Liquid honey squash & stretch: thins out slightly while stretching horizontally
                        final stretchFactor =
                            standardWidth > 0 ? (pillWidth / standardWidth) : 1.0;
                        final heightScale =
                            (1.0 / math.sqrt(stretchFactor)).clamp(0.84, 1.0);
                        final currentHeight = nominalHeight * heightScale;
                        final verticalInset = (dockHeight - currentHeight) / 2.0;

                        return Stack(
                          children: [
                            // Liquid morphing pill highlight
                            if (widget.items.isNotEmpty)
                              Positioned(
                                key: const ValueKey('dock_sliding_pill'),
                                left: pillLeft,
                                top: verticalInset,
                                bottom: verticalInset,
                                width: pillWidth,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: pillColor,
                                    borderRadius:
                                        BorderRadius.circular(currentHeight / 2.0),
                                    border: Border.all(
                                      color: pillBorderColor,
                                      width: 0.8,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.20 : 0.08,
                                        ),
                                        blurRadius: 10.0,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // Interactive items row
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: horizontalPadding,
                              ),
                              child: Row(
                                children: List.generate(widget.items.length, (index) {
                                  final item = widget.items[index];
                                  final tabCenter =
                                      posForIndex(index.toDouble()) + (standardWidth / 2.0);

                                  // Distance from liquid pill center for smooth color and scale transition
                                  final distanceInItems =
                                      (pillCenter - tabCenter).abs() / itemWidth;
                                  final selectionProgress =
                                      (1.0 - (distanceInItems * 1.15)).clamp(0.0, 1.0);

                                  final itemColor = Color.lerp(
                                    unselectedItemColor,
                                    selectedItemColor,
                                    selectionProgress,
                                  )!;

                                  final scale = 1.0 + (0.08 * selectionProgress);

                                  return Expanded(
                                    child: KeyedSubtree(
                                      key: item.key,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(22.0),
                                          splashColor: Colors.transparent,
                                          highlightColor: Colors.transparent,
                                          onTap: () {
                                            HapticFeedback.selectionClick();
                                            widget.onItemTapped(index);
                                          },
                                          child: Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Transform.scale(
                                                  scale: scale,
                                                  child: Icon(
                                                    item.icon,
                                                    size: 21.0,
                                                    color: itemColor,
                                                  ),
                                                ),
                                                const SizedBox(height: 2.0),
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    item.label,
                                                    maxLines: 1,
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight: selectionProgress > 0.5
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                      color: itemColor,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
