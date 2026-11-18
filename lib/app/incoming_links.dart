part of 'app_shell.dart';

/// Links opened from outside the app: a shelter's QR code, a catalog or
/// publisher link, or a phone nearby that shares its downloads.
mixin _IncomingLinks on State<AppShell> {
  DownloadManager? get _downloads;
  set _tab(int value);
  void _openDownloads();

  bool _asking = false;

  /// A scanned lychnion://shelter link: ask, then connect. The same link can
  /// arrive twice (at launch and from the stream): ask only once.
  Future<void> _openLink(Uri uri) async {
    if (ShareLink.fromUri(uri) case final share?) {
      await _receiveShare(share);
      return;
    }
    if (CatalogLink.fromUri(uri) case final catalog?) {
      final dm = _downloads;
      // At a cold start Downloads may not be ready yet: ask once it is.
      if (dm == null) {
        _pendingCatalog = catalog;
        return;
      }
      if (!mounted || _asking) return;
      _asking = true;
      try {
        await followCatalog(context, dm, catalog);
      } finally {
        _asking = false;
      }
      return;
    }
    if (PublisherLink.fromUri(uri) case final publisher?) {
      final dm = _downloads;
      // At a cold start Downloads may not be ready yet: ask once it is.
      if (dm == null) {
        _pendingPublisher = publisher;
        return;
      }
      if (!mounted || _asking) return;
      _asking = true;
      try {
        await addPublisher(context, dm, publisher);
      } finally {
        _asking = false;
      }
      return;
    }
    final link = ShelterLink.fromUri(uri);
    if (link == null || !mounted || _asking) return;
    // Already connected, and nothing new: a QR code with the key of a base
    // connected by address or found on the Wi-Fi pins that key.
    if (link.url == widget.settings.shelterUrl &&
        (link.key == null || link.key == widget.settings.shelterKey)) {
      return;
    }
    _asking = true;
    try {
      if (await confirmShelter(context, link)) {
        await widget.settings.setShelter(
          link.url,
          name: link.name,
          key: link.key,
        );
        setState(() => _tab = 0);
      }
    } finally {
      _asking = false;
    }
  }

  /// A publisher link that arrived before Downloads was ready.
  PublisherLink? _pendingPublisher;

  /// A catalog link that arrived before Downloads was ready.
  CatalogLink? _pendingCatalog;

  /// A phone nearby shares its downloads: ask, then show what it offers in
  /// Downloads. Records and files are checked as for any download.
  Future<void> _receiveShare(ShareLink link) async {
    final dm = _downloads;
    if (dm == null || !mounted || _asking) return;
    _asking = true;
    try {
      final l = context.l10n;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.share_rounded),
          title: Text(l.shareReceiveTitle),
          content: Text(
            l.shareReceiveBody(link.url.replaceFirst('http://', '')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l.shareReceiveShow),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final url = Uri.parse(link.url).resolve('/catalog.json');
      final offered = await dm.addCatalogFrom(url);
      if (!mounted) return;
      // Count only what this phone does not have yet.
      final n = offered == null ? 0 : dm.newItemsAt(url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            offered == null
                ? l.shareReceiveNone
                : n == 0
                ? l.shareReceiveNothingNew
                : l.shareReceiveFound(n),
          ),
        ),
      );
      if (offered != null) _openDownloads();
    } finally {
      _asking = false;
    }
  }
}
