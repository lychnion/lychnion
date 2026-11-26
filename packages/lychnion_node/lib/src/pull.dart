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

  /// Key statements left out of catalog.json to keep it under 2 MB
  /// (revocations and theft proofs kept first).
  var keysLeftOut = 0;

  /// Attestations left out of catalog.json to keep it under 2 MB (they go
  /// before key statements; withdrawals kept first).
  var attestationsLeftOut = 0;

  /// Publisher statuses left out of catalog.json (over 100 publishers, or
  /// 2 MB; they go last, Lychnion's kept first; #117).
  var statusLeftOut = 0;
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
  // Key statements kept here and learned from the sources (replaced and
  // revoked publisher keys) count for the records, and are passed on.
  var keys = trust.withStatements(await folder.keys(trust));
  // Lychnion's attestations kept here and learned from the sources (labels
  // only, lychnion/lychnion#119): passed on, never used for trust.
  final attestations = <Attestation>{...await folder.attestations(trust)};
  // Publishers' statuses (#117): kept here and learned from the sources,
  // the newest of each passed on. The key statements and withdrawals inside
  // each are taken in like the source's own.
  final status = <PublisherStatus>{...await folder.status(trust)};
  // Records here: the served catalog, and those set aside earlier because
  // their publisher was not given (kept, with their files, until it is).
  final before = [...await folder.allRecords(), ...await folder.keptRecords()];
  final have = <String, PackageRecord>{};
  // Files of records here that are no longer trusted (or not complete)
  // are not deleted: a publisher left out by mistake must not cost its
  // downloads.
  final untrusted = <String>{};
  final kept = <String, PackageRecord>{};
  for (final r in before) {
    // An added publisher's model listed by an older node: dropped (#67).
    if (!mayPublishKind(r.publisher, r.kind)) continue;
    if (await keys.verify(r)) {
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
    // A folder (a USB stick, step 5d): its catalog and files are read
    // from there; every file is still checked by its hash.
    final local = source.isScheme('file') ? _localFolder(source) : null;
    final sourcePrivate = local != null || await private.isPrivate(source.host);
    final _Catalog cat;
    try {
      cat = local != null
          ? _Catalog.parse(await _readLocal(local), local.uri)
          : _Catalog.parse(
              await fetchCatalogText(
                source,
                // An internet catalog must not redirect the node to its
                // own network, as for file addresses (#74).
                allowAddress: (u) async =>
                    sourcePrivate || !await private.isPrivate(u.host),
              ),
              source,
            );
    } on CatalogFetchError catch (e) {
      result.failed.add('${redactedUrl(source)}: ${e.code}');
      continue;
    } on FileSystemException {
      result.failed.add('${source.toFilePath()}: no catalog.json');
      continue;
    } on FormatException {
      result.failed.add('${redactedUrl(source)}: invalid');
      continue;
    }
    try {
      keys = keys.withStatements(await relevantStatements(keys, cat.keys));
      final learned = await PublisherStatus.checkAll(cat.status, keys);
      status.addAll(learned);
      keys = keys.withStatements(
        await relevantStatements(keys, [for (final s in learned) ...s.keys]),
      );
      attestations.addAll(
        await Attestation.checkAll([
          for (final s in learned) ...s.attestations,
        ], keys),
      );
    } on Object {
      // Not expected (relevantStatements skips what it cannot read), but
      // one catalog's keys must never end the pull for every source
      // (lychnion/lychnion#78).
      result.failed.add('${redactedUrl(source)}: invalid keys');
      continue;
    }
    attestations.addAll(await Attestation.checkAll(cat.attestations, keys));
    for (final raw in cat.records) {
      final r = await keys.check(raw);
      if (r == null) {
        result.notTrusted++;
        continue;
      }
      if (kinds.isNotEmpty && !kinds.contains(r.kind)) continue;
      // Models only from Lychnion: a node passes on no added publisher's
      // model, which phones would refuse anyway (#67).
      if (!mayPublishKind(r.publisher, r.kind)) {
        result.notTrusted++;
        continue;
      }
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
      final fetched = local != null
          ? await _copyFilesSafely(folder, r, local, cat, log)
          : await _fetchFiles(
              folder,
              r,
              addresses,
              log,
              // Redirects too: never into a private network from the
              // internet.
              (u) async => sourcePrivate || !await private.isPrivate(u.host),
            );
      if (fetched) {
        next[r.id] = r;
        if (newer) result.changed.add('${r.id} ${r.version}');
      } else {
        result.failed.add('${r.id} ${r.version}: files');
      }
    }
  }

  // Listed only when complete; an older complete version stays listed.
  // A record whose key a source revoked meanwhile is set aside, files
  // kept, like one whose publisher was not given.
  final listed = <PackageRecord>[];
  final complete = <PackageRecord>[];
  for (final r in next.values) {
    if (await _complete(folder, r)) {
      complete.add(r);
    } else if (have[r.id] case final old? when await _complete(folder, old)) {
      complete.add(old);
    } else {
      // No version complete (a file deleted by hand, the fetch failed):
      // not listed, but set aside with its files, so its version still
      // blocks an older one and the next pull fetches what is missing
      // (lychnion/lychnion#75).
      if (kept[r.id] == null || isOlder(kept[r.id]!.version, r.version)) {
        kept[r.id] = r;
      }
      untrusted.addAll(r.files.map((f) => f.sha256));
      if (have[r.id] case final old?) {
        untrusted.addAll(old.files.map((f) => f.sha256));
      }
      // When kept already holds a newer version, that one blocks older
      // ones. Reported every run until a source has the files again (or
      // the operator deletes `.kept.json`, which forgets the version).
      result.failed.add(
        '${r.id} ${r.version}: files missing, not listed (set aside; '
        'fetched again when a source has them)',
      );
    }
  }
  for (final r in complete) {
    if (await keys.verify(r)) {
      listed.add(r);
      continue;
    }
    if (kept[r.id] == null || isOlder(kept[r.id]!.version, r.version)) {
      kept[r.id] = r;
    }
    untrusted.addAll(r.files.map((f) => f.sha256));
    // The version before, when its key is still trusted, stays listed.
    if (have[r.id] case final old?
        when old != r &&
            await keys.verify(old) &&
            await _complete(folder, old)) {
      listed.add(old);
    }
  }
  try {
    // Checked once more with the keys after every source: a source's
    // key statements may have revoked the key that signed one (a fast
    // check: the signatures were checked when read).
    final left = await folder.writeCatalog(
      listed,
      trust: keys,
      keys: keys.statements,
      attestations: [
        for (final v in attestations)
          if (keys
              .keysFor(attesterPublisher, KeyScope.attestations)
              .contains(v.signer))
            v,
      ],
      // A far-future one (a stolen key's) never displaces the real one.
      status: PublisherStatus.deciding([
        for (final s in status)
          if (keys.keysFor(s.publisher, KeyScope.data).contains(s.signer)) s,
      ], DateTime.now()),
    );
    result.keysLeftOut = left.keys;
    result.attestationsLeftOut = left.attestations;
    result.statusLeftOut = left.status;
  } on CatalogTooLarge catch (e) {
    // The catalog served stays as it was, and so do the files it lists.
    result.failed.add('catalog.json: $e');
    return result;
  }
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

/// Whether [host] has an address that is not public
/// ([isNonPublicAddress]; a name that cannot be looked up counts as
/// private).
Future<bool> isPrivateHost(String host) => _PrivateHosts().isPrivate(host);

/// Whether a host has an address that is not public
/// ([isNonPublicAddress]; looked up once per host; a name that cannot be
/// looked up counts as private).
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

  static bool _private(InternetAddress a) => isNonPublicAddress(a);
}

