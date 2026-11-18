import 'package:flutter/foundation.dart';

import 'settings.dart';

/// Development flags, set with `--dart-define` (all optional):
///
///   --dart-define=GGUF_MODEL_PATH=/path/in/app/storage.gguf  load on start (docs:… = in Documents)
///                                                            a .litertlm file runs on LiteRT-LM
///                                                            instead of llama.cpp (spike)
///   --dart-define=GGUF_MODEL_URL=https://...gguf             download on start
///   --dart-define=AUTO_BENCH=true                            run the questions after loading
///   --dart-define=BARE=true                                  no package: the model answers alone (spike 1)
///   --dart-define=EMBED_MODEL_PATH=/path/in/app/storage.gguf  vector search (spike 3)
///   --dart-define=MIN_COS=0.5                                relevance cut-off for vector search (default 0.70)
///   --dart-define=CATALOG_URL=https://…/catalog.json         download catalog (Downloads tab)
///   --dart-define=DOWNLOAD_BASE_URL=http://host:port/        base for relative catalog URLs
///   --dart-define=MAP_PMTILES_PATH=/path/area.pmtiles        offline base map
///   --dart-define=MOCK_LOCATION=34.7376,135.3417             fixed position for testing
///   --dart-define=START_TAB=2                                open on the map (1: conversations)
///   --dart-define=SCREENSHOT_AFTER_S=20                      save a PNG of the app to Documents
///   --dart-define=BASE_SERVER=true                           answer phones on the local network (desktop)
///   --dart-define=BASE_NAME=…                                shown on phones
///   --dart-define=BASE_URL=http://192.168.1.20:8642          ask this base first (phone)
///   --dart-define=FACTS_EDIT=true                            enter facts on the map (on with BASE_SERVER)
///   --dart-define=DEMO_FACTS=true                            add made-up current facts (test data)
///   --dart-define=TOP_K=2                                    passages per answer (default 4)
///   --dart-define=LLM_BACKEND=gpu                            answer model on cpu or gpu (default: engine decides)
///   --dart-define=LLM_CONTEXT=2048                           model context in tokens (default 4096)
///   --dart-define=RELEVANCE_CHECK=true                       yes/no check before answering (spike 4)
///   --dart-define=ASK='q1|q2'                                ask these after loading, then save
///                                                            screenshots of the answers and the map
abstract final class DevFlags {
  static const modelPath = String.fromEnvironment('GGUF_MODEL_PATH');
  static const modelUrl = String.fromEnvironment(
    'GGUF_MODEL_URL',
    defaultValue: 'https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_0.gguf',
  );
  static const autoBench = bool.fromEnvironment('AUTO_BENCH');
  static const bare = bool.fromEnvironment('BARE');
  static const embedPath = String.fromEnvironment('EMBED_MODEL_PATH');
  static const minCos = String.fromEnvironment('MIN_COS', defaultValue: '0.70');
  static const mapPmtiles = String.fromEnvironment('MAP_PMTILES_PATH');
  static const mockLocation = String.fromEnvironment('MOCK_LOCATION');
  static const startTab = int.fromEnvironment('START_TAB');
  static const screenshotAfter = int.fromEnvironment('SCREENSHOT_AFTER_S');
  static const demoQuestions = String.fromEnvironment('ASK');
  static const relevanceCheck = bool.fromEnvironment('RELEVANCE_CHECK');
  static const topK = int.fromEnvironment('TOP_K', defaultValue: 4);
  // The old SHELTER_* names still work.
  static const baseServer =
      bool.fromEnvironment('BASE_SERVER') ||
      bool.fromEnvironment('SHELTER_SERVER');
  static const baseName = String.fromEnvironment(
    'BASE_NAME',
    defaultValue: String.fromEnvironment(
      'SHELTER_NAME',
      defaultValue: 'Lychnion base',
    ),
  );
  static const baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: String.fromEnvironment('SHELTER_URL'),
  );
  static const demoFacts = bool.fromEnvironment('DEMO_FACTS');
  static const factsEdit = bool.fromEnvironment('FACTS_EDIT');
}

/// Computers can share on the local network (phones: later).
bool get isDesktop => switch (defaultTargetPlatform) {
  TargetPlatform.macOS ||
  TargetPlatform.windows ||
  TargetPlatform.linux => true,
  _ => false,
};

/// Sharing on the local network: the switch in Settings, or the
/// BASE_SERVER flag for development.
bool sharingOn(AppSettings? s) =>
    DevFlags.baseServer || (isDesktop && (s?.sharing ?? false));
String sharingName(AppSettings? s) => s?.sharingName ?? DevFlags.baseName;
