import 'dart:convert';

import 'package:lychnion_format/lychnion_format.dart';

import '../knowledge/source_label.dart';
import 'download_store.dart';

/// What the app says about a publisher, from Lychnion's attestations
/// (lychnion/lychnion#119, docs/attestations.md). Labels only: nothing here
/// adds a publisher or changes which keys are trusted.
enum PublisherCheck {
  /// Built into the app (Lychnion).
  builtIn,

  /// Lychnion attests this key under this name.
  attested,

  /// No attestation for the name: added by the user, not checked by Lychnion.
  notChecked,

  /// Lychnion took its attestation for the name back.
  withdrawn,

  /// The name has an attestation, but for another key.
  otherKey,

  /// The publisher revoked this key itself.
  revoked,
}

/// A publisher's [check], and the attestation that decided it.
class PublisherLabel {
  const PublisherLabel(this.check, [this.attestation]);

  final PublisherCheck check;

  /// The deciding attestation (null for [PublisherCheck.builtIn] and
  /// [PublisherCheck.notChecked]).
  final Attestation? attestation;

  /// Shown in red: the name has an attestation that this key does not have.
  bool get isProblem => switch (check) {
    PublisherCheck.withdrawn ||
    PublisherCheck.otherKey ||
    PublisherCheck.revoked => true,
    _ => false,
  };

  /// The name to show: the one Lychnion checked (the attestation's title in
  /// [lang], else in the other language) when attested, else [fallback]
  /// (the link's own title or name).
  String titleIn(String lang, String fallback) {
    final v = attestation;
    if (check != PublisherCheck.attested || v == null) return fallback;
    final t = v.title;
    return t[lang] ?? t['ja'] ?? t['en'] ?? fallback;
  }
}

extension PublisherLabels on DownloadStore {
  /// Where publisher [name] with [key] stands with the attestations this device
  /// keeps, after the key statements it keeps.
  PublisherLabel labelOf(String name, String key) {
    if (publishers.builtIn.known.contains(name)) {
      return const PublisherLabel(PublisherCheck.builtIn);
    }
    final r = attestations.statusOf(name, key, publishers.statements, trust);
    return PublisherLabel(switch (r.status) {
      AttestationStatus.attested => PublisherCheck.attested,
      AttestationStatus.withdrawn => PublisherCheck.withdrawn,
      AttestationStatus.otherKey => PublisherCheck.otherKey,
      AttestationStatus.revoked => PublisherCheck.revoked,
      AttestationStatus.none => PublisherCheck.notChecked,
    }, r.attestation);
  }

  /// The label of the publisher that signed [r] (see [labelOfKeyId]).
  PublisherLabel? labelOfRecord(PackageRecord r) =>
      labelOfKeyId(r.publisher, r.keyId);

  /// The label of publisher [name] whose key has the short id [keyId]
  /// ([recordKeyIdOf]: records name only that): the label is for the key
  /// trusted here with that id. Null when no trusted key has it (a key
  /// revoked meanwhile, say).
  PublisherLabel? labelOfKeyId(String name, String keyId) {
    if (publishers.builtIn.known.contains(name)) {
      return const PublisherLabel(PublisherCheck.builtIn);
    }
    for (final k in trust.keysOf(name)) {
      final List<int> bytes;
      try {
        bytes = base64Url.decode(base64Url.normalize(k));
      } on FormatException {
        continue;
      }
      if (bytes.length == 32 && recordKeyIdOf(bytes) == keyId) {
        return labelOf(name, k);
      }
    }
    return null;
  }

  /// The label a source shows for the package [signer] signed with the key
  /// [keyId] (see `Source.label`): the name Lychnion checked when attested,
  /// else the title the publisher was added with. Null only without a
  /// signer (the app's help). A key no longer trusted here (revoked, or
  /// its publisher removed) is [PublisherCheck.revoked]: never no label,
  /// which would look like Lychnion's own guides.
  SourceLabel? sourceLabelOf(String? signer, String? keyId) {
    if (signer == null) return null;
    if (publishers.builtIn.known.contains(signer)) {
      return SourceLabel(PublisherCheck.builtIn, name: signer);
    }
    final added = publishers.added.where((p) => p.name == signer).firstOrNull;
    final label = keyId == null ? null : labelOfKeyId(signer, keyId);
    if (label == null) {
      return SourceLabel(
        PublisherCheck.revoked,
        name: signer,
        titles: {'und': ?SourceLabel.shownTitle(added?.title)},
      );
    }
    return SourceLabel(
      label.check,
      name: signer,
      titles: label.check == PublisherCheck.attested
          ? label.attestation!.title
          : {'und': ?SourceLabel.shownTitle(added?.title)},
    );
  }
}