/// Whether [a] is not a plain public unicast address, so a node pulling
/// from the internet must not send requests there (lychnion/lychnion#74):
/// loopback, link-local, private and shared ranges, the unspecified
/// address (`0.0.0.0/8`, `::`; on Linux a connect to either reaches this
/// machine), multicast, broadcast and reserved space, 192.0.0.0/24,
/// 198.18.0.0/15 (benchmarking), IPv6 unique local addresses, and an IPv4
/// address carried in IPv6: mapped `::ffff:a.b.c.d`, compatible
/// `::a.b.c.d`, NAT64 `64:ff9b::/96` and `64:ff9b:1::/48`, 6to4
/// `2002::/16` and translated `::ffff:0:a.b.c.d`, each judged by the IPv4
/// address it reaches. Teredo `2001::/32` and the old site-local
/// `fec0::/10` are refused too.
bool isNonPublicAddress(InternetAddress a) {
  final b = a.rawAddress;
  if (a.type == InternetAddressType.IPv4) return _nonPublicIPv4(b);
  // An IPv4 address carried in IPv6.
  final zero10 = b.take(10).every((x) => x == 0);
  if (zero10 && b[10] == 0xff && b[11] == 0xff) {
    return _nonPublicIPv4(b.sublist(12));
  }
  if (zero10 && b[10] == 0 && b[11] == 0) {
    // `::` and `::1` and the old `::a.b.c.d` form.
    return b.every((x) => x == 0) ||
        a.isLoopback ||
        _nonPublicIPv4(b.sublist(12));
  }
  if (b[0] == 0x00 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b) {
    // NAT64: the well-known prefix carries the IPv4 address last; the
    // local-use prefix 64:ff9b:1::/48 is for networks of their own.
    if (b[4] == 0 && b[5] == 1) return true;
    if (b.sublist(4, 12).every((x) => x == 0)) {
      return _nonPublicIPv4(b.sublist(12));
    }
  }
  // IPv4-translated `::ffff:0:a.b.c.d` (SIIT).
  final zero8 = b.take(8).every((x) => x == 0);
  if (zero8 && b[8] == 0xff && b[9] == 0xff && b[10] == 0 && b[11] == 0) {
    return _nonPublicIPv4(b.sublist(12));
  }
  if (b[0] == 0x20 && b[1] == 0x02) return _nonPublicIPv4(b.sublist(2, 6));
  // Teredo 2001::/32 tunnels to an address it hides: refused.
  if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0 && b[3] == 0) return true;
  if (a.isLoopback) return true;
  // Link-local fe80::/10 and the old site-local fec0::/10 (Dart's
  // isLinkLocal covers only part of the first).
  if (b[0] == 0xfe && (b[1] & 0x80) == 0x80) return true;
  if (b[0] == 0xff) return true; // multicast
  return (b[0] & 0xfe) == 0xfc; // fc00::/7
}

