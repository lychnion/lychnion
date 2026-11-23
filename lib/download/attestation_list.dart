import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lychnion_format/lychnion_format.dart';

import '../util/versioned_file.dart';

/// Lychnion's attestations for official publishers (lychnion/lychnion#119),
/// learned from catalogs, sticks and bases, and passed on with them
/// (docs/distribution.md, "Whom to trust: attestations").
///
/// Labels only: nothing here adds a publisher or changes which keys are
/// trusted. Kept in `attestations.json` as they came, apart from
/// publishers.json (an older build reading that file would set a newer
/// format aside, and with it the user's publishers). Checked again with
/// the device's current keys whenever the file is read, and left out of
/// use when their signer is no longer trusted for Lychnion ([recheck]).
class AttestationList extends ChangeNotifier {
  AttestationList(this.file, {this.max = Attestation.maxPerSource});

  final File file;

  /// At most this many are kept ([Attestation.capped]: what decides for each
  /// publisher first). As many as one catalog can pass on: more could
  /// never all be passed on anyway.
  final int max;

  /// Format of attestations.json (see versioned_file.dart).
  static const format = 1;

  final _attestations = <Attestation>[];

  /// The ids of [_attestations] ([Attestation.id]).
  final _ids = <String>{};

  /// Ids of valid attestations [learn] did not keep (over [max]): catalogs
  /// that carry them need not check them again in this run. At most
  /// [_maxDropped], then started anew.
  final _dropped = <String>{};
  static const _maxDropped = 4 * Attestation.maxPerSource;

  List<Attestation> get attestations => List.unmodifiable(_attestations);

  /// [attestations] whose signer [trust] has for Lychnion: what is passed on
  /// and shown, also between a revocation and the next [recheck].
  List<Attestation> attestationsFor(TrustedKeys trust) => [
    for (final v in _attestations)
      if (_signedFor(v, trust)) v,
  ];

  /// [Attestation.id]s a catalog need not check again: those kept here, and
  /// valid ones [learn] did not keep.
  Set<String> get ids => Set.unmodifiable({..._ids, ..._dropped});

  /// Where [publisher]'s [key] stands (see [attestationFor]); [statements]: the
  /// key statements the device keeps.
  AttestationResult statusOf(
    String publisher,
    String key,
    Iterable<KeyStatement> statements,
    TrustedKeys trust,
  ) => attestationFor(publisher, key, attestationsFor(trust), statements);

  /// Reads attestations.json and checks every attestation again with [trust]: a file
  /// changed by hand proves nothing. Unreadable or newer: a copy is kept
  /// (versioned_file.dart) and the list is empty.
  Future<void> load(TrustedKeys trust) async {
    final json = await readVersioned(file, format, (json, _) => json! as Map);
    _set(await Attestation.checkAll(json?['attestations'], trust, max: max));
    notifyListeners();
  }

  /// Keeps those of [learned] whose signer the device trusts for
  /// Lychnion ([trust], asked again after the save: a revocation may land
  /// meanwhile), and saves the list. Their signatures were checked when
  /// they were read (a [Attestation] is only made by a check). At most [max]
  /// are kept, chosen as [Attestation.capped] chooses them. Returns true when
  /// the list changed. Throws the save's error (then nothing changed).
  Future<bool> learn(
    Iterable<Attestation> learned,
    TrustedKeys Function() trust,
  ) => _serial(() async {
    final now = trust();
    final seen = {..._ids};
    final fresh = [
      for (final v in learned)
        if (_signedFor(v, now) && seen.add(v.id)) v,
    ];
    if (fresh.isEmpty) return false;
    final next = Attestation.capped([..._attestations, ...fresh], max);
    final kept = next.toSet();
    if (_dropped.length > _maxDropped) _dropped.clear();
    _dropped.addAll([
      for (final v in fresh)
        if (!kept.contains(v)) v.id,
    ]);
    if (next.length == _attestations.length &&
        next.every(_attestations.contains)) {
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

  /// Leaves out the attestations whose signer [trust] no longer has for
  /// Lychnion (a revoked key: its attestations lapse). Not saved: the file is
  /// checked again when it is read, and the next [learn] writes the list
  /// without them.
  void recheck(TrustedKeys trust) {
    final kept = [
      for (final v in _attestations)
        if (_signedFor(v, trust)) v,
    ];
    if (kept.length == _attestations.length) return;
    _set(kept);
    notifyListeners();
  }

  static bool _signedFor(Attestation v, TrustedKeys trust) =>
      trust.keysOf(attesterPublisher).contains(v.signer);

  void _set(List<Attestation> list) {
    _attestations
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

  Future<void> _save(List<Attestation> list) async {
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
        'attestations': [for (final v in list) v.json],
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}
