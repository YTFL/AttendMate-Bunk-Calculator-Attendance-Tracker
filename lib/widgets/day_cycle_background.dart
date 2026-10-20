import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/settings/ambient_theme_provider.dart';

/// Phase of the day cycle
enum DayCyclePhase {
  morning,   // 5:00 AM - 11:59 AM (Yellow / Amber)
  afternoon, // 12:00 PM - 5:59 PM (Orange / Sunset)
  night,     // 6:00 PM - 4:59 AM (Dark Blue / Sapphire)
}

/// An ambient background widget that renders a subtle, minimalist atmospheric
/// gradient from the bottom depicting the current cycle of the day:
/// - Golden dawn Yellow (Morning: 5am - 12pm)
/// - Warm radiant Orange (Afternoon: 12pm - 6pm)
/// - Deep midnight sapphire Dark Blue (Night: 6pm - 5am)
/// - Clean True-Black AMOLED UI (Off)
///
/// Supports manual locks (morning, afternoon, night) or clean AMOLED pitch black
/// via AmbientThemeProvider.
class DayCycleBackground extends StatefulWidget {
  final Widget child;
  final bool showGradient;

  const DayCycleBackground({
    super.key,
    required this.child,
    this.showGradient = true,
  });

  @override
  State<DayCycleBackground> createState() => _DayCycleBackgroundState();
}

class _DayCycleBackgroundState extends State<DayCycleBackground>
    with WidgetsBindingObserver {
  late DayCyclePhase _dynamicPhase;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dynamicPhase = _calculatePhase();
    // Check every 10 seconds so transitions happen live as time elapses
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      final newPhase = _calculatePhase();
      if (newPhase != _dynamicPhase && mounted) {
        setState(() {
          _dynamicPhase = newPhase;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When returning from device/emulator settings, immediately update phase
    if (state == AppLifecycleState.resumed && mounted) {
      final newPhase = _calculatePhase();
      if (newPhase != _dynamicPhase) {
        setState(() {
          _dynamicPhase = newPhase;
        });
      }
    }
  }

  DayCyclePhase _calculatePhase() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) {
      return DayCyclePhase.morning;
    } else if (hour >= 12 && hour < 18) {
      return DayCyclePhase.afternoon;
    } else {
      return DayCyclePhase.night;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ambientProvider = Provider.of<AmbientThemeProvider>(context);
    final isAmoled = ambientProvider.mode == AmbientThemeMode.amoled;

    // In AMOLED mode, or if gradient is turned off, render clean pure black canvas
    if (!widget.showGradient || isAmoled) {
      return Container(
        color: isDark ? const Color(0xFF000000) : const Color(0xFFF8F8FA),
        child: widget.child,
      );
    }

    // Determine the active phase based on provider mode
    final DayCyclePhase activePhase;
    switch (ambientProvider.mode) {
      case AmbientThemeMode.dynamicCycle:
        activePhase = _dynamicPhase;
        break;
      case AmbientThemeMode.morning:
        activePhase = DayCyclePhase.morning;
        break;
      case AmbientThemeMode.afternoon:
        activePhase = DayCyclePhase.afternoon;
        break;
      case AmbientThemeMode.night:
        activePhase = DayCyclePhase.night;
        break;
      case AmbientThemeMode.amoled:
        activePhase = DayCyclePhase.night; // fallback (handled above)
        break;
    }

    // Determine colors based on active day cycle phase
    final List<Color> gradientColors;
    switch (activePhase) {
      case DayCyclePhase.morning:
        // Vibrant Golden Dawn / Amber Yellow
        gradientColors = isDark
            ? [
                const Color(0xFFF59E0B).withValues(alpha: 0.02),
                const Color(0xFFFBBF24).withValues(alpha: 0.06),
                const Color(0xFFF59E0B).withValues(alpha: 0.16),
                const Color(0xFFF59E0B).withValues(alpha: 0.35),
              ]
            : [
                const Color(0xFFFEF3C7).withValues(alpha: 0.15),
                const Color(0xFFFEF3C7).withValues(alpha: 0.35),
                const Color(0xFFFDE68A).withValues(alpha: 0.55),
                const Color(0xFFFDE68A).withValues(alpha: 0.75),
              ];
      case DayCyclePhase.afternoon:
        // Warm Radiant Sunset / Midday Orange
        gradientColors = isDark
            ? [
                const Color(0xFFEA580C).withValues(alpha: 0.02),
                const Color(0xFFFB923C).withValues(alpha: 0.07),
                const Color(0xFFEA580C).withValues(alpha: 0.18),
                const Color(0xFFEA580C).withValues(alpha: 0.36),
              ]
            : [
                const Color(0xFFFFEDD5).withValues(alpha: 0.15),
                const Color(0xFFFFEDD5).withValues(alpha: 0.35),
                const Color(0xFFFED7AA).withValues(alpha: 0.55),
                const Color(0xFFFED7AA).withValues(alpha: 0.75),
              ];
      case DayCyclePhase.night:
        // Deep Midnight Twilight Sapphire Dark Blue
        gradientColors = isDark
            ? [
                const Color(0xFF1E3A8A).withValues(alpha: 0.03),
                const Color(0xFF1E3A8A).withValues(alpha: 0.08),
                const Color(0xFF1E3A8A).withValues(alpha: 0.22),
                const Color(0xFF1E1B4B).withValues(alpha: 0.48),
              ]
            : [
                const Color(0xFFE0E7FF).withValues(alpha: 0.15),
                const Color(0xFFE0E7FF).withValues(alpha: 0.32),
                const Color(0xFFC7D2FE).withValues(alpha: 0.50),
                const Color(0xFFC7D2FE).withValues(alpha: 0.70),
              ];
    }

    return Stack(
      children: [
        // Base solid background: deep pitch-black in dark mode for maximum contrast
        Positioned.fill(
          child: Container(
            color: isDark ? const Color(0xFF060608) : const Color(0xFFF8F8FA),
          ),
        ),

        // Animated Day-Cycle Atmospheric Gradient washing smoothly across the canvas
        Positioned.fill(
          child: IgnorePointer(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              key: ValueKey(activePhase),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeInOut,
              builder: (context, animValue, child) {
                return Opacity(
                  opacity: animValue,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.35, 0.68, 1.0],
                        colors: gradientColors,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // Child content
        Positioned.fill(
          child: widget.child,
        ),
      ],
    );
  }
}
