// Only Lychnion's packages supply the fixed official safety line
// (lychnion/lychnion#66): a publisher the user added brings guides, not
// "official" lines, and an empty trigger word never matches.
import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/download/download_store.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion_format/lychnion_format.dart';

Installed _installed(String publisher) => Installed(
  PackageRecord.fromJson({
    'format': 1,
    'id': 'jp.city.guide',
    'kind': 'package',
    'version': '2026.11.1',
    'publisher': publisher,
    'key': 'k1',
    'signed': '2026-11-20T00:00:00Z',
    'signature': 'sig',
    'files': [
      {
        'name': 'jp.city.guide.sqlite',
        'size': 1,
        'sha256': '0' * 64,
        'url': 'https://example.org/jp.city.guide.sqlite',
      },
    ],
  }),
);

void main() {
  final src = Source('s', 'Guide', 'City', '', 'CC BY 4.0', '');

  group('trigger words', () {
    Alert alert(List<List<String>> groups) =>
        Alert('a', src, 'Move to high ground now.', matchAll: {'en': groups});

    test('a normal word still matches', () {
      expect(
        alert([
          ['tsunami'],
        ]).matches('What to do in a tsunami?'),
        isTrue,
      );
    });

    test('an empty or blank word matches nothing', () {
      for (final w in ['', ' ', '　']) {
        expect(
          alert([
            [w],
          ]).matches('Where can I buy bread?'),
          isFalse,
          reason: '"$w"',
        );
      }
      // Next to a real word, only the real word counts.
      final a = alert([
        ['', 'tsunami'],
      ]);
      expect(a.matches('Where can I buy bread?'), isFalse);
      expect(a.matches('Is a tsunami coming?'), isTrue);
    });
  });

  test('a package without its safety lines keeps its guides', () {
    final core = KnowledgePackage.open('assets/packages/jp.bousai.core.sqlite');
    expect(core.alerts, isNotEmpty);
    final plain = core.withoutAlerts();
    expect(plain.alerts, isEmpty);
    expect(plain.passages.length, core.passages.length);
    expect(plain.sources, core.sources);
    expect(plain.parts.single.id, core.parts.single.id);
    // Merged with Lychnion's own, only Lychnion's lines remain.
    final both = KnowledgePackage.merge([core, plain]);
    expect(both.alerts.length, core.alerts.length);
    expect(both.passages.length, core.passages.length * 2);
  });

  test('only a built-in publisher supplies safety lines', () {
    expect(_installed('lychnion').builtInPublisher, isTrue);
    expect(_installed('city.example').builtInPublisher, isFalse);
  });

  // An added publisher's copy of a bundled id must not replace Lychnion's
  // guide and safety lines: the bundled file is used instead.
  test('a bundled id is answered from Lychnion, never from an added '
      'publisher', () {
    expect(DownloadStore.useInstalledBundled(_installed('lychnion')), isTrue);
    expect(
      DownloadStore.useInstalledBundled(_installed('city.example')),
      isFalse,
    );
    expect(DownloadStore.useInstalledBundled(null), isFalse);
  });
}
