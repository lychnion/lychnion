import '../download/publisher_label.dart' show PublisherCheck;
import '../download/publisher_list.dart' show PublisherLink;

/// What Lychnion's attestations say about the publisher that signed a source's
/// package (lychnion/lychnion#119), as an answer shows it: "via 仙台市 ·
/// checked by Lychnion", "via Aoba Club · not checked by Lychnion".
/// Labels only: it changes nothing about which packages are used.
class SourceLabel {
  const SourceLabel(this.check, {required this.name, this.titles = const {}});

  final PublisherCheck check;

  /// The publisher's name (`jp.city.sendai`).
  final String name;

  /// Its name for people: the attestation's title (`ja`, `en`) when attested,
  /// else the title it was added with (under `und`). May be empty.
  final Map<String, String> titles;

  /// Shown without a label: Lychnion's own guides.
  bool get isBuiltIn => check == PublisherCheck.builtIn;

  /// Not Lychnion's, and not attested: the answer says so.
  bool get isUnchecked =>
      check != PublisherCheck.builtIn && check != PublisherCheck.attested;

  /// Shown in red: the name has an attestation that this key does not have.
  bool get isProblem => switch (check) {
    PublisherCheck.withdrawn ||
    PublisherCheck.otherKey ||
    PublisherCheck.revoked => true,
    _ => false,
  };

  /// Its name for people in [lang], else in Japanese or English, else
  /// any, else [name].
  String titleIn(String lang) =>
      titles[lang] ??
      titles['ja'] ??
      titles['en'] ??
      (titles.isEmpty ? name : titles.values.first);

  Map<String, Object?> toWire() => {
    'check': check.name,
    'name': name,
    if (titles.isNotEmpty) 'titles': titles,
  };

  /// A label as a base sent it (or as an answer was saved). Null when it
  /// is not one: an unknown check, a name or title that is not plain.
  /// Titles are cleaned as a publisher link's are, so none can show as
  /// the app itself.
  static SourceLabel? fromWire(Object? j) {
    if (j is! Map) return null;
    final check = PublisherCheck.values
        .where((c) => c.name == j['check'])
        .firstOrNull;
    final name = j['name'];
    if (check == null || name is! String || !_name.hasMatch(name)) {
      return null;
    }
    // Only Lychnion's own guides carry its name.
    if (name == _lychnion && check != PublisherCheck.builtIn) return null;
    final titles = <String, String>{};
    if (j['titles'] case final Map<Object?, Object?> t) {
      for (final e in t.entries.take(4)) {
        final k = e.key, v = e.value;
        if (k is! String || !_lang.hasMatch(k) || v is! String) continue;
        if (shownTitle(v) case final clean?) titles[k] = clean;
      }
    }
    return SourceLabel(check, name: name, titles: titles);
  }

  /// [t] as an answer's label line may show it, or null: cleaned as a
  /// publisher link's title, and without what would read as part of the
  /// line around it (the app's name, the separator, quotes). Only ASCII
  /// and Japanese spellings of the name are caught; look-alike letters are
  /// not (see the lookalike warning when a publisher is added).
  static String? shownTitle(String? t) {
    final clean = PublisherLink.cleanTitle(t);
    if (clean == null ||
        clean.toLowerCase().contains(_lychnion) ||
        clean.contains('リクニオン') ||
        _lineMarks.any(clean.contains)) {
      return null;
    }
    return clean;
  }

  static const _lineMarks = ['·', '・', '“', '”', '"', '「', '」'];

  static final _name = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');
  static final _lang = RegExp(r'^[a-z]{2,3}$');
  static const _lychnion = 'lychnion';
}
