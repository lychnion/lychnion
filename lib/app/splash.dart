import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'brand.dart';

/// The "switch on" intro from the brand canvas (board 8, option 1): the
/// light pops on, its glow opens, roof and pointer settle in, then the name.
/// Plays once over the app as it starts (about 1.4 s), the light keeps a
/// slow glow until [intro] ends, then it fades out. A tap skips it.
/// With "reduce motion" on, the still mark shows briefly instead.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.child});

  final Widget child;

  /// The intro and the glow after it, then the fade.
  static const intro = Duration(milliseconds: 3000);
  static const fade = Duration(milliseconds: 500);
  static const still = Duration(milliseconds: 600);

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with TickerProviderStateMixin {
  late final _intro = AnimationController(
    vsync: this,
    duration: SplashOverlay.intro,
  );
  late final _out = AnimationController(
    vsync: this,
    duration: SplashOverlay.fade,
  );
  bool _done = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      Future.delayed(SplashOverlay.still, _finish);
    } else {
      unawaited(_intro.forward().whenComplete(_finish));
    }
  }

  Future<void> _finish() async {
    if (!mounted || _out.isAnimating || _done) return;
    _intro.stop();
    await _out.forward();
    if (mounted) setState(() => _done = true);
  }

  @override
  void dispose() {
    _intro.dispose();
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        FadeTransition(
          opacity: ReverseAnimation(_out),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _finish,
            child: ColoredBox(
              color: Brand.night,
              child: AnimatedBuilder(
                animation: _intro,
                builder: (context, _) => _Intro(t: _intro.value),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One frame of the intro at time [t] (0..1 of [SplashOverlay.intro]).
class _Intro extends StatelessWidget {
  const _Intro({required this.t});

  final double t;

  /// 0..1 between [a] and [b] (fractions of the intro), eased.
  static double _span(
    double t,
    double a,
    double b, [
    Curve c = Curves.easeOut,
  ]) => c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final word = _span(t, 0.3, 0.467);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 132,
            child: CustomPaint(painter: _IntroPainter(t)),
          ),
          const SizedBox(height: 18),
          Opacity(
            opacity: word,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - word)),
              child: Column(
                children: [
                  const Text(
                    Brand.name,
                    style: TextStyle(
                      fontFamily: Brand.wordmarkFont,
                      fontWeight: FontWeight.w500,
                      fontSize: 34,
                      letterSpacing: -0.4,
                      color: Brand.moonlight,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    Brand.nameJa,
                    style: TextStyle(
                      fontFamily: Brand.wordmarkFontJa,
                      fontFamilyFallback: [Brand.textFont],
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: 2.2,
                      color: Brand.haze,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroPainter extends CustomPainter {
  _IntroPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    const c = Offset(32, 36);

    // Glow: opens past full size, settles, then breathes slowly (one
    // cycle in 2.4 s, as on the canvas) until the splash fades.
    final h = _Intro._span(t, 0.083, 0.25);
    final hs = _Intro._span(t, 0.25, 0.4, Curves.easeInOut);
    final b = t > 0.4 ? sin(2 * pi * (t - 0.4) * 3.0 / 2.4) : 0.0;
    final haloScale = (0.5 + 0.65 * h) - 0.15 * hs + 0.06 * b;
    final haloOpacity = 0.85 * h - 0.28 * hs + 0.15 * b;
    if (haloOpacity > 0) {
      final r = 24 * haloScale;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFFFD27A).withValues(alpha: haloOpacity),
              Brand.glow.withValues(alpha: 0.75 * haloOpacity),
              Brand.glow.withValues(alpha: 0),
            ],
            stops: const [0, 0.5, 1],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final ink = Paint()
      ..color = Brand.moonlight
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Roof: fades in, rising 5 units.
    final roof = _Intro._span(t, 0.133, 0.283);
    if (roof > 0) {
      canvas.save();
      canvas.translate(0, 5 * (1 - roof));
      canvas.drawPath(
        Path()
          ..moveTo(12, 25)
          ..lineTo(32, 10)
          ..lineTo(52, 25),
        ink
          ..strokeWidth = 5
          ..color = Brand.moonlight.withValues(alpha: roof),
      );
      canvas.restore();
    }

    // The light: a soft pop (0.2 → 1.08 → 1).
    final pop = _Intro._span(t, 0.017, 0.133);
    final settle = _Intro._span(t, 0.133, 0.2, Curves.easeInOut);
    if (pop > 0) {
      final s = 0.2 + 0.88 * pop - 0.08 * settle + 0.02 * b;
      canvas.drawCircle(
        c,
        11 * s,
        Paint()..color = Brand.glow.withValues(alpha: min(1, pop * 1.5)),
      );
    }

    // Pointer: fades in, dropping 5 units.
    final ptr = _Intro._span(t, 0.183, 0.333);
    if (ptr > 0) {
      canvas.save();
      canvas.translate(0, -5 * (1 - ptr));
      final p = Path()
        ..moveTo(26.5, 51)
        ..lineTo(37.5, 51)
        ..lineTo(32, 59)
        ..close();
      final color = Brand.moonlight.withValues(alpha: ptr);
      canvas.drawPath(p, Paint()..color = color);
      canvas.drawPath(
        p,
        ink
          ..strokeWidth = 2
          ..color = color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_IntroPainter old) => old.t != t;
}
