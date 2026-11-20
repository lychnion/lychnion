import 'package:crypto/crypto.dart' as crypto;
import 'package:lychnion_format/lychnion_format.dart';

import 'node_folder.dart';

/// Checks a node folder: every record in catalog.json signed by a key of
/// [trust], every file there at its size and SHA-256. Returns the
/// problems found (empty: all good).
Future<List<String>> checkFolder(NodeFolder folder, TrustedKeys trust) async {
  final problems = <String>[];
  if (!await folder.catalogFile.exists()) {
    return ['${folder.catalogFile.path}: missing'];
  }
  final CatalogDocument doc;
  try {
    doc = CatalogDocument.parse(await folder.catalogFile.readAsString());
  } on CatalogFormatException catch (e) {
    return [
      '${folder.catalogFile.path}: '
          '${e.notJson ? 'not JSON' : 'not a format 2 catalog'}',
    ];
  }
  // Records of a successor key count when the catalog says so.
  final keys = trust.withStatements(await relevantStatements(trust, doc.keys));
  for (final raw in doc.records) {
    final r = await keys.check(raw);
    if (r == null) {
      // Only a string id is shown: a nested one would overflow the stack
      // when printed (lychnion/lychnion#78).
      final id = switch (raw) {
        {'id': final String id} => id,
        _ => null,
      };
      problems.add('${id ?? '?'}: not signed by a trusted publisher');
      continue;
    }
    for (final f in r.files) {
      final b = folder.blob(f.sha256)!;
      if (!await b.exists()) {
        problems.add('${r.id} ${r.version}: ${f.name} missing');
      } else if (await b.length() != f.size ||
          (await crypto.sha256.bind(b.openRead()).first).toString() !=
              f.sha256) {
        problems.add('${r.id} ${r.version}: ${f.name} does not match');
      }
    }
  }
  return problems;
}
