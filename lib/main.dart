import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import 'knowledge/grounded_answer.dart';
import 'knowledge/hybrid_retriever.dart';
import 'knowledge/knowledge_package.dart';
import 'llm/local_embedder.dart';
import 'map/map_screen.dart';
import 'map/hazard_detect.dart';
import 'map/map_state.dart';
import 'llm/local_llm.dart';
import 'spike/bench_prompts.dart';
import 'spike/eval_questions.dart';
import 'ui/answer_card.dart';
import 'util/paths.dart';

/// Spike app: load a GGUF model, chat with it, and time a fixed question set.
///
/// Dev flags (all optional):
///   --dart-define=GGUF_MODEL_PATH=/path/in/app/storage.gguf  load on start (docs:… = in Documents)
///   --dart-define=GGUF_MODEL_URL=https://...gguf             download on start
///   --dart-define=AUTO_BENCH=true                            run the questions after loading
///   --dart-define=BARE=true                                  no package: the model answers alone (spike 1)
///   --dart-define=EMBED_MODEL_PATH=/path/in/app/storage.gguf  vector search (spike 3)
///   --dart-define=MIN_COS=0.5                                relevance cut-off for vector search
///   --dart-define=MAP_PMTILES_PATH=/path/area.pmtiles        offline base map
///   --dart-define=MOCK_LOCATION=34.7376,135.3417             fixed position for testing
///   --dart-define=START_TAB=1                                open on the map
///   --dart-define=SCREENSHOT_AFTER_S=20                      save a PNG of the app to Documents
///   --dart-define=RELEVANCE_CHECK=true                       yes/no check before answering (spike 4)
///   --dart-define=ASK='q1|q2'                                ask these after loading, then save
///                                                            screenshots of the answers and the map
const _modelPath = String.fromEnvironment('GGUF_MODEL_PATH');
const _modelUrl = String.fromEnvironment(
  'GGUF_MODEL_URL',
  defaultValue:
      'https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_0.gguf',
);
const _autoBench = bool.fromEnvironment('AUTO_BENCH');
const _bare = bool.fromEnvironment('BARE');
const _packageAsset = 'jp.bousai.core.sqlite';
const _embedPath = String.fromEnvironment('EMBED_MODEL_PATH');
const _minCos = String.fromEnvironment('MIN_COS', defaultValue: '0');
const _mapPmtiles = String.fromEnvironment('MAP_PMTILES_PATH');
const _mockLocation = String.fromEnvironment('MOCK_LOCATION');
const _mapSitesAsset = 'jp.map.nishinomiya.sites.sqlite';
const _startTab = int.fromEnvironment('START_TAB');
const _screenshotAfter = int.fromEnvironment('SCREENSHOT_AFTER_S');
const _demoQuestions = String.fromEnvironment('ASK');
const _relevanceCheck = bool.fromEnvironment('RELEVANCE_CHECK');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalLlm.init();
  runApp(const FieldkitApp());
}

class FieldkitApp extends StatelessWidget {
  const FieldkitApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'fieldkit',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const HomePage(),
  );
}

