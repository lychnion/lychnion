import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'catalog.dart';
import 'download_store.dart';
import 'downloader.dart';
import 'followed_catalogs.dart';
import 'package:lychnion_format/lychnion_format.dart';

/// Dev flags: where the catalog and relative file URLs come from.
const _catalogUrl = String.fromEnvironment('CATALOG_URL');
const _baseUrl = String.fromEnvironment('DOWNLOAD_BASE_URL');

/// Dev flag for scripted tests: comma-separated catalog ids to download
/// (or check, if the files are already there) on start, in order. A `!`
/// before an id downloads again even if a matching file is there.
const _autoDownload = String.fromEnvironment('AUTO_DOWNLOAD');

void _log(Map<String, Object?> data) =>
    debugPrint('LYCHNION ${jsonEncode(data)}');

/// Above this size the app asks before downloading.
const largeDownloadBytes = 1000 * 1000 * 1000;

enum ItemStatus { absent, partial, unverified, running, installed, update }

class ItemState {
  ItemStatus status = ItemStatus.absent;
  DownloadPhase? phase;
  int bytes = 0;
  int total = 0;

  /// Bytes per second over the last few seconds.
  double speed = 0;

  /// Short error code or message of the last attempt.
  String? error;
  String? installedVersion;
  CancelToken? cancel;
}

/// Keeps the catalog and the state of every download. One per app.
class DownloadManager extends ChangeNotifier {
  DownloadManager._(this.store);

  static Future<DownloadManager> create() async =>
      DownloadManager._(await DownloadStore.instance()).._init();

  final DownloadStore store;
  Catalog catalog = Catalog(const []);
  final _states = <String, ItemState>{};

  /// Counts installs and deletions, so loaders can react.
  final changes = ValueNotifier<int>(0);
  bool refreshing = false;
  int _lastPct = -1;
  String? catalogError;

  /// Catalogs of shelter computers this phone is connected to, merged into
  /// every catalog the app reads (a refresh from the internet must not drop
  /// the shelter's addresses).
  final _shelterCatalogs = <Uri, Catalog>{};

  /// What each shelter sent, to read again when publishers change.
  final _shelterBodies = <Uri, String>{};

  Catalog _withShelters(Catalog c) {
    for (final s in _shelterCatalogs.values) {
      c = c.mergedWith(s);
    }
    return c;
  }

  /// Lychnion's catalog (bundled, or the one fetched last).
  Catalog _main = Catalog(const []);

  /// Followed catalogs as last read (step 4c). Their text stays on disk
  /// (FollowedCatalogs.cached), not in memory.
  final _followed = <Uri, Catalog>{};

  /// What Downloads shows: Lychnion's catalog, then the followed ones
  /// (they add items and newer versions; Lychnion's keeps the rest), then
  /// connected bases (first, as on the local Wi-Fi).
  Catalog _compose() {
    var c = _main;
    for (final f in store.followed.all) {
      if (_followed[f.url] case final other?) {
        c = c.mergedWith(other, preferOther: false);
      }
    }
    return _withShelters(c);
  }

  /// Counts publisher changes: a catalog read before one is read again
  /// before it is used (its records were checked against the old keys).
  int _trustGeneration = 0;

  /// [body] as a catalog, or [CatalogFetchError] `invalid`.
  Future<Catalog> _parseFollowed(String body, Uri url) async {
    try {
      return await _parse(body, url);
    } on Object {
      throw CatalogFetchError('invalid');
    }
  }

  void _useFollowed(Uri url, Catalog c, DateTime fetched, {String? error}) {
    _followed[url] = c;
    store.followed.setStatus(
      url,
      CatalogStatus(
        shown: c.items.length,
        notShown: c.rejected.length,
        fetched: fetched,
        error: error,
      ),
    );
  }

  void _failedFollowed(Uri url, String code) {
    final old = store.followed.status[url];
    store.followed.setStatus(
      url,
      CatalogStatus(
        shown: old?.shown ?? 0,
        notShown: old?.notShown ?? 0,
        fetched: old?.fetched,
        error: code,
      ),
    );
  }

