import 'package:flutter/material.dart';
import '../../utils/responsive_scale.dart';

class SwipeableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onSwipeRight;
  final VoidCallback onSwipeLeft;
  final Widget swipeRightBackground;
  final Widget swipeLeftBackground;
  final ResponsiveScale rs;

  const SwipeableCard({
    super.key,
    required this.child,
    required this.onSwipeRight,
    required this.onSwipeLeft,
    required this.swipeRightBackground,
    required this.swipeLeftBackground,
    required this.rs,
  });

  @override
  State<SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<SwipeableCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragOffset = 0.0;
  double _startOffset = 0.0;
  late double _maxDragDistance;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = _controller.drive(Tween<double>(begin: 0.0, end: 0.0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _controller.stop();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.primaryDelta ?? 0.0;
      _dragOffset = _dragOffset.clamp(-_maxDragDistance, _maxDragDistance);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final threshold = _maxDragDistance * 0.5;
    if (_dragOffset >= threshold) {
      widget.onSwipeRight();
    } else if (_dragOffset <= -threshold) {
      widget.onSwipeLeft();
    }

    _startOffset = _dragOffset;
    _animation = _controller.drive(
      Tween<double>(begin: _startOffset, end: 0.0).chain(
        CurveTween(curve: Curves.easeOutCubic),
      ),
    );
    
    _controller.reset();
    _controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _dragOffset = 0.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Limit swipe offset to 25% of the screen width
    _maxDragDistance = screenWidth * 0.25;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final currentOffset = _controller.isAnimating ? _animation.value : _dragOffset;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (currentOffset != 0)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.rs.scale(12)),
                  child: Stack(
                    children: [
                      if (currentOffset > 0)
                        Positioned.fill(child: widget.swipeRightBackground),
                      if (currentOffset < 0)
                        Positioned.fill(child: widget.swipeLeftBackground),
                    ],
                  ),
                ),
              ),
            GestureDetector(
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              behavior: HitTestBehavior.opaque,
              child: Transform.translate(
                offset: Offset(currentOffset, 0.0),
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}