/// Two tabs: ask (the spike screen) and the offline map.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = _startTab;
  final _shotKey = GlobalKey();

  /// Map data and position, shared by the answers and the map tab.
  final MapState? _map = _mapPmtiles.isEmpty
      ? null
      : MapState(
          pmtilesPath: _mapPmtiles,
          sitesAsset: _mapSitesAsset,
          mockLocation: _mockLocation,
        );

  @override
  void initState() {
    super.initState();
    unawaited(_map?.load());
    if (_screenshotAfter > 0) {
      Timer(const Duration(seconds: _screenshotAfter), _saveScreenshot);
    }
  }

  /// Demo run: screenshot the answers, then the map at the suggested site.
  Future<void> _demoDone(List<GroundedAnswer> answers) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    await _saveScreenshot();
    final map = _map;
    if (map == null) return;
    for (final a in answers) {
      final h = hazardFor(a.question, a.alerts);
      final near = map.nearest(h, limit: 1);
      if (h == null || near.isEmpty) continue;
      map.showOnMap(h, near.first.site.point);
      setState(() => _tab = 1);
      await Future<void>.delayed(const Duration(seconds: 10));
      await _saveScreenshot();
      return;
    }
  }

  // Dev aid: lets scripts see the app without screen-recording rights.
  Future<void> _saveScreenshot() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = await exchangeDirectory();
    final file = File(
      '${dir.path}/fieldkit-screenshot-${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(png!.buffer.asUint8List());
    debugPrint(
      'FIELDKIT ${jsonEncode({'event': 'screenshot', 'file': file.path})}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final en = Localizations.localeOf(context).languageCode != 'ja';
    return RepaintBoundary(
      key: _shotKey,
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            SpikePage(
              map: _map,
              onShowOnMap: () => setState(() => _tab = 1),
              onDemoDone: _demoDone,
            ),
            Scaffold(
              appBar: AppBar(title: Text(en ? 'Map' : '地図')),
              body: _map == null
                  ? const Center(
                      child: Text('Set MAP_PMTILES_PATH to a .pmtiles file.'),
                    )
                  : MapScreen(state: _map, english: en),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.chat_outlined),
              label: en ? 'Ask' : '質問',
            ),
            NavigationDestination(
              icon: const Icon(Icons.map_outlined),
              label: en ? 'Map' : '地図',
            ),
          ],
        ),
      ),
    );
  }
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key, this.map, this.onShowOnMap, this.onDemoDone});

  final MapState? map;
  final void Function()? onShowOnMap;
  final Future<void> Function(List<GroundedAnswer>)? onDemoDone;

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final _llm = LocalLlm();
  final _input = TextEditingController();
  final _url = TextEditingController(text: _modelUrl);
  final _entries = <GroundedAnswer>[];
  GroundedAnswerer? _answerer;
  final _embedder = LocalEmbedder();
  String _status = 'No model loaded.';
  bool _busy = false;

  bool get _usesDownload =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (_modelPath.isNotEmpty) {
      unawaited(
        _run(
          () async => _llm.loadFile(await resolvePath(_modelPath)),
          afterLoad: true,
        ),
      );
    } else if (_autoBench && _usesDownload) {
      unawaited(_download());
    }
  }

  Future<void> _run(
    Future<void> Function() load, {
    bool afterLoad = false,
  }) async {
    setState(() {
      _busy = true;
      _status = 'Loading model…';
    });
    try {
      await load();
      await _llm.newChat(systemInstruction: benchSystemInstruction);
      if (!_bare) {
        final pkg = await KnowledgePackage.fromAsset(_packageAsset);
        HybridRetriever? hybrid;
        if (_embedPath.isNotEmpty) {
          final sw = Stopwatch()..start();
          await _embedder.loadFile(await resolvePath(_embedPath));
          hybrid = HybridRetriever(
            pkg,
            _embedder,
            minCosine: double.parse(_minCos),
          );
          await hybrid.index();
          _log({
            'event': 'indexed',
            'ms': sw.elapsedMilliseconds,
            'model': _embedder.modelName,
          });
        }
        _answerer = GroundedAnswerer(
          _llm,
          pkg,
          hybrid: hybrid,
          checkRelevance: _relevanceCheck,
        );
        _log({
          'event': 'package',
          'id': pkg.id,
          'version': pkg.version,
          'passages': pkg.passages.length,
        });
      }
      _log({
        'event': 'loaded',
        'load_ms': _llm.lastLoadTime?.inMilliseconds,
        'backend': _llm.backend,
      });
      setState(
        () => _status =
            'Ready · ${_llm.backend} · loaded in ${_llm.lastLoadTime!.inMilliseconds} ms',
      );
    } catch (e) {
      setState(() => _status = 'Load failed: $e');
      _log({'event': 'load_failed', 'error': '$e'});
      return;
    } finally {
      setState(() => _busy = false);
    }
    if (afterLoad && _autoBench) await _bench();
    if (afterLoad && _demoQuestions.isNotEmpty) {
      for (final q in _demoQuestions.split('|')) {
        await _ask(q.trim());
      }
      await widget.onDemoDone?.call(_entries);
    }
  }

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'GGUF models', extensions: ['gguf']),
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

  Future<void> _ask(String question) async {
    final entry = GroundedAnswer(question);
    setState(() {
      _busy = true;
      _entries.add(entry);
    });
    try {
      final answerer = _answerer;
      if (answerer != null) {
        await answerer.answer(entry, () => setState(() {}));
      } else {
        await for (final t in _llm.ask(
          question,
          onDone: (s) => entry.stats = s,
        )) {
          entry.text += t;
          setState(() {});
        }
      }
      _log({'event': 'answer', ...entry.toJson()});
    } catch (e) {
      entry.text += '\n[error: $e]';
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _bench() async {
    final results = <Map<String, Object?>>[];
    final hybrid = _answerer?.hybrid;
    if (hybrid != null) await _logRetrieval(hybrid);
    final questions = hybrid != null
        ? [for (final e in evalQuestions) e.text]
        : benchPrompts;
    for (final q in questions) {
      // A fresh chat per question, so answers do not depend on each other.
      if (_bare) await _llm.newChat(systemInstruction: benchSystemInstruction);
      await _ask(q);
      results.add(_entries.last.toJson());
    }
    final dir = await exchangeDirectory();
    final out = File(
      '${dir.path}/fieldkit-bench-${_bare ? 'bare' : 'grounded'}-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await out.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'platform': defaultTargetPlatform.name,
        'mode': _bare ? 'bare' : 'grounded',
        'relevance_check': _relevanceCheck,
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

  void _log(Map<String, Object?> data) =>
      debugPrint('FIELDKIT ${jsonEncode(data)}');

  @override
  Widget build(BuildContext context) {
    final ready = _llm.isLoaded && !_busy;
    return Scaffold(
      appBar: AppBar(title: const Text('fieldkit · spike')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_usesDownload) ...[
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _url,
                      decoration: const InputDecoration(labelText: 'GGUF URL'),
                    ),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _download,
                    child: const Text('Download model'),
                  ),
                ] else
                  FilledButton(
                    onPressed: _busy ? null : _pickFile,
                    child: const Text('Load GGUF file'),
                  ),
                OutlinedButton(
                  onPressed: ready ? _bench : null,
                  child: const Text('Run test questions'),
                ),
                if (_busy)
                  TextButton(onPressed: _llm.stop, child: const Text('Stop')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(alignment: Alignment.centerLeft, child: Text(_status)),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _entries.length,
              itemBuilder: (_, i) => ListenableBuilder(
                // Rebuild when the map data or position arrives.
                listenable: widget.map ?? ValueNotifier(0),
                builder: (_, _) => AnswerCard(
                  answer: _entries[i],
                  grounded: _answerer != null,
                  done: !_busy || i < _entries.length - 1,
                  map: widget.map,
                  onShowOnMap: widget.onShowOnMap,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: ready,
                      decoration: const InputDecoration(
                        hintText: '質問を入力 / Ask a question',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    onPressed: ready ? _send : null,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _send() {
    final q = _input.text.trim();
    if (q.isEmpty) return;
    _input.clear();
    unawaited(_ask(q));
  }
}
