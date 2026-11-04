# fieldkit

Proof of concept for an offline AI helper for disaster preparedness and the
outdoors in Japan. One Flutter codebase for iOS, Android, macOS and Windows.
Everything runs on the device; the network is only needed to download models.

"fieldkit" is a code name. The public name is still open (see
[docs/poc-plan.md](docs/poc-plan.md), section 0).

## Status

- Spike 1 ([results](docs/spike-1-results.md)): Gemma 4 E2B (GGUF) runs on
  the device through [flutter_edge_ai](https://pub.dev/packages/flutter_edge_ai)
  and its llama.cpp engine.
- Spike 2 ([results](docs/spike-2-results.md)): answers only from a small
  Bousai package of official sources, with checked citations and fixed
  safety lines.
- Spike 3 ([results](docs/spike-3-results.md)): vector search
  (EmbeddingGemma 2), relevance cut-off, questions in Japanese and English.
- Spike 4 ([results](docs/spike-4-results.md)): near-topic answers; volcano
  page added, "partly covered" label; a yes/no self-check did not work with
  the 2B model.
- Spike 5 ([results](docs/spike-5-results.md)): Gemma 4 E4B for desktop
  (better answers, half the speed); OCR'd bear source disabled after it
  inverted advice.
- Spike 6 ([results](docs/spike-6-results.md)): checked sources for bears
  and getting lost (政府広報オンライン), two more safety lines; 28 / 28
  covered, 9 / 9 uncovered.
- Shelter computer ([results](docs/shelter-results.md)): the desktop app
  answers phones on the local network (E4B); a Pixel 5a with no model gets
  answers in 2.5 s instead of 48 s.
- Real devices ([results](docs/device-results.md)): iPad Air 5 (M1) runs
  the full app offline: about 22 tokens/s, answers in 2 to 9 s, same answers
  as on the Mac. Pixel 5a (2021, 6 GB): same quality but about 48 s per
  answer on the CPU, and memory is borderline.
- Offline map ([results](docs/map-results.md)): Nishinomiya area, GSI
  evacuation sites by hazard, nearest sites from the current position;
  answers about a hazard show the nearest site and link to the map.
- Downloads ([results](docs/download-results.md)): models, knowledge
  packages and map areas download inside the app, with resume and SHA-256
  check; the app then runs fully offline. Tested on macOS.
- Current facts ([results](docs/facts-results.md)): shelter status,
  blocked roads and warnings with age and source, apart from the AI; full
  shelters are skipped; shared by the shelter computer; 16 bytes per update
  in the radio-sized format.

## Knowledge packages

```bash
python3 -I tool/build_package.py tool/packages/jp.bousai.core.json
# after one app run has embedded the package (vectors cache on the Mac):
python3 -I tool/add_vectors.py assets/packages/jp.bousai.core.sqlite <cache>.vectors.json embeddinggemma-2-Q8_0.gguf
```

Builds `assets/packages/jp.bousai.core.sqlite` (macOS: uses `textutil` and
Swift for .doc and PDF/OCR). Add `--dart-define=BARE=true` to `flutter run`
to compare with the model alone.

## Run

Needs Flutter 3.44+ (Dart 3.12+), Xcode for Apple platforms, the Android SDK
for Android. Flutter's Swift Package Manager support must stay on (default).

```bash
flutter pub get
flutter run -d macos
```

Open the **Downloads** tab (ダウンロード) and download the answer model
(Gemma 4 E2B, 2.8 GB) and the search model (EmbeddingGemma 2, 310 MB). The
app loads them as soon as they are checked, on every platform. Wi-Fi only by
default. The list comes from
[assets/downloads/catalog.json](assets/downloads/catalog.json); package and
map files are releases of the public repo
[dkastl/fieldkit-data](https://github.com/dkastl/fieldkit-data).

Older ways still work: on macOS, click **Load GGUF file** and pick a model. The app copies it into
its own storage. On Android and iOS, the app downloads the model from the URL
field (default: Gemma 4 E2B Q4_0 from `ggml-org/gemma-4-E2B-it-GGUF`, 2.8 GB).

**Run test questions** asks eight fixed Japanese questions
([lib/spike/bench_prompts.dart](lib/spike/bench_prompts.dart)) and saves the
answers with timings as JSON in the app's documents folder.

Dev flags (spike 3 adds `EMBED_MODEL_PATH` for EmbeddingGemma 2
`embeddinggemma-2-Q8_0.gguf` from `ggml-org/embeddinggemma-2-GGUF`, and
`MIN_COS`, e.g. 0.70):

```bash
flutter run -d macos --dart-define=GGUF_MODEL_PATH=/path/inside/app/storage.gguf --dart-define=AUTO_BENCH=true
```

Downloads for testing (local server with Range support):

```bash
python3 -I tool/serve_downloads.py <folder with catalog.json and files> 8765
flutter run -d macos --dart-define=DOWNLOAD_BASE_URL=http://127.0.0.1:8765/
```

`AUTO_DOWNLOAD=id,…` downloads catalog items on start (for scripted tests).
`MIN_COS` now defaults to 0.70.

## Layout

- `lib/llm/local_llm.dart`: the only code that talks to the model engine.
- `lib/download/`: catalog, downloader (resume, SHA-256), Downloads tab.
- `lib/spike/`: test questions for comparing models and devices.
- `docs/poc-plan.md`: plan, competitor review, licences, naming notes.

## Licence

Apache 2.0, see [LICENSE](LICENSE). Models and data have their own licences;
Gemma 4 is Apache 2.0.
