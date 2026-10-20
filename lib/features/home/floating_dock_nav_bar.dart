import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AttendMateDock extends StatelessWidget {
  static const double horizontalMargin = 20.0;
  static const double dockHeight = 64.0;
  static const double minBottomPadding = 16.0;

  static double totalDockHeight(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return dockHeight + math.max(bottomPadding, minBottomPadding);
  }

  final int selectedIndex;
  final ValueChanged<int> onItemTapped;
  final Key? todayKey;
  final Key? subjectsKey;
  final Key? semesterKey;
  final Key? bunkKey;
  final Key? moreKey;
  final bool isSemesterDetailsOpen;

  const AttendMateDock({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
    this.todayKey,
    this.subjectsKey,
    this.semesterKey,
    this.bunkKey,
    this.moreKey,
    this.isSemesterDetailsOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    // Hide dock when keyboard is visible
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    if (bottomInset > 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark ||
        theme.colorScheme.brightness == Brightness.dark;

    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    // Premium translucent frosted liquid glass floating dock
    final dockBgColor = isDark
        ? const Color(0xFF141416).withValues(alpha: 0.32) // Translucent frosted obsidian
        : Colors.white.withValues(alpha: 0.42); // Translucent frosted white

    final dockBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.10);

    final selectedColor = isDark ? Colors.white : Colors.black;
    final unselectedColor = isDark
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.40);

    return RepaintBoundary(
      child: Container(
        color: Colors.transparent,
      padding: EdgeInsets.only(
        left: horizontalMargin,
        right: horizontalMargin,
        bottom: math.max(bottomPadding, minBottomPadding),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
              blurRadius: 24.0,
              spreadRadius: 0.0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36.0),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
            child: Container(
              height: 64.0,
              decoration: BoxDecoration(
                color: dockBgColor,
                borderRadius: BorderRadius.circular(36.0),
                border: Border.all(
                  color: dockBorderColor,
                  width: 0.9,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 0: Today
                  _DockIconItem(
                    key: todayKey,
                    index: 0,
                    selectedIndex: selectedIndex,
                    activeIcon: Icons.calendar_today_rounded,
                    inactiveIcon: Icons.calendar_today_outlined,
                    activeColor: selectedColor,
                    inactiveColor: unselectedColor,
                    iconSize: 23.0,
                    onTap: () => onItemTapped(0),
                  ),

                  // 1: Subjects
                  _DockIconItem(
                    key: subjectsKey,
                    index: 1,
                    selectedIndex: selectedIndex,
                    activeIcon: Icons.auto_stories_rounded,
                    inactiveIcon: Icons.auto_stories_outlined,
                    activeColor: selectedColor,
                    inactiveColor: unselectedColor,
                    iconSize: 25.0,
                    onTap: () => onItemTapped(1),
                  ),

                  // 2: Semester (High contrast central action icon)
                  _DockCenterButtonItem(
                    key: semesterKey,
                    index: 2,
                    selectedIndex: selectedIndex,
                    isDark: isDark,
                    isOpen: isSemesterDetailsOpen,
                    onTap: () => onItemTapped(2),
                  ),

                  // 3: Bunk Meter
                  _DockIconItem(
                    key: bunkKey,
                    index: 3,
                    selectedIndex: selectedIndex,
                    activeIcon: Icons.calculate_rounded,
                    inactiveIcon: Icons.calculate_outlined,
                    activeColor: selectedColor,
                    inactiveColor: unselectedColor,
                    iconSize: 26.0,
                    onTap: () => onItemTapped(3),
                  ),

                  // 4: Settings
                  _DockIconItem(
                    key: moreKey,
                    index: 4,
                    selectedIndex: selectedIndex,
                    activeIcon: Icons.settings_rounded,
                    inactiveIcon: Icons.settings_outlined,
                    activeColor: selectedColor,
                    inactiveColor: unselectedColor,
                    iconSize: 25.0,
                    onTap: () => onItemTapped(4),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  }
}

class _DockIconItem extends StatefulWidget {
  final int index;
  final int selectedIndex;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final Color activeColor;
  final Color inactiveColor;
  final double iconSize;
  final VoidCallback onTap;

  const _DockIconItem({
    super.key,
    required this.index,
    required this.selectedIndex,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.activeColor,
    required this.inactiveColor,
    required this.iconSize,
    required this.onTap,
  });

  @override
  State<_DockIconItem> createState() => _DockIconItemState();
}

class _DockIconItemState extends State<_DockIconItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.selectedIndex == widget.index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Center(
          child: AnimatedScale(
            scale: _isPressed ? 0.88 : (isSelected ? 1.05 : 1.0),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isSelected ? widget.activeIcon : widget.inactiveIcon,
                key: ValueKey('${widget.index}_$isSelected'),
                size: widget.iconSize,
                color: isSelected ? widget.activeColor : widget.inactiveColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockCenterButtonItem extends StatefulWidget {
  final int index;
  final int selectedIndex;
  final bool isDark;
  final bool isOpen;
  final VoidCallback onTap;

  const _DockCenterButtonItem({
    super.key,
    required this.index,
    required this.selectedIndex,
    required this.isDark,
    this.isOpen = false,
    required this.onTap,
  });

  @override
  State<_DockCenterButtonItem> createState() => _DockCenterButtonItemState();
}

class _DockCenterButtonItemState extends State<_DockCenterButtonItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.selectedIndex == widget.index || widget.isOpen;

    // High contrast styling:
    // In dark theme: crisp pure white circle with solid black icon
    // In light theme: sleek solid black circle with pure white icon
    final bgColor = widget.isDark ? Colors.white : Colors.black;
    final iconColor = widget.isDark ? Colors.black : Colors.white;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Center(
          child: AnimatedScale(
            scale: _isPressed ? 0.90 : (isSelected ? 1.06 : 1.0),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: Container(
              width: 48.0,
              height: 48.0,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.8,
                ),
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) => RotationTransition(
                    turns: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Icon(
                    widget.isOpen ? Icons.close_rounded : Icons.school_rounded,
                    key: ValueKey(widget.isOpen),
                    size: 24.0,
                    color: iconColor,
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

