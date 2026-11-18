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

  /// Records here whose publisher is not trusted in this run (left out
  /// of the catalog; their files are kept).
  var keptUntrusted = 0;
}

/// Another pull is working on this folder (cron runs overlapping).
class PullBusy implements Exception {
  @override
  String toString() => 'Another pull is running on this folder';
}

/// Pulls the catalogs at [sources] into [folder]: keeps the records
/// [trust] accepts, fetches their files by hash (resumable, from every
/// address a catalog gives, the hash decides), and writes the folder's
/// catalog.json. Versions only go up, an id stays with the publisher that
/// has it here (except that Lychnion, built in, always keeps its own
/// ids), and a record is listed only once all its files are here.
/// Afterwards files no record needs any more are deleted; files of
/// records no longer trusted (a `--publisher` left out) are kept.
///
/// One pull per folder at a time: a second one throws [PullBusy].
/// Run it again and again (cron): what is current is not fetched again.
///
/// [kinds] (`package`, `map`, `model`): only those; empty means all.
/// Models are large (gigabytes), so a node may leave them out.
///
/// Addresses a catalog gives for files on private, loopback or link-local
/// networks are skipped unless the catalog itself is on such a network
/// (a base on the local Wi-Fi), so a catalog from the internet cannot
/// make the node probe its own network.
Future<PullResult> pull(
  List<Uri> sources,
  NodeFolder folder,
  TrustedKeys trust, {
  Set<String> kinds = const {},
  void Function(String line)? log,
}) async {
  await folder.blobs.create(recursive: true);
  final lock = await File(
    '${folder.dir.path}/.pull.lock',
  ).open(mode: FileMode.write);
  try {
    await lock.lock(FileLock.exclusive);
  } on FileSystemException {
    await lock.close();
    throw PullBusy();
  }
  try {
    return await _pull(sources, folder, trust, kinds, log);
  } finally {
    await lock.unlock();
    await lock.close();
  }
}

