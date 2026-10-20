import 'package:flutter/material.dart';
import '../../utils/responsive_scale.dart';

typedef SwipeableCardBuilder = Widget Function(BuildContext context, double dragOffset);

class SwipeableCard extends StatefulWidget {
  final Widget? child;
  final SwipeableCardBuilder? childBuilder;
  final VoidCallback onSwipeRight;
  final VoidCallback onSwipeLeft;
  final Widget swipeRightBackground;
  final Widget swipeLeftBackground;
  final ResponsiveScale rs;
  final BorderRadius? borderRadius;

  const SwipeableCard({
    super.key,
    this.child,
    this.childBuilder,
    required this.onSwipeRight,
    required this.onSwipeLeft,
    required this.swipeRightBackground,
    required this.swipeLeftBackground,
    required this.rs,
    this.borderRadius,
  }) : assert(child != null || childBuilder != null, 'Either child or childBuilder must be provided');

  @override
  State<SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<SwipeableCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragOffset = 0.0;
  double _startOffset = 0.0;
  late double _maxDragDistance;
  Widget? _animatingBackground;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _animation = _controller.drive(Tween<double>(begin: 0.0, end: 0.0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_controller.isAnimating) {
      _dragOffset = _animation.value;
      _controller.stop();
    } else {
      _dragOffset = 0.0;
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0.0;
    setState(() {
      final raw = _dragOffset + delta;
      final absRaw = raw.abs();
      if (absRaw > _maxDragDistance) {
        final over = absRaw - _maxDragDistance;
        final dampened = _maxDragDistance + (over * 0.25);
        _dragOffset = (raw >= 0 ? 1 : -1) * dampened.clamp(0.0, _maxDragDistance * 1.35);
      } else {
        _dragOffset = raw;
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    // Capture the active background BEFORE parent rebuilds
    Widget? activeBackground;
    if (_dragOffset > 0) {
      activeBackground = widget.swipeRightBackground;
    } else if (_dragOffset < 0) {
      activeBackground = widget.swipeLeftBackground;
    }

    final vx = details.velocity.pixelsPerSecond.dx;
    final threshold = _maxDragDistance * 0.45;
    if (_dragOffset >= threshold || (vx > 350 && _dragOffset > 20)) {
      widget.onSwipeRight();
    } else if (_dragOffset <= -threshold || (vx < -350 && _dragOffset < -20)) {
      widget.onSwipeLeft();
    }

    _startOffset = _dragOffset;
    _animatingBackground = activeBackground;

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
          _animatingBackground = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Limit swipe offset to 25% of the screen width
    _maxDragDistance = screenWidth * 0.25;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, staticChild) {
          final currentOffset = _controller.isAnimating ? _animation.value : _dragOffset;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (currentOffset != 0)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: widget.borderRadius ?? BorderRadius.circular(widget.rs.scale(14)),
                    child: Stack(
                      children: [
                        if (_controller.isAnimating && _animatingBackground != null)
                          Positioned.fill(child: _animatingBackground!)
                        else ...[
                          if (currentOffset > 0)
                            Positioned.fill(child: widget.swipeRightBackground),
                          if (currentOffset < 0)
                            Positioned.fill(child: widget.swipeLeftBackground),
                        ],
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
                  child: widget.childBuilder != null
                      ? widget.childBuilder!(context, currentOffset)
                      : staticChild!,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
