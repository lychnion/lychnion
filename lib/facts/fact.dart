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

/// Status values for [FactKind.shelterStatus].
enum ShelterStatus {
  open('open', '開設', 'open'),
  crowded('crowded', '混雑', 'crowded'),
  full('full', '満員', 'full'),
  closed('closed', '閉鎖', 'closed');

  const ShelterStatus(this.key, this.ja, this.en);
  final String key, ja, en;

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
  });

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

  /// Citizen reports stay unconfirmed until someone checks them.
  bool get unconfirmed => sourceType == SourceType.citizen;

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
  );

  /// "2時間前" / "2 h ago".
  String age(DateTime now, {required bool en}) {
    final d = now.difference(observedAt);
    if (d.inMinutes < 1) return en ? 'just now' : 'たった今';
    if (d.inMinutes < 60) {
      return en ? '${d.inMinutes} min ago' : '${d.inMinutes}分前';
    }
    if (d.inHours < 48) return en ? '${d.inHours} h ago' : '${d.inHours}時間前';
    return en ? '${d.inDays} days ago' : '${d.inDays}日前';
  }

  /// "市・公式", "センサー", "住民の報告・未確認".
  String sourceLabel({required bool en}) {
    final type = switch (sourceType) {
      SourceType.official => en ? 'official' : '公式',
      SourceType.sensor => en ? 'sensor' : 'センサー',
      SourceType.citizen => en ? 'resident report, unconfirmed' : '住民の報告・未確認',
    };
    return sourceName.isEmpty ? type : '$sourceName · $type';
  }
}
