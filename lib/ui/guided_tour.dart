import 'dart:async';

import 'package:flutter/material.dart';

import '../app/brand.dart';
import '../app/lang.dart';
import 'announce.dart';

/// The parts of the screen the guided tour points at (lychnion#7). The
/// widgets carry these keys; a part that is not on screen (no map area,
/// no status line) is left out of the tour.
class TourKeys {
  final status = GlobalKey(debugLabel: 'tour-status');
  final site = GlobalKey(debugLabel: 'tour-site');
  final packages = GlobalKey(debugLabel: 'tour-packages');
  final bar = GlobalKey(debugLabel: 'tour-bar');
  final ask = GlobalKey(debugLabel: 'tour-ask');
  final map = GlobalKey(debugLabel: 'tour-map');
  final menu = GlobalKey(debugLabel: 'tour-menu');
}

/// One stop: the part to show and what to say about it.
class TourStop {
  const TourStop(this.key, this.title, this.text);
  final GlobalKey key;
  final String title, text;
}

/// The stops in order, with the texts in the user's language.
List<TourStop> tourStops(BuildContext context, TourKeys k) {
  final l = context.l10n;
  return [
    TourStop(k.status, l.tourStatus, l.tourStatusText),
    TourStop(k.site, l.tourSite, l.tourSiteText),
    TourStop(k.packages, l.tourPackages, l.tourPackagesText),
    TourStop(k.bar, l.tourBar, l.tourBarText),
    TourStop(k.ask, l.tourAsk, l.tourAskText),
    TourStop(k.map, l.tourMap, l.tourMapText),
    TourStop(k.menu, l.tourMenu, l.tourMenuText),
  ];
}

/// Shows the tour over the whole app (bottom bar included). Stops whose
/// part is not on screen are skipped; nothing is shown when none is.
/// [onEnd] runs once when the tour is finished or skipped.
void showGuidedTour(
  BuildContext context,
  List<TourStop> stops, {
  VoidCallback? onEnd,
}) {
  final shown = [
    for (final s in stops)
      if (_rectOf(s.key) != null) s,
  ];
  if (shown.isEmpty) return;
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Tour(
      stops: shown,
      onEnd: () {
        entry.remove();
        onEnd?.call();
      },
    ),
  );
  overlay.insert(entry);
}

Rect? _rectOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _Tour extends StatefulWidget {
  const _Tour({required this.stops, required this.onEnd});
  final List<TourStop> stops;
  final VoidCallback onEnd;

  @override
  State<_Tour> createState() => _TourState();
}

class _TourState extends State<_Tour> {
  int _i = 0;

  void _go(int i) {
    if (i >= widget.stops.length) return widget.onEnd();
    // Bring the part into view first (Home scrolls).
    final ctx = widget.stops[i].key.currentContext;
    if (ctx != null) {
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 250),
        ).then((_) {
          if (mounted) setState(() {});
        }),
      );
    }
    setState(() => _i = i);
    // Screen readers: the card changed, though focus may not move.
    final stop = widget.stops[i];
    announce(context, '${stop.title}. ${stop.text}');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go(0));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final stop = widget.stops[_i];
    final size = MediaQuery.sizeOf(context);
    // Kept inside the screen, so the ring of an edge part stays visible.
    final hole = (_rectOf(stop.key) ?? Rect.zero)
        .inflate(6)
        .intersect((Offset.zero & size).deflate(4));
    final last = _i == widget.stops.length - 1;
    // The card goes where there is more room: below or above the part.
    final below = hole.center.dy < size.height / 2;
    // With large text the card may not fit next to the part: then it
    // takes up to half the screen at the far edge and scrolls.
    final room = below ? size.height - hole.bottom - 32 : hole.top - 32;
    final fits = room >= 240;
    final maxHeight = fits ? room : size.height / 2;
    // Screen readers reach only the card, not the app behind the dim.
    return BlockSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Taps outside the card do nothing (no accidental actions).
            Positioned.fill(
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: CustomPaint(painter: _Dim(hole)),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: below
                  ? (fits ? hole.bottom + 16 : null)
                  : (fits ? null : 16),
              bottom: below
                  ? (fits ? null : 16)
                  : (fits ? size.height - hole.top + 16 : null),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Semantics(
                  scopesRoute: true,
                  explicitChildNodes: true,
                  child: Card(
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 8, 12, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l.tourStep(_i + 1, widget.stops.length),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.tertiary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: widget.onEnd,
                                child: Text(l.tourSkip),
                              ),
                            ],
                          ),
                          Text(stop.title, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 6),
                          Text(stop.text, style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 12),
                          // Wraps at large text instead of running off.
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (_i > 0)
                                OutlinedButton(
                                  onPressed: () => _go(_i - 1),
                                  child: Text(l.tourBack),
                                ),
                              FilledButton(
                                onPressed: () => _go(_i + 1),
                                child: Text(last ? l.tourDone : l.tourNext),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims everything but [hole], and rings the hole in Glow.
class _Dim extends CustomPainter {
  _Dim(this.hole);
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(hole, const Radius.circular(18));
    final shade = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(r),
    );
    canvas.drawPath(shade, Paint()..color = const Color(0xB816233F));
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Brand.glow,
    );
  }

  @override
  bool shouldRepaint(_Dim old) => old.hole != hole;
}