  /// The followed catalogs from their last copies (offline is fine). A
  /// copy that cannot be read is skipped; the others still load.
  Future<void> _loadFollowed() async {
    for (final f in store.followed.all) {
      final copy = await store.followed.cached(f.url);
      if (copy == null) continue;
      try {
        final c = await _parseFollowed(copy.body, f.url);
        _useFollowed(
          f.url,
          c,
          copy.fetched,
          error: store.followed.status[f.url]?.error,
        );
      } on CatalogFetchError catch (e) {
        _followed.remove(f.url);
        _failedFollowed(f.url, e.code);
      }
    }
  }

  /// Fetches one followed catalog. Only a copy that reads as a catalog is
  /// kept; on any failure the last good copy stays in use. A catalog
  /// removed meanwhile is left alone.
  Future<void> _fetchFollowed(Uri url) async {
    try {
      final body = await fetchCatalogText(url);
      var gen = _trustGeneration;
      var c = await _parseFollowed(body, url);
      // Kept only while still followed (one write at a time).
      if (!await store.followed.keep(url, body)) return;
      // Publishers changed meanwhile: check the records again.
      while (gen != _trustGeneration) {
        gen = _trustGeneration;
        c = await _parseFollowed(body, url);
      }
      if (!store.followed.follows(url)) return;
      _useFollowed(url, c, DateTime.now());
    } on CatalogFetchError catch (e) {
      if (!store.followed.follows(url)) return;
      _failedFollowed(url, e.code);
      _log({
        'event': 'followed_catalog_failed',
        'url': redactedUrl(url),
        'error': e.code,
      });
    } on Object catch (e) {
      // The copy could not be kept (disk): the last one stays.
      if (!store.followed.follows(url)) return;
      _failedFollowed(url, 'disk');
      _log({
        'event': 'followed_catalog_failed',
        'url': redactedUrl(url),
        'error': e.runtimeType.toString(),
      });
    }
  }

  /// Follows a catalog (after the user agreed): saves it, fetches it and
  /// shows its items. Returns its status, or null when it was followed
  /// already or the list is full. Throws when the list cannot be saved.
  Future<CatalogStatus?> follow(CatalogLink link) async {
    if (!await store.followed.add(link)) return null;
    await _fetchFollowed(link.url);
    catalog = _compose();
    _refreshStates();
    return store.followed.status[link.url];
  }

  /// Stops following [url]. What was installed from it stays.
  Future<void> unfollow(Uri url) async {
    await store.followed.remove(url);
    _followed.remove(url);
    catalog = _compose();
    _refreshStates();
  }

  ItemState stateOf(CatalogItem i) => _states[i.id] ??= ItemState();

  /// Installed items with a newer version in the catalog (for badges).
  final updates = ValueNotifier<int>(0);

  UpdateMode get updateMode => store.updateMode;
  Future<void> setUpdateMode(UpdateMode v) async {
    await store.setUpdateMode(v);
    notifyListeners();
    if (v != UpdateMode.off) unawaited(refreshCatalog());
  }

  bool _updating = false;

  /// With automatic updates: downloads new versions of installed items,
  /// one after another, only on Wi-Fi or a cable (never mobile data,
  /// whatever the mobile data setting says).
  Future<void> _autoUpdate() async {
    if (updateMode != UpdateMode.auto || _updating) return;
    final now = await Connectivity().checkConnectivity();
    final wifi = now.any(
      (c) => c == ConnectivityResult.wifi || c == ConnectivityResult.ethernet,
    );
    if (!wifi) return;
    _updating = true;
    try {
      for (final item in [...catalog.items]) {
        if (stateOf(item).status == ItemStatus.update) {
          _log({
            'event': 'auto_update',
            'id': item.id,
            'version': item.version,
          });
          await download(item);
        }
      }
    } finally {
      _updating = false;
    }
  }

