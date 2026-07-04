import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A smoothly animated, full-screen gradient backdrop.
///
/// Screens feed it an artwork-derived palette (see [ArtworkPalette]); it eases
/// between palettes whenever the colors change so track switches feel alive
/// rather than snapping. Falls back to the neutral brand gradient.
class AppBackground extends StatelessWidget {
  final List<Color> colors;
  final Duration duration;

  const AppBackground({
    super.key,
    this.colors = AppTheme.fallbackGradient,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    final palette = colors.length >= 3 ? colors : AppTheme.fallbackGradient;
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: palette,
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: const _GrainOverlay(),
    );
  }
}

/// A soft radial highlight near the top that adds depth without clutter.
class _GrainOverlay extends StatelessWidget {
  const _GrainOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.75),
          radius: 1.1,
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}
