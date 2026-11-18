import 'dart:async';
import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart' as edge;
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:flutter_edge_ai_llama/flutter_edge_ai_llama.dart';

/// Timing and memory figures for one answer.
class AnswerStats {
  AnswerStats({
    required this.timeToFirstToken,
    required this.total,
    required this.outputTokens,
    required this.inputTokens,
    required this.rssBytes,
  });

  final Duration timeToFirstToken;
  final Duration total;
  final int outputTokens;
  final int inputTokens;
  final int rssBytes;

  double get tokensPerSecond {
    final gen = total - timeToFirstToken;
    if (outputTokens <= 1 || gen.inMilliseconds <= 0) return 0;
    return (outputTokens - 1) / (gen.inMilliseconds / 1000);
  }

  Map<String, Object> toJson() => {
    'ttft_ms': timeToFirstToken.inMilliseconds,
    'total_ms': total.inMilliseconds,
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    'tokens_per_s': double.parse(tokensPerSecond.toStringAsFixed(1)),
    'rss_mb': rssBytes ~/ (1024 * 1024),
  };
}

/// The one place the app talks to the on-device model.
///
/// Kept small on purpose so the engine can be swapped without touching the
/// UI. The file decides the engine: a `.gguf` runs on llama.cpp (the
/// default), a `.litertlm` on Google's LiteRT-LM (spike: about twice as
/// fast on an Android phone's CPU, needs Android 11; see
/// docs/device-results.md).
/// Developer flag `--dart-define=LLM_BACKEND=cpu|gpu`: which processor
/// runs the answer model. Unset: the engine decides (as before). A GPU the
/// device lacks falls back to the CPU; `backend` says what was used.
const _llmBackend = String.fromEnvironment('LLM_BACKEND');
final _preferredBackend = switch (_llmBackend) {
  'cpu' => edge.PreferredBackend.cpu,
  'gpu' => edge.PreferredBackend.gpu,
  _ => null,
};

/// Developer flag `--dart-define=LLM_CONTEXT=2048`: the model's context in
/// tokens (prompt plus answer; default 4096). On the GPU, LiteRT-LM runs
/// Gemma 4 with 32-bit numbers above 2048 and with faster 16-bit ones at
/// 2048 or less. Overrides the context a caller passes.
const _llmContext = int.fromEnvironment('LLM_CONTEXT');

class LocalLlm {
  edge.InferenceModel? _model;
  edge.InferenceChat? _chat;
  Duration? lastLoadTime;

  /// Registers the engines: llama.cpp for chat and for embeddings,
  /// LiteRT-LM for `.litertlm` chat models.
  static Future<void> init() => edge.FlutterEdgeAi.initialize(
    inferenceEngines: [const LlamaEngineProvider(), LiteRtLmEngine()],
    embeddingBackends: const [LlamaEmbeddingBackend()],
  );

  /// The model type the chat is opened with (set when loading).
  var _modelType = edge.ModelType.general;

  bool get isLoaded => _model != null;
  String get backend => _model?.activeBackend?.name.toUpperCase() ?? '-';

  /// Loads a model file that is already in app storage: GGUF (llama.cpp)
  /// or `.litertlm` (LiteRT-LM).
  Future<void> loadFile(String path, {int contextTokens = 4096}) =>
      _load(contextTokens, (i) => i.fromFile(path), path: path);

  /// Downloads a GGUF file once (Android, iOS), then loads it.
  Future<void> loadUrl(
    String url, {
    int contextTokens = 4096,
    void Function(int percent)? onProgress,
  }) => _load(contextTokens, (i) {
    final b = i.fromNetwork(url);
    return onProgress == null ? b : b.withProgress(onProgress);
  }, path: Uri.parse(url).path);

  Future<void> _load(
    int contextTokens,
    edge.InferenceInstallationBuilder Function(
      edge.InferenceInstallationBuilder,
    )
    source, {
    required String path,
  }) async {
    await close();
    final sw = Stopwatch()..start();
    final liteRt = path.toLowerCase().endsWith('.litertlm');
    // LiteRT-LM reads the chat template from the file, but the type picks
    // the order of media and the turn markers; all our .litertlm models
    // are Gemma 4.
    _modelType = liteRt ? edge.ModelType.gemma4 : edge.ModelType.general;
    final installation = edge.FlutterEdgeAi.installModel(
      modelType: _modelType,
      fileType: liteRt ? edge.ModelFileType.litertlm : edge.ModelFileType.gguf,
    );
    await source(installation).install();
    _model = await edge.FlutterEdgeAi.getActiveModel(
      maxTokens: _llmContext > 0 ? _llmContext : contextTokens,
      preferredBackend: _preferredBackend,
    );
    lastLoadTime = sw.elapsed;
  }

  Future<void> newChat({
    required String systemInstruction,
    int maxOutputTokens = 512,
  }) async {
    await _chat?.close();
    _chat = await _model!.openChat(
      systemInstruction: systemInstruction,
      modelType: _modelType,
      temperature: .3,
      topK: 40,
      topP: .9,
      maxOutputTokens: maxOutputTokens,
    );
  }

  /// Streams the answer. [onDone] gets the figures after the last token.
  Stream<String> ask(
    String prompt, {
    void Function(AnswerStats)? onDone,
  }) async* {
    final chat = _chat;
    if (chat == null) throw StateError('No chat. Load a model first.');
    final sw = Stopwatch()..start();
    Duration? first;
    var tokens = 0;
    await chat.addQueryChunk(edge.Message.text(text: prompt, isUser: true));
    // Thinking is off (openChat default), but some models (Qwen3) may still
    // emit a <think>…</think> block; drop it from the answer.
    var thinking = false;
    await for (final r in chat.generateChatResponseAsync()) {
      if (r is edge.TextResponse) {
        first ??= sw.elapsed;
        tokens++;
        final t = r.token;
        if (t.contains('<think>')) thinking = true;
        if (thinking) {
          if (t.contains('</think>')) {
            thinking = false;
            final rest = t.split('</think>').last.trimLeft();
            if (rest.isNotEmpty) yield rest;
          }
          continue;
        }
        yield t;
      }
    }
    final m = chat.session.getSessionMetrics();
    onDone?.call(
      AnswerStats(
        timeToFirstToken: first ?? sw.elapsed,
        total: sw.elapsed,
        outputTokens: m.outputTokens > 0 ? m.outputTokens : tokens,
        inputTokens: m.inputTokens,
        rssBytes: ProcessInfo.currentRss,
      ),
    );
  }

  Future<void> stop() async => _chat?.session.stopGeneration();

  Future<void> close() async {
    await _chat?.close();
    _chat = null;
    await _model?.close();
    _model = null;
  }
}
