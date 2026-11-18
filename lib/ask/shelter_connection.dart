part of 'ask_page.dart';

/// Phone side: connects to a shelter base, checks its key and keeps its
/// current facts in step.
mixin _ShelterConnection on _AskPageBase {
  Timer? _retry;

  String? get _wantedShelter => DevFlags.shelterUrl.isNotEmpty
      ? DevFlags.shelterUrl
      : widget.settings?.shelterUrl;

  /// Connects, switches or disconnects when the saved shelter changes.
  void _shelterChanged() {
    final want = _wantedShelter;
    final key = widget.settings?.shelterKey;
    // A key pinned for the same address connects again, to check it.
    if (want == _shelter?.baseUrl && key == _shelterKeyUsed) return;
    _shelterKeyUsed = key;
    _factsTimer?.cancel();
    _retry?.cancel();
    _shelter?.close();
    _shelter = want == null ? null : ShelterClient(want);
    setState(() {
      _shelterReady = false;
      if (_phase == AskPhase.shelter) {
        _phase = _llm.isLoaded ? AskPhase.ready : AskPhase.noModel;
      }
    });
    if (_shelter != null) unawaited(_connectShelter());
  }

  /// The pinned key the current connection was checked against.
  String? _shelterKeyUsed;

  Timer? _factsTimer;

  Future<void> _pullFacts() async {
    final store = widget.facts;
    if (store == null) return;
    try {
      final shelter = _shelter;
      if (shelter == null) return;
      final added = await store.addAll(await shelter.facts());
      _log({'event': 'facts_pulled', 'new': added});
    } catch (e) {
      _log({'event': 'facts_failed', 'error': '$e'});
    }
  }

  /// Trusts the shelter's signing key, only when it came from its QR code
  /// (checked in person): a computer with another key is refused (someone
  /// else at that address). A base connected by its address or found on
  /// the Wi-Fi gives answers and downloads (checked by signature anyway),
  /// but its facts stay unverified until its QR code is scanned.
  Future<bool> _trustShelterKey(Map<String, dynamic> info) async {
    final key = info['key'] as String?;
    final expected = widget.settings?.shelterKey;
    final trust = widget.facts?.trust;
    if (expected == null) {
      _log({'event': 'shelter_key_not_pinned'});
      return true;
    }
    if (key != expected) {
      _log({'event': 'shelter_key_mismatch'});
      setState(() {
        _status = 'Base key does not match the QR code: not connected.';
        _phase = _llm.isLoaded ? AskPhase.ready : AskPhase.noModel;
      });
      return false;
    }
    if (trust != null) {
      await trust.add(expected, _shelter?.name ?? 'base');
      // Facts pulled before the QR code was scanned.
      await widget.facts?.reverify();
    }
    return true;
  }

  Future<void> _connectShelter() async {
    final shelter = _shelter;
    if (shelter == null) return;
    try {
      final info = await shelter.info();
      if (!identical(shelter, _shelter)) return; // switched meanwhile
      if (!await _trustShelterKey(info)) return;
      // Only what the app knows, cleaned: the rest of /info is the base's.
      final model = info['model'];
      final shownModel = cleanShownText(model is String ? model : null);
      _log({
        'event': 'shelter_connected',
        'name': shelter.name,
        'model': shownModel,
        'answers': info['answers'] == true,
      });
      await _pullFacts();
      // Packages, maps and models the shelter can pass on (signed records).
      widget.onShelterCatalog?.call(
        Uri.parse(shelter.baseUrl).resolve('/catalog.json'),
      );
      // Keep current facts in step with the shelter while connected.
      _factsTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(_pullFacts()),
      );
      setState(() {
        _shelterReady = true;
        _status = 'Connected to base: ${shelter.name} ($shownModel)';
        _phase = AskPhase.shelter;
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
      _log({'event': 'shelter_unreachable', 'error': '$e'});
      if (!mounted || !identical(shelter, _shelter)) return;
      setState(() => _status = 'Base not reachable: $e');
      // The phone may join the shelter Wi-Fi later: try again.
      _retry = Timer(const Duration(seconds: 30), () {
        if (identical(shelter, _shelter)) unawaited(_connectShelter());
      });
    }
  }
}
