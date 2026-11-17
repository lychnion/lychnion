import 'dart:math';

import 'package:flutter/material.dart';

import '../app/brand.dart';

/// "Thinking / loading" from the brand canvas (board 8): only the amber
/// light, breathing slowly (one cycle in 2.4 s) while something is being
/// prepared. Replaces a spinner. With "reduce motion" on it stays still.
class BreathingLight extends StatefulWidget {
  const BreathingLight({super.key, this.size = 24, this.label});

  final double size;

  /// For screen readers, e.g. "Loading".
  final String? label;

  static const period = Duration(milliseconds: 2400);

  @override
  State<BreathingLight> createState() => _BreathingLightState();
}

class _BreathingLightState extends State<BreathingLight>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: BreathingLight.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c
        ..stop()
        ..value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: widget.label,
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) =>
              CustomPaint(painter: _LightPainter(_c.value, outline: !dark)),
        ),
      ),
    );
  }
}

class _LightPainter extends CustomPainter {
  _LightPainter(this.t, {required this.outline});

  /// 0..1 through one breath.
  final double t;

  /// A Night ring around the light on light grounds (Glow alone is too
  /// faint on Paper).
  final bool outline;

  @override
  void paint(Canvas canvas, Size size) {
    // 0 at the start and end of a breath, 1 in the middle (ease in-out).
    final b = (1 - cos(2 * pi * t)) / 2;
    final c = size.center(Offset.zero);
    final unit = size.width / 64;

    final haloR = 26 * unit * (0.9 + 0.25 * b);
    final haloA = 0.38 + 0.47 * b;
    canvas.drawCircle(
      c,
      haloR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFD27A).withValues(alpha: haloA),
            Brand.glow.withValues(alpha: 0.75 * haloA),
            Brand.glow.withValues(alpha: 0),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: c, radius: haloR)),
    );

    final coreR = 13 * unit * (0.94 + 0.1 * b);
    canvas.drawCircle(c, coreR, Paint()..color = Brand.glow);
    if (outline) {
      canvas.drawCircle(
        c,
        coreR,
        Paint()
          ..color = Brand.night
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1, 2.6 * unit),
      );
    }
  }

  @override
  bool shouldRepaint(_LightPainter old) => old.t != t || old.outline != outline;
}
