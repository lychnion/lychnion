import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'knowledge/grounded_answer.dart';
import 'knowledge/knowledge_package.dart';
import 'llm/local_llm.dart';
import 'spike/bench_prompts.dart';
import 'ui/answer_card.dart';

/// Spike app: load a GGUF model, chat with it, and time a fixed question set.
///
/// Dev flags (all optional):
///   --dart-define=GGUF_MODEL_PATH=/path/in/app/storage.gguf  load on start
///   --dart-define=GGUF_MODEL_URL=https://...gguf             download on start
///   --dart-define=AUTO_BENCH=true                            run the questions after loading
///   --dart-define=BARE=true                                  no package: the model answers alone (spike 1)
const _modelPath = String.fromEnvironment('GGUF_MODEL_PATH');
const _modelUrl = String.fromEnvironment(
  'GGUF_MODEL_URL',
  defaultValue:
      'https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_0.gguf',
);
const _autoBench = bool.fromEnvironment('AUTO_BENCH');
const _bare = bool.fromEnvironment('BARE');
const _packageAsset = 'jp.bousai.core.sqlite';

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
    home: const SpikePage(),
  );
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final _llm = LocalLlm();
  final _input = TextEditingController();
  final _url = TextEditingController(text: _modelUrl);
  final _entries = <GroundedAnswer>[];
  GroundedAnswerer? _answerer;
  String _status = 'No model loaded.';
  bool _busy = false;

  bool get _usesDownload =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    if (_modelPath.isNotEmpty) {
      unawaited(_run(() => _llm.loadFile(_modelPath), afterLoad: true));
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
        _answerer = GroundedAnswerer(_llm, pkg);
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
    for (final q in benchPrompts) {
      // A fresh chat per question, so answers do not depend on each other.
      if (_bare) await _llm.newChat(systemInstruction: benchSystemInstruction);
      await _ask(q);
      results.add(_entries.last.toJson());
    }
    final dir = await getApplicationDocumentsDirectory();
    final out = File(
      '${dir.path}/fieldkit-bench-${_bare ? 'bare' : 'grounded'}-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await out.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'platform': defaultTargetPlatform.name,
        'mode': _bare ? 'bare' : 'grounded',
        'package': _answerer?.package.version,
        'backend': _llm.backend,
        'load_ms': _llm.lastLoadTime?.inMilliseconds,
        'results': results,
      }),
    );
    _log({'event': 'bench_done', 'file': out.path});
    setState(() => _status = 'Benchmark saved: ${out.path}');
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
              itemBuilder: (_, i) => AnswerCard(
                answer: _entries[i],
                grounded: _answerer != null,
                done: !_busy || i < _entries.length - 1,
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
