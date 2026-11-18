import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'catalog.dart';
import 'download_store.dart';
import 'downloader.dart';
import 'record.dart';

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

  Catalog _withShelters(Catalog c) {
    for (final s in _shelterCatalogs.values) {
      c = c.mergedWith(s);
    }
    return c;
  }

  ItemState stateOf(CatalogItem i) => _states[i.id] ??= ItemState();

  Future<void> _init() async {
    final bundled = await rootBundle.loadString(
      'assets/downloads/catalog.json',
    );
    catalog = await _parse(bundled, null);
    // A catalog fetched earlier wins over the bundled one.
    try {
      final f = store.cachedCatalog;
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        catalog = await _parse(
          j['body'] as String,
          Uri.parse(j['url'] as String),
        );
      }
    } catch (_) {}
    _refreshStates();
    if (_autoDownload.isNotEmpty) unawaited(_runAuto());
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

  /// Records with a bad signature are left out of the catalog and logged.
  Future<Catalog> _parse(String json, Uri? from) async {
    final c = await Catalog.parse(
      json,
      fetchedFrom: from,
      baseOverride: _baseUrl.isEmpty ? null : Uri.parse(_baseUrl),
      trust: store.trust,
    );
    for (final r in c.rejected) {
      _log({'event': 'catalog_rejected', 'record': r, 'from': '$from'});
    }
    return c;
  }

  /// Fetches the newest catalog (dev flag CATALOG_URL, else the catalog's
  /// `refresh` URL). Offline is fine: the current one stays.
  Future<void> refreshCatalog() async {
    final url = _catalogUrl.isNotEmpty
        ? Uri.parse(_catalogUrl)
        : catalog.refreshUrl;
    if (url == null || refreshing) return;
    refreshing = true;
    catalogError = null;
    notifyListeners();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(url);
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final body = await res.transform(utf8.decoder).join();
      catalog = _withShelters(await _parse(body, url));
      await store.cachedCatalog.parent.create(recursive: true);
      await store.cachedCatalog.writeAsString(
        jsonEncode({'url': '$url', 'body': body}),
      );
    } catch (e) {
      catalogError = 'offline';
    } finally {
      client.close(force: true);
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
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(url);
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final other = await _parse(body, url);
      _shelterCatalogs[url] = other;
      catalog = catalog.mergedWith(other);
      _log({
        'event': 'shelter_catalog',
        'from': '$url',
        'items': other.items.length,
      });
      _refreshStates();
      return other.items.length;
    } catch (e) {
      _log({'event': 'shelter_catalog_failed', 'from': '$url', 'error': '$e'});
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void _refreshStates() {
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
        await Downloader().fetch(
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
        done += f.size;
      }
      await store.markInstalled(item);
      s.error = null;
      changes.value++;
    } catch (e) {
      s.error = _errorCode(e);
      if (s.error != null) {
        _log({'event': 'download_error', 'id': item.id, 'detail': '$e'});
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
  /// (`signature`) or older than the installed version (`older`).
  Future<String?> _refusal(CatalogItem item) async {
    final r = item.record;
    if (r == null || !await store.trust.verify(r)) return 'signature';
    final have = store.installedVersion(item);
    if (have != null && isOlder(item.version, have)) return 'older';
    return null;
  }

  /// Short code for the screen (see DownloadsScreen), or null if stopped.
  static String? _errorCode(Object e) => switch (e) {
    DownloadCancelled() => null,
    UnsignedItem() => 'signature',
    OlderVersion() => 'older',
    ChecksumError() => 'checksum',
    DownloadBusy() => 'busy',
    SocketException(:final osError) =>
      _diskFull(osError) ? 'disk-full' : 'network',
    FileSystemException(:final osError) =>
      _diskFull(osError) ? 'disk-full' : 'disk',
    TimeoutException() => 'network',
    HttpException(:final message) when !message.startsWith('HTTP ') =>
      'network',
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
