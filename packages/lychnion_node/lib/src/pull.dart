import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:lychnion_fetch/lychnion_fetch.dart';
import 'package:lychnion_format/lychnion_format.dart';

import 'node_folder.dart';

/// What a pull did.
class PullResult {
  /// Ids added or updated.
  final changed = <String>[];

  /// Records left out: not signed by a trusted publisher, or broken.
  var notTrusted = 0;

  /// Ids not taken because another publisher has that id here.
  final taken = <String>[];

  /// Sources or ids that failed (the last version stays), with why.
  final failed = <String>[];

  /// Files deleted because no record lists them any more.
  var pruned = 0;
}

/// Pulls the catalogs at [sources] into [folder]: keeps the records
/// [trust] accepts, fetches their files by hash (resumable, from every
/// address a catalog gives, the hash decides), and writes the folder's
/// catalog.json. Versions only go up, an id stays with the publisher that
/// has it here, and a record is listed only once all its files are here.
/// Files no record lists any more are deleted afterwards.
///
/// Run it again and again (cron): what is current is not fetched again.
///
/// [kinds] (`package`, `map`, `model`): only those; empty means all.
/// Models are large (gigabytes), so a node may leave them out.
Future<PullResult> pull(
  List<Uri> sources,
  NodeFolder folder,
  TrustedKeys trust, {
  Set<String> kinds = const {},
  void Function(String line)? log,
}) async {
  final result = PullResult();
  final have = {for (final r in await folder.records(trust)) r.id: r};
  final next = Map.of(have);
  await folder.blobs.create(recursive: true);

  for (final source in sources) {
    final _Catalog cat;
    try {
      cat = _Catalog.parse(await fetchCatalogText(source), source);
    } on CatalogFetchError catch (e) {
      result.failed.add('$source: ${e.code}');
      continue;
    } on FormatException {
      result.failed.add('$source: invalid');
      continue;
    }
    for (final raw in cat.records) {
      final r = await trust.check(raw);
      if (r == null) {
        result.notTrusted++;
        continue;
      }
      if (kinds.isNotEmpty && !kinds.contains(r.kind)) continue;
      final mine = next[r.id];
      if (mine != null && mine.publisher != r.publisher) {
        result.taken.add(r.id);
        continue;
      }
      final newer = mine == null || isOlder(mine.version, r.version);
      final same = mine != null && mine.version == r.version;
      // Same version with files missing here (deleted by hand): fetch them.
      if (!newer && !(same && !await _complete(folder, mine))) continue;
      if (await _fetchFiles(folder, r, cat, log)) {
        next[r.id] = r;
        if (newer) result.changed.add('${r.id} ${r.version}');
      } else {
        result.failed.add('${r.id} ${r.version}: files');
      }
    }
  }

  // Listed only when complete; an older complete version stays listed.
  final listed = [
    for (final r in next.values)
      if (await _complete(folder, r))
        r
      else if (have[r.id] case final old? when await _complete(folder, old))
        old,
  ];
  await folder.writeCatalog(listed);

  final keep = {
    for (final r in listed)
      for (final f in r.files) f.sha256,
  };
  for (final f in folder.blobs.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (folder.blob(name) != null && !keep.contains(name)) {
      f.deleteSync();
      result.pruned++;
    }
  }
  return result;
}

/// Whether every file of [r] is here at its size.
Future<bool> _complete(NodeFolder folder, PackageRecord r) async {
  for (final f in r.files) {
    final b = folder.blob(f.sha256)!;
    if (!await b.exists() || await b.length() != f.size) return false;
  }
  return true;
}

Future<bool> _fetchFiles(
  NodeFolder folder,
  PackageRecord r,
  _Catalog cat,
  void Function(String line)? log,
) async {
  for (final f in r.files) {
    final blob = folder.blob(f.sha256)!;
    if (await blob.exists() &&
        await blob.length() == f.size &&
        await _sha256(blob) == f.sha256) {
      continue;
    }
    final urls = cat.addressesOf(f);
    if (urls.isEmpty) return false;
    try {
      await Downloader(
        onSourceFailed: (u, e) =>
            log?.call('  ${redactedUrl(u)}: ${sourceErrorText(e)}'),
      ).fetch(
        FileSpec(
          url: urls.first,
          fallbacks: urls.skip(1).toList(),
          name: f.sha256,
          size: f.size,
          sha256: f.sha256,
        ),
        folder.blobs,
      );
      log?.call('${r.id} ${r.version}: ${f.name} (${f.size} bytes)');
    } on Object catch (e) {
      log?.call(
        '${r.id} ${r.version}: ${f.name} failed: ${sourceErrorText(e)}',
      );
      return false;
    }
  }
  return true;
}

Future<String> _sha256(File f) async =>
    (await crypto.sha256.bind(f.openRead()).first).toString();

/// The parts of a catalog (format 2) a node needs: its records as given,
/// and where their files are.
class _Catalog {
  _Catalog(this.records, this.base, this.urls, this.mirrors);

  final List<Object?> records;
  final Uri base;
  final Map<String, String> urls;
  final List<Uri> mirrors;

  factory _Catalog.parse(String text, Uri from) {
    final j = jsonDecode(text);
    if (j is! Map || j['format'] != 2 || j['records'] is! List) {
      throw const FormatException('not a format 2 catalog');
    }
    final base = j['base'] is String
        ? (Uri.tryParse(j['base'] as String) ?? from)
        : from;
    return _Catalog(
      j['records'] as List,
      from.resolveUri(base),
      {
        for (final e in ((j['urls'] as Map?) ?? const {}).entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      },
      [
        for (final m in (j['mirrors'] as List?) ?? const [])
          if (m is String)
            if (Uri.tryParse(m.endsWith('/') ? m : '$m/') case final u?)
              if (_web(from.resolveUri(u))) from.resolveUri(u),
      ].take(10).toList(),
    );
  }

  static bool _web(Uri u) =>
      (u.isScheme('http') || u.isScheme('https')) && u.host.isNotEmpty;

  /// The file's own address (`urls`, else next to the catalog by name),
  /// then each mirror's `blobs/sha256/<hash>`; http(s) only.
  List<Uri> addressesOf(RecordFile f) {
    final out = <Uri>[];
    void add(Uri? u) {
      if (u != null && _web(u) && !out.contains(u)) out.add(u);
    }

    final own = Uri.tryParse(urls[f.sha256] ?? f.name);
    add(own == null ? null : base.resolveUri(own));
    for (final m in mirrors) {
      add(m.resolve('blobs/sha256/${f.sha256}'));
    }
    return out;
  }
}