  Future<void> _init() async {
    _main = await _localCatalog();
    await _loadFollowed();
    catalog = _compose();
    _refreshStates();
    if (_autoDownload.isNotEmpty) {
      unawaited(_runAuto());
    } else if (updateMode != UpdateMode.off) {
      // New versions: look once at start (offline is fine).
      unawaited(refreshCatalog());
    }
  }

  Future<void> _runAuto() async {
    await refreshCatalog();
    for (final raw in _autoDownload.split(',')) {
      final force = raw.trim().startsWith('!');
      final id = raw.trim().replaceFirst('!', '');
      final item = catalog.byId(id);
      if (item == null) {
        _log({'event': 'download_unknown', 'id': id});
        continue;
      }
      final s = stateOf(item);
      final sw = Stopwatch()..start();
      final resumeFrom = s.status == ItemStatus.partial ? s.bytes : 0;
      if (force && s.status != ItemStatus.installed) {
        await download(item, force: true);
      } else if (s.status == ItemStatus.unverified) {
        await verifyExisting(item);
      } else if (s.status != ItemStatus.installed) {
        await download(item);
      }
      _log({
        'event': 'download_done',
        'id': item.id,
        'status': stateOf(item).status.name,
        'error': stateOf(item).error,
        'resumed_from': resumeFrom,
        'bytes': item.size,
        'ms': sw.elapsedMilliseconds,
      });
    }
  }

