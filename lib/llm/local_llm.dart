import 'dart:async';
import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart' as edge;
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
/// Kept small on purpose so the engine (flutter_edge_ai + llama.cpp today)
/// can be swapped without touching the UI.
class LocalLlm {
  edge.InferenceModel? _model;
  edge.InferenceChat? _chat;
  Duration? lastLoadTime;

  /// Registers the llama.cpp engine for chat and for embeddings.
  static Future<void> init() => edge.FlutterEdgeAi.initialize(
    inferenceEngines: const [LlamaEngineProvider()],
    embeddingBackends: const [LlamaEmbeddingBackend()],
  );

  bool get isLoaded => _model != null;
  String get backend => _model?.activeBackend?.name.toUpperCase() ?? '-';

  /// Loads a GGUF file that is already in app storage.
  Future<void> loadFile(String path, {int contextTokens = 4096}) =>
      _load(contextTokens, (i) => i.fromFile(path));

  /// Downloads a GGUF file once (Android, iOS), then loads it.
  Future<void> loadUrl(
    String url, {
    int contextTokens = 4096,
    void Function(int percent)? onProgress,
  }) => _load(contextTokens, (i) {
    final b = i.fromNetwork(url);
    return onProgress == null ? b : b.withProgress(onProgress);
  });

  Future<void> _load(
    int contextTokens,
    edge.InferenceInstallationBuilder Function(
      edge.InferenceInstallationBuilder,
    )
    source,
  ) async {
    await close();
    final sw = Stopwatch()..start();
    final installation = edge.FlutterEdgeAi.installModel(
      modelType: edge.ModelType.general,
      fileType: edge.ModelFileType.gguf,
    );
    await source(installation).install();
    _model = await edge.FlutterEdgeAi.getActiveModel(maxTokens: contextTokens);
    lastLoadTime = sw.elapsed;
  }

  Future<void> newChat({
    required String systemInstruction,
    int maxOutputTokens = 512,
  }) async {
    await _chat?.close();
    _chat = await _model!.createChat(
      systemInstruction: systemInstruction,
      modelType: edge.ModelType.general,
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
    // Thinking is off (createChat default), but some models (Qwen3) may still
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
