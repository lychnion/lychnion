import 'dart:convert';

import 'fact.dart';

/// Compact text format for facts over radio (Meshtastic, about 200 bytes per
/// message) or other small channels.
///
/// One fact: `<kind><source>|<subject>|<value>|<observed>|<ttl>`
/// - kind, source: one letter each (see [FactKind], [SourceType])
/// - subject: the site's number in the shared site list (base 36), or
///   `lat,lon` with 4 decimals for points
/// - value: one letter for shelter status (o/c/f/x), else short text
/// - observed: minutes since [epoch] (base 36); ttl: minutes until expiry
///
/// Example: `So|1v|f|8nq4|3c` = official: site 67 is full, observed at …,
/// expires 120 minutes later. Several facts are joined with `;`.
///
/// Not signed yet: Idea 5 plans signatures for official updates.
class CompactCodec {
  CompactCodec(List<String> siteIds)
    : _ids = siteIds,
      _index = {for (var i = 0; i < siteIds.length; i++) siteIds[i]: i};

  /// Sites in the same order on every device (same map area version).
  final List<String> _ids;
  final Map<String, int> _index;

  static final epoch = DateTime.utc(2026, 1, 1);

  static const _status = {
    'open': 'o',
    'crowded': 'c',
    'full': 'f',
    'closed': 'x',
  };
  static final _statusBack = {for (final e in _status.entries) e.value: e.key};

  String encode(Fact f) {
    final i = _index[f.subject];
    final subject = i != null ? i.toRadixString(36) : f.subject;
    final value = f.kind == FactKind.shelterStatus
        ? (_status[f.value] ?? f.value)
        : f.value;
    final observed = f.observedAt.toUtc().difference(epoch).inMinutes;
    final ttl = f.expiresAt.difference(f.observedAt).inMinutes;
    for (final part in [subject, value]) {
      if (part.contains('|') || part.contains(';')) {
        throw ArgumentError('field contains a separator: $part');
      }
    }
    return '${f.kind.code}${f.sourceType.code}|$subject|$value|'
        '${observed.toRadixString(36)}|${ttl.toRadixString(36)}';
  }

  Fact decode(String s) {
    final p = s.split('|');
    if (p.length != 5 || p[0].length != 2) {
      throw FormatException('not a compact fact: $s');
    }
    final kind = FactKind.fromCode(p[0][0]);
    final source = SourceType.fromCode(p[0][1]);
    final subject = p[1].contains(',')
        ? p[1]
        : _ids[int.parse(p[1], radix: 36)];
    final value = kind == FactKind.shelterStatus
        ? (_statusBack[p[2]] ?? p[2])
        : p[2];
    final observed = epoch.add(Duration(minutes: int.parse(p[3], radix: 36)));
    final ttl = Duration(minutes: int.parse(p[4], radix: 36));
    return Fact(
      kind: kind,
      subject: subject,
      value: value,
      observedAt: observed,
      expiresAt: observed.add(ttl),
      sourceType: source,
    );
  }

  /// Packs facts into messages of at most [maxBytes] (UTF-8).
  List<String> pack(Iterable<Fact> facts, {int maxBytes = 200}) {
    final out = <String>[];
    var cur = '';
    for (final f in facts) {
      final e = encode(f);
      final next = cur.isEmpty ? e : '$cur;$e';
      if (cur.isNotEmpty && _bytes(next) > maxBytes) {
        out.add(cur);
        cur = e;
      } else {
        cur = next;
      }
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  List<Fact> unpack(String message) => [
    for (final part in message.split(';'))
      if (part.isNotEmpty) decode(part),
  ];

  /// UTF-8 bytes: Japanese text (warnings) takes 3 bytes per character.
  static int _bytes(String s) => utf8.encode(s).length;
}
