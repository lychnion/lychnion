// Map texts shown to people: hazard names, depths, distances. The domain
// classes (Hazard, Depth, SiteDistance) carry keys and numbers only; the
// words come from the app texts (lib/l10n/app_<lang>.arb).

import '../l10n/app_localizations.dart';
import 'evac_sites.dart';
import 'route_graph.dart';

/// "Tsunami" / 「津波」.
String hazardName(AppLocalizations l, Hazard h) => l.hazardName(h.name);

/// The hazard inside a sentence: "tsunami" / 「津波」.
String hazardInSentence(AppLocalizations l, Hazard h) =>
    l.hazardInSentence(h.name);

/// 「1〜2 m」 / "1–2 m", 「0.3 m未満」, 「5 m以上」.
String depthLabel(AppLocalizations l, Depth d) {
  if (d.hi >= depthBounds.length) return l.depthOrMore(depthMetres(d.lo));
  final hi = depthMetres(d.hi);
  if (d.lo == 0) return l.depthUnder(hi);
  return l.depthRange(depthMetres(d.lo), hi);
}

/// Legend entry for colour [lo]: 「0.3 m未満」, then 「1 m〜」 / "from 1 m".
String depthFromLabel(AppLocalizations l, int lo) =>
    lo == 0 ? l.depthLegendUnder : l.depthLegendFrom(depthMetres(lo));

/// 8-point compass direction: "N" / 「北」.
String siteDirection(AppLocalizations l, SiteDistance n) =>
    l.compassPoint(n.compassPoint);

/// "海抜 5 m" for the ground near the site, and how low the way goes when
/// it dips [SiteDistance.minDip] or more below the start. Empty without
/// heights.
String siteHeightLabel(AppLocalizations l, SiteDistance n) {
  final r = n.route, h = r?.endHeight;
  if (r == null || h == null) return '';
  return [
    l.siteHeight(SiteDistance.formatHeight(h)),
    if (r.endDepth case final d?) l.siteFlooding(depthLabel(l, d)),
    if (r.dip >= SiteDistance.minDip && r.lowest != null)
      l.siteDip(SiteDistance.formatHeight(r.lowest!)),
  ].join(' · ');
}

/// "850 m walk · about 14 min", or the straight line and direction.
String siteLabel(AppLocalizations l, SiteDistance n) {
  final w = n.walk;
  if (w != null) return l.siteWalk(formatDistance(w), '${n.minutes}');
  return l.siteStraight(formatDistance(n.meters), siteDirection(l, n));
}

/// "850 m", "1.2 km".
String formatDistance(double meters) => meters < 1000
    ? '${meters.round()} m'
    : '${(meters / 1000).toStringAsFixed(1)} km';
