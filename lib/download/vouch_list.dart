import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lychnion_format/lychnion_format.dart';

import '../util/versioned_file.dart';

/// Lychnion's vouches for official publishers (lychnion/lychnion#119),
/// learned from catalogs, sticks and bases, and passed on with them
/// (docs/distribution.md, "Whom to trust: vouches").
///
/// Labels only: nothing here adds a publisher or changes which keys are
/// trusted. Kept in `vouches.json` as they came, apart from
/// publishers.json (an older build reading that file would set a newer
/// format aside, and with it the user's publishers). Checked again with
/// the device's current keys whenever the file is read, and left out of
/// use when their signer is no longer trusted for Lychnion ([recheck]).
class VouchList extends ChangeNotifier {
  VouchList(this.file, {this.max = Vouch.maxPerSource});

  final File file;

  /// At most this many are kept ([Vouch.capped]: what decides for each
  /// publisher first). As many as one catalog can pass on: more could
  /// never all be passed on anyway.
  final int max;

  /// Format of vouches.json (see versioned_file.dart).
  static const format = 1;

  final _vouches = <Vouch>[];

  /// The ids of [_vouches] ([Vouch.id]).
  final _ids = <String>{};

  /// Ids of valid vouches [learn] did not keep (over [max]): catalogs
  /// that carry them need not check them again in this run. At most
  /// [_maxDropped], then started anew.
  final _dropped = <String>{};
  static const _maxDropped = 4 * Vouch.maxPerSource;

  List<Vouch> get vouches => List.unmodifiable(_vouches);

  /// [vouches] whose signer [trust] has for Lychnion: what is passed on
  /// and shown, also between a revocation and the next [recheck].
  List<Vouch> vouchesFor(TrustedKeys trust) => [
    for (final v in _vouches)
      if (_signedFor(v, trust)) v,
  ];

  /// [Vouch.id]s a catalog need not check again: those kept here, and
  /// valid ones [learn] did not keep.
  Set<String> get ids => Set.unmodifiable({..._ids, ..._dropped});

  /// Where [publisher]'s [key] stands (see [vouchFor]); [statements]: the
  /// key statements the device keeps.
  VouchResult statusOf(
    String publisher,
    String key,
    Iterable<KeyStatement> statements,
    TrustedKeys trust,
  ) => vouchFor(publisher, key, vouchesFor(trust), statements);

  /// Reads vouches.json and checks every vouch again with [trust]: a file
  /// changed by hand proves nothing. Unreadable or newer: a copy is kept
  /// (versioned_file.dart) and the list is empty.
  Future<void> load(TrustedKeys trust) async {
    final json = await readVersioned(file, format, (json, _) => json! as Map);
    _set(await Vouch.checkAll(json?['vouches'], trust, max: max));
    notifyListeners();
  }

  /// Keeps those of [learned] whose signer the device trusts for
  /// Lychnion ([trust], asked again after the save: a revocation may land
  /// meanwhile), and saves the list. Their signatures were checked when
  /// they were read (a [Vouch] is only made by a check). At most [max]
  /// are kept, chosen as [Vouch.capped] chooses them. Returns true when
  /// the list changed. Throws the save's error (then nothing changed).
  Future<bool> learn(Iterable<Vouch> learned, TrustedKeys Function() trust) =>
      _serial(() async {
        final now = trust();
        final seen = {..._ids};
        final fresh = [
          for (final v in learned)
            if (_signedFor(v, now) && seen.add(v.id)) v,
        ];
        if (fresh.isEmpty) return false;
        final next = Vouch.capped([..._vouches, ...fresh], max);
        final kept = next.toSet();
        if (_dropped.length > _maxDropped) _dropped.clear();
        _dropped.addAll([
          for (final v in fresh)
            if (!kept.contains(v)) v.id,
        ]);
        if (next.length == _vouches.length && next.every(_vouches.contains)) {
          return false;
        }
        await _save(next);
        // Those a revocation made lapse during the save stay out of use (the
        // file is checked again when read).
        final after = trust();
        _set([
          for (final v in next)
            if (_signedFor(v, after)) v,
        ]);
        notifyListeners();
        return true;
      });

  /// Leaves out the vouches whose signer [trust] no longer has for
  /// Lychnion (a revoked key: its vouches lapse). Not saved: the file is
  /// checked again when it is read, and the next [learn] writes the list
  /// without them.
  void recheck(TrustedKeys trust) {
    final kept = [
      for (final v in _vouches)
        if (_signedFor(v, trust)) v,
    ];
    if (kept.length == _vouches.length) return;
    _set(kept);
    notifyListeners();
  }

  static bool _signedFor(Vouch v, TrustedKeys trust) =>
      trust.keysOf(voucherPublisher).contains(v.signer);

  void _set(List<Vouch> list) {
    _vouches
      ..clear()
      ..addAll(list);
    _ids
      ..clear()
      ..addAll(list.map((v) => v.id));
  }

  /// One learn after another: each saves the list as the one before left
  /// it.
  Future<void> _last = Future.value();

  Future<T> _serial<T>(Future<T> Function() f) {
    final run = _last.then((_) => f());
    _last = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _save(List<Vouch> list) async {
    if (!mayReplace(file)) {
      throw FileSystemException('kept as it is', file.path);
    }
    await file.parent.create(recursive: true);
    // Written next to the file, then renamed: a cut write leaves the old
    // list.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'format': format,
        'vouches': [for (final v in list) v.json],
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}
