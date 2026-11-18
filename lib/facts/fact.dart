/// Current facts: things that change after a disaster (a shelter is full, a
/// road is blocked), kept apart from the model and the knowledge packages.
///
/// Every fact has a time, a source and an expiry. The app shows facts as they
/// are, with their age; the model never rewrites them.
library;

enum FactKind {
  shelterStatus('S'),
  roadBlocked('R'),
  waterPoint('W'),
  warning('A');

  const FactKind(this.code);

  /// One letter for the compact radio format.
  final String code;

  static FactKind fromCode(String c) => values.firstWhere((k) => k.code == c);
}

/// Who reported the fact. Higher [trust] wins when facts disagree.
enum SourceType {
  official('o', 3),
  sensor('s', 2),
  citizen('c', 1);

  const SourceType(this.code, this.trust);
  final String code;
  final int trust;

  static SourceType fromCode(String c) => values.firstWhere((s) => s.code == c);
}

/// Status values for [FactKind.shelterStatus]. Names shown to people come
/// from the app texts (`shelterStatus`, keyed by [key]).
enum ShelterStatus {
  open('open'),
  crowded('crowded'),
  full('full'),
  closed('closed');

  const ShelterStatus(this.key);
  final String key;

  /// Full or closed: do not send people there.
  bool get avoid => this == full || this == closed;

  static ShelterStatus? fromKey(String k) {
    for (final s in values) {
      if (s.key == k) return s;
    }
    return null;
  }
}

class Fact {
  Fact({
    required this.kind,
    required this.subject,
    required this.value,
    required this.observedAt,
    required this.expiresAt,
    required this.sourceType,
    this.sourceName = '',
    this.note = '',
    this.keyId,
    this.sig,
  });

  /// Signature over [canonical] by the key [keyId] (Ed25519, base64url).
  /// Official and sensor facts need one from a trusted key to count as such.
  final String? keyId;
  final String? sig;

  /// Set by the fact store: false when an official or sensor fact has no
  /// valid signature from a trusted key. Such facts count as resident reports.
  bool verified = true;

  /// The fields a signature covers, in a fixed order.
  String get canonical => [
    kind.code,
    subject,
    value,
    observedAt.toUtc().millisecondsSinceEpoch,
    expiresAt.toUtc().millisecondsSinceEpoch,
    sourceType.code,
    sourceName,
    note,
  ].join('\u001f');

  Fact signed(String keyId, String sig) => Fact(
    kind: kind,
    subject: subject,
    value: value,
    observedAt: observedAt,
    expiresAt: expiresAt,
    sourceType: sourceType,
    sourceName: sourceName,
    note: note,
    keyId: keyId,
    sig: sig,
  );

  /// Trust used when facts disagree: an unverified official fact counts
  /// like a resident report.
  int get trust => verified ? sourceType.trust : SourceType.citizen.trust;

  final FactKind kind;

  /// What the fact is about: an evacuation site id (GSI 共通ID, e.g.
  /// `E2820400001201`) or a point `lat,lon`.
  final String subject;

  /// For shelters: a [ShelterStatus] key. Otherwise a short text.
  final String value;
  final DateTime observedAt;
  final DateTime expiresAt;
  final SourceType sourceType;
  final String sourceName;
  final String note;

  /// Value meaning "no longer true": a road reopened, a warning lifted.
  static const cleared = 'cleared';

  bool get isCleared => value == cleared;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  /// Citizen reports, and official facts without a valid signature, stay
  /// unconfirmed.
  bool get unconfirmed => sourceType == SourceType.citizen || !verified;

  ShelterStatus? get shelterStatus =>
      kind == FactKind.shelterStatus ? ShelterStatus.fromKey(value) : null;

  /// Facts about the same thing compete; other facts do not.
  String get topic => '${kind.code}|$subject';

  Map<String, Object?> toJson() => {
    'kind': kind.code,
    'subject': subject,
    'value': value,
    'observed_at': observedAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'source_type': sourceType.code,
    'source_name': sourceName,
    if (note.isNotEmpty) 'note': note,
    'key_id': ?keyId,
    'sig': ?sig,
  };

  factory Fact.fromJson(Map<String, dynamic> j) => Fact(
    kind: FactKind.fromCode(j['kind'] as String),
    subject: j['subject'] as String,
    value: j['value'] as String,
    observedAt: DateTime.parse(j['observed_at'] as String),
    expiresAt: DateTime.parse(j['expires_at'] as String),
    sourceType: SourceType.fromCode(j['source_type'] as String),
    sourceName: j['source_name'] as String? ?? '',
    note: j['note'] as String? ?? '',
    keyId: j['key_id'] as String?,
    sig: j['sig'] as String?,
  );
}
