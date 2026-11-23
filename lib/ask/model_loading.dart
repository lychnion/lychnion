part of 'ask_page.dart';

/// Loads the chat model, the search model and the knowledge packages, and
/// runs the test questions (AUTO_BENCH).
mixin _ModelLoading on _AskPageBase {
  final _url = TextEditingController(text: DevFlags.modelUrl);

  final _embedder = LocalEmbedder();

  /// What the last load used from Downloads (model, embedder, package).
  String? _loadedDownloads;

  /// A download change that came while busy, looked at again later.
  Timer? _reloadLater;

  /// Whether the last failed load failed before the chat was ready (the
  /// model or the engine), not later (search model, packages).
  bool _chatFailed = false;

  /// Whether Downloads were looked at once in this run (a crash marker
  /// left by an earlier run is read only then).
  bool _loadedOnce = false;

  /// Loads the model on start: GGUF_MODEL_PATH, a download for AUTO_BENCH
  /// on phones, else the model from Downloads (again whenever it changes).
  void _startModel() {
    if (DevFlags.modelPath.isNotEmpty) {
      unawaited(
        _run(
          () async => _llm.loadFile(await resolvePath(DevFlags.modelPath)),
          afterLoad: true,
        ),
      );
    } else if (DevFlags.autoBench && _usesDownload) {
      unawaited(_download());
    } else {
      widget.downloadChanges?.addListener(_loadDownloaded);
      unawaited(_loadDownloaded());
    }
  }

  /// Loads the chat model from the Downloads tab, and loads again when the
  /// model, the search model or the package there changes.
  Future<void> _loadDownloaded() async {
    // Busy (loading or answering): look again shortly, so a change (a
    // removed publisher, say) is never skipped.
    if (_busy) {
      _reloadLater?.cancel();
      _reloadLater = Timer(const Duration(seconds: 1), _loadDownloaded);
      return;
    }
    final store = await DownloadStore.instance();
    // A LiteRT-LM load that never ended: it crashed the app last time.
    // Skip that model, or every start would crash again.
    if (store.loadingChat case final crashed? when !_loadedOnce) {
      store.failedChats.add(crashed);
      await store.setLoadingChat(null);
      _log({'event': 'chat_crashed_before', 'model': crashed});
    }
    _loadedOnce = true;
    final active = store.activeChat();
    final chat = active == null ? null : store.path(active, active.chatFile!);
    if (active == null || chat == null) {
      // The model is gone (deleted, or its publisher removed): stop using
      // what was loaded from Downloads, also on the base server.
      if (_loadedDownloads != null && mounted) {
        _loadedDownloads = null;
        setState(() {
          _answerer = null;
          _phase = _baseReady ? AskPhase.base : AskPhase.noModel;
          _status = '';
        });
        await _syncServer();
        // Not left in memory: a loaded model without guides would count
        // as "could not load the guides" rather than "no model" (#65).
        await _llm.close();
      }
      return;
    }
    final sig = [
      chat,
      store.embedModelPath(),
      for (final i in store.allInstalled(ItemKind.package))
        '${i.id}@${i.version}',
    ].join('|');
    if (sig == _loadedDownloads) return;
    _loadedDownloads = sig;
    final liteRt = isLiteRtFile(chat);
    if (liteRt) await store.setLoadingChat(active.id);
    final ok = await _run(
      () => _llm.loadFile(chat),
      afterLoad: true,
      chatDone: liteRt ? () => store.setLoadingChat(null) : null,
    );
    if (ok || !_chatFailed || !liteRt) return;
    // LiteRT-LM could not start the model: fall back to llama.cpp with the
    // next answer model (the GGUF one). Without one, the error stays.
    store.failedChats.add(active.id);
    if (store.chatModelPath() == null) {
      store.failedChats.remove(active.id);
      return;
    }
    _log({'event': 'chat_fallback', 'failed': active.id});
    await _llm.close();
    await _loadDownloaded();
  }

  /// Loads with [load], then the packages; false if it failed. [chatDone]
  /// runs once the chat is open or failed to open.
  Future<bool> _run(
    Future<void> Function() load, {
    bool afterLoad = false,
    Future<void> Function()? chatDone,
  }) async {
    setState(() {
      _loadingModel = true;
      _status = 'Loading model…';
      _phase = AskPhase.loading;
      // The guides loaded before go too: if this load fails after the
      // model, answers must not go on from the old set, which may hold a
      // package just removed (#65). Questions wait until it is done.
      _answerer = null;
    });
    var chatReady = false;
    try {
      try {
        await load();
        await _llm.newChat(systemInstruction: benchSystemInstruction);
        chatReady = true;
      } finally {
        await chatDone?.call();
      }
      if (!DevFlags.bare) {
        final store = await DownloadStore.instance();
        // The built-in packages (or newer downloads of them) plus every
        // other package installed from Downloads, searched together.
        // One broken or foreign file must not stop the app from answering
        // with the others: it is left out and logged.
        // Only Lychnion's packages (built in, or downloaded and signed by
        // Lychnion) supply the fixed official safety line; a publisher the
        // user added brings guides, not "official" lines (#66).
        KnowledgePackage? openOrSkip(
          String id,
          String path, {
          required bool safetyLines,
        }) {
          try {
            final p = KnowledgePackage.open(path);
            if (safetyLines || p.alerts.isEmpty) return p;
            _log({
              'event': 'package_alerts_ignored',
              'id': id,
              'alerts': p.alerts.length,
            });
            return p.withoutAlerts();
          } on Object catch (e) {
            _log({'event': 'package_skipped', 'id': id, 'error': '$e'});
            return null;
          }
        }

        // Bundled ids: Lychnion's download of them, else the bundled file;
        // never a copy of that id from an added publisher.
        final bundled = <KnowledgePackage>[];
        for (final id in bundledPackages) {
          final src = await store.bundledPackageSource(id, '$id.sqlite');
          if (src.shadowed case final who?) {
            _log({'event': 'package_shadow_ignored', 'id': id, 'by': who});
          }
          bundled.addAll([?openOrSkip(id, src.path, safetyLines: true)]);
        }
        final pkg = KnowledgePackage.merge([
          ...bundled,
          for (final i in store.allInstalled(ItemKind.package))
            if (!bundledPackages.contains(i.id) &&
                i.fileEnding('.sqlite') != null)
              ?openOrSkip(
                i.id,
                store.path(i, i.fileEnding('.sqlite')!),
                safetyLines: i.builtInPublisher,
              ),
        ]);
        HybridRetriever? hybrid;
        final embedPath = DevFlags.embedPath.isNotEmpty
            ? await resolvePath(DevFlags.embedPath)
            : store.embedModelPath();
        if (embedPath != null) {
          final sw = Stopwatch()..start();
          await _embedder.loadFile(embedPath);
          hybrid = HybridRetriever(
            pkg,
            _embedder,
            minCosine: double.parse(DevFlags.minCos),
            embedTexts: DevFlags.embedTexts,
          );
          await hybrid.index();
          _log({
            'event': 'indexed',
            'ms': sw.elapsedMilliseconds,
            'model': _embedder.modelName,
          });
        }
        // The app's own help, for questions about the app (lychnion#9).
        // Answers about hazards work without it.
        KnowledgePackage? help;
        HybridRetriever? helpHybrid;
        try {
          help = await AppHelp.load();
          if (hybrid != null) {
            helpHybrid = HybridRetriever(
              help,
              _embedder,
              minCosine: double.parse(DevFlags.minCos),
            );
            await helpHybrid.index();
          }
        } on Object catch (e) {
          _log({'event': 'help', 'error': '$e'});
        }
        _answerer = GroundedAnswerer(
          _llm,
          pkg,
          hybrid: hybrid,
          checkRelevance: DevFlags.relevanceCheck,
          topK: DevFlags.topK,
          help: help,
          helpHybrid: helpHybrid,
        );
        _log({
          'event': 'package',
          'id': pkg.id,
          'version': pkg.version,
          'passages': pkg.passages.length,
        });
        _packages = pkg.parts;
        if (mounted && widget.settings != null) {
          unawaited(showPackageNotices(context, widget.settings!, _packages));
        }
      }
      _log({
        'event': 'loaded',
        'load_ms': _llm.lastLoadTime?.inMilliseconds,
        'backend': _llm.backend,
      });
      await _syncServer();
      setState(() {
        _status =
            'Ready · ${_llm.backend} · loaded in ${_llm.lastLoadTime!.inMilliseconds} ms'
            '${_server != null ? ' · base server on port ${BaseServer.defaultPort}' : ''}';
        // A connected base still answers first.
        _phase = _server != null
            ? AskPhase.serving
            : (_baseReady ? AskPhase.base : AskPhase.ready);
      });
    } catch (e) {
      _chatFailed = !chatReady;
      setState(() {
        _status = 'Load failed: $e';
        // Also when only the last step failed: the bar and the phase
        // agree, and no answers come from a half-done load (#65).
        _answerer = null;
        // A connected base still answers: no red card then.
        _phase = _baseReady ? AskPhase.base : AskPhase.failed;
      });
      _log({'event': 'load_failed', 'error': '$e'});
      // No guides: a base server sharing the old ones stops (#65).
      try {
        await _syncServer();
      } on Object catch (e) {
        _log({'event': 'base_sync_failed', 'error': '$e'});
      }
      return false;
    } finally {
      setState(() => _loadingModel = false);
      _answerWaiting();
    }
    if (afterLoad && DevFlags.autoBench) await _bench();
    if (afterLoad && DevFlags.demoQuestions.isNotEmpty) {
      _startThread();
      for (final q in DevFlags.demoQuestions.split('|')) {
        await _ask(q.trim());
      }
      await widget.onDemoDone?.call(_entries);
    }
    return true;
  }

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Models', extensions: ['gguf', 'litertlm']),
      ],
    );
    if (file == null) return;
    // Copy into app storage so the sandboxed app can reopen it after restart.
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/models',
    );
    await dir.create(recursive: true);
    final target = File('${dir.path}/${file.name}');
    if (!await target.exists() ||
        await target.length() != await file.length()) {
      setState(() => _status = 'Copying model into app storage…');
      await File(file.path).copy(target.path);
    }
    await _run(() => _llm.loadFile(target.path));
  }

  Future<void> _download() => _run(
    () => _llm.loadUrl(
      _url.text.trim(),
      onProgress: (p) => setState(() => _status = 'Downloading model… $p%'),
    ),
    afterLoad: true,
  );

  Future<void> _bench() async {
    _current = _threads.create(); // results land in their own thread
    final results = <Map<String, Object?>>[];
    final hybrid = _answerer?.hybrid;
    if (hybrid != null) await _logRetrieval(hybrid);
    final questions = hybrid != null
        ? [for (final e in evalQuestions) e.text]
        : benchPrompts;
    for (final q in questions) {
      // A fresh chat per question, so answers do not depend on each other.
      if (DevFlags.bare) {
        await _llm.newChat(systemInstruction: benchSystemInstruction);
      }
      await _ask(q);
      results.add(_entries.last.toJson());
    }
    final dir = await exchangeDirectory();
    final out = File(
      '${dir.path}/lychnion-bench-${DevFlags.bare ? 'bare' : 'grounded'}-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await out.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'platform': defaultTargetPlatform.name,
        'mode': DevFlags.bare ? 'bare' : 'grounded',
        'relevance_check': DevFlags.relevanceCheck,
        'top_k': DevFlags.topK,
        'package': _answerer?.package.version,
        'backend': _llm.backend,
        'load_ms': _llm.lastLoadTime?.inMilliseconds,
        'results': results,
      }),
    );
    _log({'event': 'bench_done', 'file': out.path});
    setState(() => _status = 'Benchmark saved: ${out.path}');
  }

  /// Logs the ranking for every eval question, so the cut-off can be tuned.
  Future<void> _logRetrieval(HybridRetriever hybrid) async {
    for (final e in evalQuestions) {
      final ranked = await hybrid.rankAll(e.text);
      _log({
        'event': 'rank',
        'q': e.text,
        'lang': e.lang,
        'expected': e.expected,
        'top': [
          for (final h in ranked.take(6))
            {
              'source': h.passage.source.id,
              'id': h.passage.id,
              'cos': double.parse(h.cosine.toStringAsFixed(3)),
              'kw': double.parse(h.keyword.toStringAsFixed(1)),
            },
        ],
      });
    }
  }
}