bool _nonPublicIPv4(List<int> b) =>
    b[0] == 0 || // 0.0.0.0/8, "this network"
    b[0] == 10 ||
    b[0] == 127 ||
    (b[0] == 100 && b[1] >= 64 && b[1] < 128) ||
    (b[0] == 169 && b[1] == 254) ||
    (b[0] == 172 && b[1] >= 16 && b[1] < 32) ||
    (b[0] == 192 && b[1] == 0 && b[2] == 0) ||
    (b[0] == 192 && b[1] == 168) ||
    (b[0] == 198 && (b[1] == 18 || b[1] == 19)) ||
    b[0] >= 224; // multicast, reserved, broadcast

/// The node folder at [source] (a `file:` address): `<dir>/lychnion` when
/// that holds the catalog (as the app writes a stick), else the folder.
Directory _localFolder(Uri source) {
  final dir = Directory(source.toFilePath());
  final inner = Directory('${dir.path}/lychnion');
  return File('${inner.path}/catalog.json').existsSync() ? inner : dir;
}

/// The catalog.json in [dir], at most [maxCatalogBytes] like a fetched one.
Future<String> _readLocal(Directory dir) async {
  final f = File('${dir.path}/catalog.json');
  if (await f.length() > maxCatalogBytes) {
    throw const FormatException('too large');
  }
  return f.readAsString();
}

/// [_copyFiles], false on any file error (the stick pulled out, the disk
/// full): the item fails, the others go on.
Future<bool> _copyFilesSafely(
  NodeFolder folder,
  PackageRecord r,
  Directory from,
  _Catalog cat,
  void Function(String line)? log,
) async {
  try {
    return await _copyFiles(folder, r, from, cat, log);
  } on FileSystemException catch (e) {
    log?.call('${r.id} ${r.version}: ${e.message}');
    return false;
  }
}

/// Copies the files of [r] from the folder [from] into [folder], each
/// checked by its hash before it is used.
Future<bool> _copyFiles(
  NodeFolder folder,
  PackageRecord r,
  Directory from,
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
    final listed = cat.urls[f.sha256];
    final candidates = [
      if (listed != null &&
          !listed.contains('..') &&
          !listed.startsWith('/') &&
          !(Uri.tryParse(listed)?.hasScheme ?? true))
        listed,
      'blobs/sha256/${f.sha256}',
    ];
    File? source;
    for (final c in candidates) {
      final file = File('${from.path}/$c');
      if (await file.exists()) {
        source = file;
        break;
      }
    }
    if (source == null || await source.length() != f.size) {
      log?.call('${r.id} ${r.version}: ${f.name} not in the folder');
      return false;
    }
    final part = File('${blob.path}.copy');
    try {
      await source.copy(part.path);
      if (await _sha256(part) != f.sha256) {
        log?.call('${r.id} ${r.version}: ${f.name} does not match');
        return false;
      }
      await part.rename(blob.path);
    } on FileSystemException catch (e) {
      // The stick pulled out, or the disk full.
      log?.call('${r.id} ${r.version}: ${f.name}: ${e.message}');
      return false;
    } finally {
      if (await part.exists()) await part.delete();
    }
    log?.call('${r.id} ${r.version}: ${f.name} (${f.size} bytes, copied)');
  }
  return true;
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
  _Catalog(
    this.records,
    this.base,
    this.urls,
    this.mirrors,
    this.keys,
    this.attestations,
    this.status,
  );

  final List<Object?> records;
  final List<Object?> keys;
  final List<Object?> attestations;
  final List<Object?> status;
  final Uri base;
  final Map<String, String> urls;
  final List<Uri> mirrors;

  factory _Catalog.parse(String text, Uri from) {
    final doc = CatalogDocument.parse(text);
    final base = doc.base != null ? (Uri.tryParse(doc.base!) ?? from) : from;
    return _Catalog(
      doc.records,
      from.resolveUri(base),
      doc.urls,
      [
        for (final m in doc.mirrors)
          if (Uri.tryParse(m.endsWith('/') ? m : '$m/') case final u?)
            if (_web(from.resolveUri(u))) from.resolveUri(u),
      ].take(10).toList(),
      doc.keys,
      doc.attestations,
      doc.status,
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
