import 'dart:convert';

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
  final Object? j;
  try {
    j = jsonDecode(await folder.catalogFile.readAsString());
  } on FormatException {
    return ['${folder.catalogFile.path}: not JSON'];
  }
  if (j is! Map || j['format'] != 2 || j['records'] is! List) {
    return ['${folder.catalogFile.path}: not a format 2 catalog'];
  }
  for (final raw in j['records'] as List) {
    final r = await trust.check(raw);
    if (r == null) {
      final id = raw is Map ? raw['id'] : null;
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
