part of 'ask_page.dart';

/// Desktop side: shares this computer as a base on the local
/// network, and announces it so phones find it.
mixin _BaseSharing on _AskPageBase {
  /// Server changes run one after the other.
  Future<void> _serverOps = Future.value();

  void _sharingChanged() {
    final want = sharingOn(widget.settings) && _answerer != null;
    final name = sharingName(widget.settings);
    if (want == (_server != null) && (!want || _server!.name == name)) return;
    _serverOps = _serverOps.then((_) => _syncServer()).then((_) {
      if (!mounted) return;
      setState(() {
        if (_phase == AskPhase.serving ||
            _phase == AskPhase.ready ||
            _phase == AskPhase.base) {
          _phase = _server != null
              ? AskPhase.serving
              : (_baseReady ? AskPhase.base : AskPhase.ready);
        }
      });
    });
  }

  /// Starts, stops or renames the server to match the settings. Answering
  /// needs the loaded model, so it starts once the model is ready.
  @override
  Future<void> _syncServer() async {
    final answerer = _answerer;
    final want = sharingOn(widget.settings) && answerer != null;
    final name = sharingName(widget.settings);
    // A new answerer (other packages, or a publisher removed) restarts the
    // server: it must not keep answering from what was unloaded.
    if (_server case final s?
        when !want || s.name != name || s.answerer != answerer) {
      await s.stop();
      await _announcer.stop().catchError((Object _) {});
      _server = null;
      widget.baseUrls?.value = const [];
      _log({'event': 'base_stopped'});
    }
    if (!want || _server != null) return;
    final server = BaseServer(
      answerer: answerer,
      name: name,
      modelName: DevFlags.modelPath.split('/').last,
      facts: widget.facts,
      codec: widget.map?.sites == null
          ? null
          : CompactCodec(widget.map!.sites!.siteIds),
      // Pass on what this computer has installed (packages, maps,
      // models), so phones can update here without internet.
      library: BaseLibrary(await DownloadStore.instance()),
      page: await rootBundle.loadString('assets/web/base.html'),
      placeName: (id) => widget.map?.sites?.byUid(id)?.name,
    );
    try {
      await server.start();
    } on SocketException catch (e) {
      _log({'event': 'base_failed', 'error': '$e'});
      return;
    }
    _server = server;
    // Exactly where it listens: the local-network addresses, followed as
    // the network changes (#64).
    List<String> urlsOf(List<String> addresses) => [
      for (final a in addresses) 'http://$a:${BaseServer.defaultPort}',
    ];
    final urls = urlsOf(server.addresses);
    widget.baseUrls?.value = urls;
    server.onAddressesChanged = (a) {
      if (!identical(_server, server)) return;
      widget.baseUrls?.value = urlsOf(a);
      _log({'event': 'base_addresses', 'urls': urlsOf(a)});
    };
    _log({'event': 'base_started', 'name': name, 'urls': urls});
    // Phones on this Wi-Fi find the base without its QR code (step 5e).
    // Serving goes on if announcing is not possible here.
    try {
      await _announcer.start(
        name: name,
        port: BaseServer.defaultPort,
        key: widget.facts?.signer?.publicKeyText,
      );
    } on Object catch (e) {
      _log({'event': 'base_announce_failed', 'error': '$e'});
    }
  }

  final _announcer = BaseAnnouncer();
}
