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

  /// Trusts the base's signing key, only when it came from its QR code
  /// (checked in person): a computer with another key is refused (someone
  /// else at that address). A base connected by its address or found on
  /// the Wi-Fi gives answers and downloads (checked by signature anyway),
  /// but its facts stay unverified until its QR code is scanned.
  Future<bool> _trustBaseKey(Map<String, dynamic> info) async {
    final key = info['key'] as String?;
    final expected = widget.settings?.baseKey;
    final trust = widget.facts?.trust;
    if (expected == null) {
      _log({'event': 'base_key_not_pinned'});
      return true;
    }
    if (key != expected) {
      _log({'event': 'base_key_mismatch'});
      setState(() {
        _status = 'Base key does not match the QR code: not connected.';
        _phase = _llm.isLoaded ? AskPhase.ready : AskPhase.noModel;
      });
      return false;
    }
    if (trust != null) {
      await trust.add(expected, _base?.name ?? 'base');
      // Facts pulled before the QR code was scanned.
      await widget.facts?.reverify();
    }
    return true;
  }

  Future<void> _connectBase() async {
    final base = _base;
    if (base == null) return;
    try {
      final info = await base.info();
      if (!identical(base, _base)) return; // switched meanwhile
      if (!await _trustBaseKey(info)) return;
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