  /// The bundled catalog, or the one fetched last (it wins).
  Future<Catalog> _localCatalog() async {
    var c = await _parse(
      await rootBundle.loadString('assets/downloads/catalog.json'),
      null,
    );
    try {
      final f = store.cachedCatalog;
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        c = await _parse(j['body'] as String, Uri.parse(j['url'] as String));
      }
    } catch (_) {}
    return c;
  }

  /// Removes an added publisher and deletes what was installed from it, so
  /// nothing of it stays in use or on the device. Throws when the list of
  /// publishers cannot be saved (then nothing changed).
  Future<void> removePublisher(String name) async {
    await store.publishers.remove(name);
    final n = await store.deleteFrom(name);
    _log({'event': 'publisher_removed', 'name': name, 'deleted': n});
    await publishersChanged();
  }

  /// A publisher was added or removed: install records are checked again,
  /// and every catalog is read again, so the publisher's records show up
  /// (or go). Shelter catalogs are read from what they sent, no network.
  Future<void> publishersChanged() async {
    _trustGeneration++;
    await store.reverify();
    _main = await _localCatalog();
    await _loadFollowed();
    for (final e in _shelterBodies.entries) {
      _shelterCatalogs[e.key] = await _parse(e.value, e.key);
    }
    catalog = _compose();
    changes.value++;
    _refreshStates();
  }

  /// Records with a bad signature are left out of the catalog and logged.
  Future<Catalog> _parse(String json, Uri? from) async {
    final c = await Catalog.parse(
      json,
      fetchedFrom: from,
      baseOverride: _baseUrl.isEmpty ? null : Uri.parse(_baseUrl),
      trust: store.trust,
    );
    // A few lines, not one per record: a catalog may hold thousands of
    // records from publishers not added.
    for (final r in c.rejected.take(10)) {
      final text = r.length > 200 ? '${r.substring(0, 200)}…' : r;
      _log({
        'event': 'catalog_rejected',
        'record': text,
        'from': from == null ? null : redactedUrl(from),
      });
    }
    if (c.rejected.length > 10) {
      _log({
        'event': 'catalog_rejected_more',
        'count': c.rejected.length - 10,
        'from': from == null ? null : redactedUrl(from),
      });
    }
    return c;
  }

  /// Fetches the newest catalog (dev flag CATALOG_URL, else the catalog's
  /// `refresh` URL). Offline is fine: the current one stays.
  Future<void> refreshCatalog() async {
    final url = _catalogUrl.isNotEmpty
        ? Uri.parse(_catalogUrl)
        : catalog.refreshUrl;
    if (refreshing) return;
    refreshing = true;
    catalogError = null;
    // Not during a build (Downloads starts a refresh in initState).
    scheduleMicrotask(notifyListeners);
    try {
      // No address of its own (dev setups): only the followed catalogs.
      if (url != null) {
        final body = await fetchCatalogText(url);
        _main = await _parse(body, url);
        await store.cachedCatalog.parent.create(recursive: true);
        await store.cachedCatalog.writeAsString(
          jsonEncode({'url': '$url', 'body': body}),
        );
      }
    } catch (e) {
      catalogError = 'offline';
    } finally {
      // Followed catalogs too, at the same time; each keeps its last copy
      // when it cannot be reached, and each fetch has its own time limit.
      await Future.wait([
        for (final f in store.followed.all) _fetchFollowed(f.url),
      ]);
      catalog = _compose();
      refreshing = false;
      _refreshStates();
    }
  }

  /// Adds the catalog of a shelter computer (its `/catalog.json`), so
  /// packages, maps and models can come from it over the local Wi-Fi,
  /// without internet. Signatures and hashes are checked as for any
  /// download. Returns how many items the shelter offers, or null when it
  /// could not be read.
  Future<int?> addCatalogFrom(Uri url) async {
    try {
      // Size and time limited, like every catalog fetch.
      final body = await fetchCatalogText(url);
      final other = await _parse(body, url);
      _shelterCatalogs[url] = other;
      _shelterBodies[url] = body;
      catalog = catalog.mergedWith(other);
      _log({
        'event': 'shelter_catalog',
        'from': redactedUrl(url),
        'items': other.items.length,
      });
      _refreshStates();
      return other.items.length;
    } catch (e) {
      _log({
        'event': 'shelter_catalog_failed',
        'from': redactedUrl(url),
        'error': e.runtimeType.toString(),
      });
      return null;
    }
  }

  /// Items the catalog at [url] (added with [addCatalogFrom]) offers that
  /// this device does not have, or has in an older version.
  int newItemsAt(Uri url) {
    final other = _shelterCatalogs[url];
    if (other == null) return 0;
    var n = 0;
    for (final i in other.items) {
      final have = store.installed(i.kind, i.id);
      if (have == null || compareVersions(have.version, i.version) < 0) n++;
    }
    return n;
  }

  /// Counts per followed catalog as Downloads shows them: an item left
  /// out by the merge (its id belongs to another publisher) counts as
  /// not shown.
  void _countFollowed() {
    for (final e in _followed.entries) {
      final old = store.followed.status[e.key];
      if (old == null) continue;
      var shown = 0;
      for (final i in e.value.items) {
        if (catalog.byId(i.id)?.record?.publisher == i.record?.publisher) {
          shown++;
        }
      }
      final notShown = e.value.rejected.length + e.value.items.length - shown;
      if (old.shown == shown && old.notShown == notShown) continue;
      store.followed.setStatus(
        e.key,
        CatalogStatus(
          shown: shown,
          notShown: notShown,
          fetched: old.fetched,
          error: old.error,
        ),
      );
    }
  }

  void _refreshStates() {
    _countFollowed();
    for (final item in catalog.items) {
      final s = stateOf(item);
      if (s.status == ItemStatus.running) continue;
      final inst = store.installed(item.kind, item.id);
      s.installedVersion = inst?.version;
      s.total = item.size;
      if (inst != null) {
        // A catalog with an older version is no update: versions only go up.
        s.status =
            inst.version == item.version || isOlder(item.version, inst.version)
            ? ItemStatus.installed
            : ItemStatus.update;
        s.bytes = item.size;
      } else if (store.hasUnverifiedFiles(item)) {
        s.status = ItemStatus.unverified;
        s.bytes = item.size;
      } else {
        s.bytes = store.partBytes(item, catalog);
        s.status = s.bytes > 0 ? ItemStatus.partial : ItemStatus.absent;
      }
    }
    updates.value = [
      for (final i in catalog.items)
        if (stateOf(i).status == ItemStatus.update) i,
    ].length;
    if (updates.value > 0) unawaited(_autoUpdate());
    notifyListeners();
  }

  MobileData get mobileData => store.mobileData;
  Future<void> setMobileData(MobileData v) async {
    await store.setMobileData(v);
    notifyListeners();
  }

  String? get chatModelId => store.chatModelId;
  Future<void> useChatModel(CatalogItem item) async {
    await store.setChatModelId(item.id);
    changes.value++;
    notifyListeners();
  }

  /// Null if downloading is allowed now, else `offline` or `wifi-only`.
  /// True when this download would go over mobile data (no Wi-Fi or
  /// cable): with "Ask first" the app then asks, whatever the size. Files
  /// from a shelter on the local Wi-Fi never get here: that is Wi-Fi.
  Future<bool> asksBeforeMobile(CatalogItem item) async {
    final now = await Connectivity().checkConnectivity();
    final wifi = now.any(
      (c) => c == ConnectivityResult.wifi || c == ConnectivityResult.ethernet,
    );
    return now.contains(ConnectivityResult.mobile) && !wifi;
  }

  Future<String?> networkProblem() async {
    final now = await Connectivity().checkConnectivity();
    if (now.isEmpty || now.every((c) => c == ConnectivityResult.none)) {
      return 'offline';
    }
    final ok = now.any(
      (c) => c == ConnectivityResult.wifi || c == ConnectivityResult.ethernet,
    );
    // Desktops report "other" for some links; only phones have mobile data.
    final mobile = now.contains(ConnectivityResult.mobile);
    if (mobileData == MobileData.never && mobile && !ok) return 'wifi-only';
    return null;
  }

  /// Downloads (or resumes, or updates) [item]. Errors end up in its state.
  ///
  /// [force] fetches files even if matching ones are there (tests only).
  Future<void> download(CatalogItem item, {bool force = false}) async {
    final s = stateOf(item);
    if (s.status == ItemStatus.running) return;
    s.error = await _refusal(item) ?? await networkProblem();
    if (s.error != null) return notifyListeners();
    final dir = store.dirFor(item.kind);
    final cancel = CancelToken();
    s
      ..status = ItemStatus.running
      ..cancel = cancel
      ..total = item.size
      ..speed = 0;
    notifyListeners();
    try {
      // A file that is already there and matches (copied by cable, the
      // first file of an interrupted map download, or a file an update did
      // not change) is not fetched again. On update a changed file replaces
      // the old one only once verified.
      var done = 0;
      for (final f in item.files) {
        final target = File('${dir.path}/${f.name}');
        if (!force &&
            await target.exists() &&
            await target.length() == f.size &&
            await sha256OfFile(target, cancel: cancel) == f.sha256) {
          done += f.size;
          continue;
        }
        final sw = Stopwatch()..start();
        var lastBytes = 0, lastMs = 0, lastUi = 0;
        final downloader = Downloader(
          onSourceFailed: (url, e) => _log({
            'event': 'download_source_failed',
            'id': item.id,
            'url': redactedUrl(url),
            'error': sourceErrorText(e),
          }),
        );
        try {
          await downloader.fetch(
            catalog.spec(f),
            dir,
            cancel: cancel,
            onProgress: (phase, bytes, total) {
              final ms = sw.elapsedMilliseconds;
              if (ms - lastUi < 200 && phase == s.phase) return;
              if (phase == DownloadPhase.downloading && ms - lastMs > 2000) {
                s.speed = (bytes - lastBytes) / ((ms - lastMs) / 1000);
                lastBytes = bytes;
                lastMs = ms;
              }
              if (phase != DownloadPhase.downloading) {
                lastBytes = bytes;
                lastMs = ms;
              }
              lastUi = ms;
              final pct = 100 * (done + bytes) ~/ item.size;
              if (_autoDownload.isNotEmpty && pct ~/ 10 != _lastPct ~/ 10) {
                _lastPct = pct;
                _log({
                  'event': 'download_progress',
                  'id': item.id,
                  'phase': phase.name,
                  'pct': pct,
                });
              }
              s
                ..phase = phase
                ..bytes =
                    done + (phase == DownloadPhase.checkingPart ? 0 : bytes);
              notifyListeners();
            },
          );
        } finally {
          downloader.close();
        }
        done += f.size;
      }
      await store.markInstalled(item);
      s.error = null;
      changes.value++;
    } catch (e) {
      s.error = _errorCode(e);
      if (s.error != null) {
        // An HttpException's text carries its address (maybe with a token).
        _log({
          'event': 'download_error',
          'id': item.id,
          'detail': e is HttpException ? sourceErrorText(e) : '$e',
        });
      }
    } finally {
      s
        ..cancel = null
        ..phase = null
        ..status = ItemStatus.absent;
      _refreshStates();
    }
  }

  /// Error code when [item] must not be installed: no valid signature
  /// (`signature`), its id or a file name installed from another publisher
  /// (`taken`), or older than the installed version (`older`).
  Future<String?> _refusal(CatalogItem item) async {
    final r = item.record;
    if (r == null || !await store.trust.verify(r)) return 'signature';
    if (store.isTaken(item)) return 'taken';
    // Also what is on disk but no longer trusted: files are replaced while
    // downloading, before the install is recorded.
    final have = store.installedVersion(item) ?? store.recordedVersion(item);
    if (have != null && isOlder(item.version, have)) return 'older';
    return null;
  }

  @visibleForTesting
  static String? errorCodeOf(Object e) => _errorCode(e);

  /// Short code for the screen (see DownloadsScreen), or null if stopped.
  /// Never the address: it may carry a token.
  static String? _errorCode(Object e) => switch (e) {
    DownloadCancelled() => null,
    UnsignedItem() => 'signature',
    OlderVersion() => 'older',
    TakenItem() => 'taken',
    ChecksumError() => 'checksum',
    DownloadBusy() => 'busy',
    SocketException(:final osError) =>
      _diskFull(osError) ? 'disk-full' : 'network',
    FileSystemException(:final osError) =>
      _diskFull(osError) ? 'disk-full' : 'disk',
    TimeoutException() => 'network',
    HttpException(:final message) when !message.startsWith('HTTP ') =>
      'network',
    HttpException(:final message) => message,
    TlsException() => 'network',
    _ => '$e',
  };

  /// ENOSPC (macOS, Linux, Android) or ERROR_DISK_FULL (Windows).
  static bool _diskFull(OSError? e) =>
      e != null && (e.errorCode == 28 || e.errorCode == 112);

  void stop(CatalogItem item) => stateOf(item).cancel?.cancel();

  Future<void> delete(CatalogItem item) async {
    stop(item);
    await store.delete(item);
    stateOf(item).error = null;
    changes.value++;
    _refreshStates();
  }

  /// Checks files that are already there (copied by cable) and records
  /// them as installed if they match the catalog.
  Future<void> verifyExisting(CatalogItem item) async {
    final s = stateOf(item);
    s.error = await _refusal(item);
    if (s.error != null) return notifyListeners();
    final cancel = CancelToken();
    s
      ..status = ItemStatus.running
      ..phase = DownloadPhase.verifying
      ..cancel = cancel
      ..bytes = 0;
    notifyListeners();
    try {
      var done = 0;
      for (final f in item.files) {
        final file = File('${store.dirFor(item.kind).path}/${f.name}');
        var lastUi = 0;
        final sum = await sha256OfFile(
          file,
          cancel: cancel,
          onProgress: (n) {
            if (n - lastUi < 32 << 20) return;
            lastUi = n;
            s.bytes = done + n;
            notifyListeners();
          },
        );
        if (sum != f.sha256) throw ChecksumError(f.name, f.sha256, sum);
        done += f.size;
      }
      await store.markInstalled(item);
      s.error = null;
      changes.value++;
    } on DownloadCancelled {
      s.error = null;
    } on ChecksumError {
      s.error = 'checksum-local';
    } catch (e) {
      s.error = '$e';
    } finally {
      s
        ..cancel = null
        ..phase = null
        ..status = ItemStatus.absent;
      _refreshStates();
    }
  }

  @override
  void dispose() {
    changes.dispose();
    super.dispose();
  }
}
