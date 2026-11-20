part of 'ask_page.dart';

/// Phone side: connects to a base, checks its key and keeps its
/// current facts in step.
mixin _BaseConnection on _AskPageBase {
  Timer? _retry;

  String? get _wantedBase =>
      DevFlags.baseUrl.isNotEmpty ? DevFlags.baseUrl : widget.settings?.baseUrl;

  /// Connects, switches or disconnects when the saved base changes.
  void _baseChanged() {
    final want = _wantedBase;
    final key = widget.settings?.baseKey;
    // A key pinned for the same address connects again, to check it.
    if (want == _base?.url && key == _baseKeyUsed) return;
    _baseKeyUsed = key;
    _factsTimer?.cancel();
    _retry?.cancel();
    _base?.close();
    _base = want == null ? null : BaseClient(want);
    setState(() {
      _baseReady = false;
      if (_phase == AskPhase.base) {
        _phase = _llm.isLoaded ? AskPhase.ready : AskPhase.noModel;
      }
    });
    if (_base != null) unawaited(_connectBase());
  }

  /// The pinned key the current connection was checked against.
  String? _baseKeyUsed;

  Timer? _factsTimer;

  Future<void> _pullFacts() async {
    final store = widget.facts;
    if (store == null) return;
    try {
      final base = _base;
      if (base == null) return;
      final added = await store.addAll(await base.facts());
      _log({'event': 'facts_pulled', 'new': added});
    } catch (e) {
      _log({'event': 'facts_failed', 'error': '$e'});
    }
  }

  /// Checks the base's key against the one from its link: a computer with
  /// another key is refused (someone else at that address). Its facts are
  /// verified only once the user compared the key's code in person
  /// (lychnion/lychnion#63); until then, and for a base connected by its
  /// address or found on the Wi-Fi, it gives answers and downloads
  /// (checked by signature anyway), and its facts stay unconfirmed.
  Future<bool> _checkBaseKey(Map<String, dynamic> info) async {
    final check = checkBaseKey(
      info,
      pinned: widget.settings?.baseKey,
      trust: widget.facts?.trust,
    );
    _log({'event': check.logEvent});
    if (!check.connects) {
      setState(() {
        _status = 'Base key does not match its link: not connected.';
        _phase = _llm.isLoaded ? AskPhase.ready : AskPhase.noModel;
      });
    }
    return check.connects;
  }

  Future<void> _connectBase() async {
    final base = _base;
    if (base == null) return;
    try {
      final info = await base.info();
      if (!identical(base, _base)) return; // switched meanwhile
      if (!await _checkBaseKey(info)) return;
      // Only what the app knows, cleaned: the rest of /info is the base's.
      final model = info['model'];
      final shownModel = cleanShownText(model is String ? model : null);
      _log({
        'event': 'base_connected',
        'name': base.name,
        'model': shownModel,
        'answers': info['answers'] == true,
      });
      await _pullFacts();
      // Packages, maps and models the base can pass on (signed records).
      widget.onBaseCatalog?.call(Uri.parse(base.url).resolve('/catalog.json'));
      // Keep current facts in step with the base while connected.
      _factsTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(_pullFacts()),
      );
      setState(() {
        _baseReady = true;
        _status = 'Connected to base: ${base.name} ($shownModel)';
        _phase = AskPhase.base;
      });
      _answerWaiting();
      if (DevFlags.modelPath.isEmpty && DevFlags.demoQuestions.isNotEmpty) {
        _startThread();
        for (final q in DevFlags.demoQuestions.split('|')) {
          await _ask(q.trim());
        }
        await widget.onDemoDone?.call(_entries);
      }
    } catch (e) {
      _log({'event': 'base_unreachable', 'error': '$e'});
      if (!mounted || !identical(base, _base)) return;
      setState(() => _status = 'Base not reachable: $e');
      // The phone may join the base Wi-Fi later: try again.
      _retry = Timer(const Duration(seconds: 30), () {
        if (identical(base, _base)) unawaited(_connectBase());
      });
    }
  }
}