Future<PullResult> _pull(
  List<Uri> sources,
  NodeFolder folder,
  TrustedKeys trust,
  Set<String> kinds,
  void Function(String line)? log,
) async {
  final result = PullResult();
  // Records here: the served catalog, and those set aside earlier because
  // their publisher was not given (kept, with their files, until it is).
  final before = [...await folder.allRecords(), ...await folder.keptRecords()];
  final have = <String, PackageRecord>{};
  // Files of records here that are no longer trusted are not deleted: a
  // publisher left out by mistake must not cost its downloads.
  final untrusted = <String>{};
  final kept = <String, PackageRecord>{};
  for (final r in before) {
    if (await trust.verify(r)) {
      if (have[r.id] case final o? when !isOlder(o.version, r.version)) {
        continue;
      }
      have[r.id] = r;
    } else if (kept[r.id] == null || isOlder(kept[r.id]!.version, r.version)) {
      kept[r.id] = r;
    }
  }
  for (final r in kept.values) {
    untrusted.addAll(r.files.map((f) => f.sha256));
  }
  result.keptUntrusted = kept.length;
  final next = Map.of(have);
  final builtIn = builtInPublishers.publishers.toSet();
  final wanted = <String>{}; // hashes of every record looked at
  final private = _PrivateHosts();

  for (final source in sources) {
    final _Catalog cat;
    try {
      cat = _Catalog.parse(await fetchCatalogText(source), source);
    } on CatalogFetchError catch (e) {
      result.failed.add('${redactedUrl(source)}: ${e.code}');
      continue;
    } on FormatException {
      result.failed.add('${redactedUrl(source)}: invalid');
      continue;
    }
    final sourcePrivate = await private.isPrivate(source.host);
    for (final raw in cat.records) {
      final r = await trust.check(raw);
      if (r == null) {
        result.notTrusted++;
        continue;
      }
      if (kinds.isNotEmpty && !kinds.contains(r.kind)) continue;
      // A set-aside record still owns its id.
      final mine = next[r.id] ?? kept[r.id];
      // Lychnion (built in) keeps its own ids; otherwise the publisher
      // that has an id here keeps it.
      final lychnionTakesBack =
          mine != null &&
          builtIn.contains(r.publisher) &&
          !builtIn.contains(mine.publisher);
      if (mine != null && mine.publisher != r.publisher && !lychnionTakesBack) {
        result.taken.add(r.id);
        continue;
      }
      wanted.addAll(r.files.map((f) => f.sha256));
      final newer =
          mine == null || lychnionTakesBack || isOlder(mine.version, r.version);
      final same = mine != null && mine.version == r.version;
      // Same version with files missing here (deleted by hand): fetch them.
      if (!newer && !(same && !await _complete(folder, mine))) continue;
      final addresses = <RecordFile, List<Uri>>{};
      for (final f in r.files) {
        addresses[f] = [
          for (final u in cat.addressesOf(f))
            if (sourcePrivate || !await private.isPrivate(u.host)) u,
        ];
      }
      if (await _fetchFiles(
        folder,
        r,
        addresses,
        log,
        // Redirects too: never into a private network from the internet.
        (u) async => sourcePrivate || !await private.isPrivate(u.host),
      )) {
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
  await folder.writeKept([
    for (final r in kept.values)
      if (!listed.any((l) => l.id == r.id)) r,
  ]);

  final keep = {
    for (final r in listed)
      for (final f in r.files) f.sha256,
    ...untrusted,
  };
  for (final f in folder.blobs.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (folder.blob(name) != null) {
      if (!keep.contains(name)) {
        f.deleteSync();
        result.pruned++;
      }
      continue;
    }
    // Half-downloaded files of versions nobody offers any more.
    final hash = name.split('.').first;
    if (folder.blob(hash) != null &&
        (name.endsWith('.part') || name.endsWith('.part.json')) &&
        !keep.contains(hash) &&
        !wanted.contains(hash)) {
      f.deleteSync();
    }
  }
  return result;
}

/// Whether [host] is on a private, loopback or link-local network (a
/// name that cannot be looked up counts as private).
Future<bool> isPrivateHost(String host) => _PrivateHosts().isPrivate(host);

/// Whether a host is on a private, loopback or link-local network (looked
/// up once per host; a name that cannot be looked up counts as private).
class _PrivateHosts {
  final _known = <String, bool>{};

  Future<bool> isPrivate(String host) async {
    if (_known[host] case final v?) return v;
    List<InternetAddress> addresses;
    if (InternetAddress.tryParse(host) case final a?) {
      addresses = [a];
    } else {
      try {
        addresses = await InternetAddress.lookup(host);
      } on Object {
        addresses = const [];
      }
    }
    final v = addresses.isEmpty || addresses.any(_private);
    return _known[host] = v;
  }

  static bool _private(InternetAddress a) {
    var b = a.rawAddress;
    // ::ffff:a.b.c.d reaches the IPv4 address a.b.c.d.
    if (a.type == InternetAddressType.IPv6 &&
        b.take(10).every((x) => x == 0) &&
        b[10] == 0xff &&
        b[11] == 0xff) {
      a = InternetAddress.fromRawAddress(b.sublist(12));
      b = a.rawAddress;
    }
    if (a.isLoopback || a.isLinkLocal) return true;
    if (a.type == InternetAddressType.IPv4) {
      return b[0] == 10 ||
          (b[0] == 172 && b[1] >= 16 && b[1] < 32) ||
          (b[0] == 192 && b[1] == 168) ||
          (b[0] == 100 && b[1] >= 64 && b[1] < 128) ||
          b[0] == 0;
    }
    return (b[0] & 0xfe) == 0xfc; // fc00::/7
  }
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
  Map<RecordFile, List<Uri>> addresses,
  void Function(String line)? log,
  Future<bool> Function(Uri url) allow,
) async {
  for (final f in r.files) {
    final blob = folder.blob(f.sha256)!;
    if (await blob.exists() &&
        await blob.length() == f.size &&
        await _sha256(blob) == f.sha256) {
      continue;
    }
    final urls = addresses[f] ?? const [];
    if (urls.isEmpty) {
      log?.call('${r.id} ${r.version}: ${f.name}: no usable address');
      return false;
    }
    final downloader = Downloader(
      allowAddress: allow,
      onSourceFailed: (u, e) =>
          log?.call('  ${redactedUrl(u)}: ${sourceErrorText(e)}'),
    );
    try {
      await downloader.fetch(
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
    } finally {
      downloader.close();
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
    if ((j['urls'] != null && j['urls'] is! Map) ||
        (j['mirrors'] != null && j['mirrors'] is! List) ||
        (j['base'] != null && j['base'] is! String)) {
      throw const FormatException('urls, mirrors or base of the wrong type');
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
