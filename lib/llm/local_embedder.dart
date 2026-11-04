import 'package:flutter_edge_ai/flutter_edge_ai.dart' as edge;

/// The on-device embedding model (EmbeddingGemma 2, multilingual).
///
/// Separate from the chat model: both stay loaded.
class LocalEmbedder {
  edge.EmbeddingModel? _model;
  String modelName = '';

  bool get isLoaded => _model != null;

  Future<void> loadFile(String path) async {
    await close();
    await edge.FlutterEdgeAi.installEmbedder().modelFromFile(path).install();
    _model = await edge.FlutterEdgeAi.getActiveEmbedder();
    modelName = path.split('/').last;
  }

  Future<List<double>> query(String text) => _model!.embed(
    edge.EmbeddingInput.text(text),
    taskType: edge.TaskType.retrievalQuery,
  );

  Future<List<List<double>>> documents(List<String> texts) => _model!.embedAll([
    for (final t in texts) edge.EmbeddingInput.text(t),
  ], taskType: edge.TaskType.retrievalDocument);

  Future<void> close() async {
    await _model?.close();
    _model = null;
  }
}
