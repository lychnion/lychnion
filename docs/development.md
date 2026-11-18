# Development

How to build, run and test the app. Start with the
[README](../README.md) if you are new.

## Requirements

- Flutter 3.44 or newer (Dart 3.12 or newer).
- Xcode for iOS and macOS, the Android SDK for Android.
- Flutter's Swift Package Manager support must stay on (it is on by
  default).

## Run

```bash
flutter pub get
flutter run -d macos
```

The app needs two models. Follow the first steps on Home, or open
Settings → オフラインデータ / "Offline data" → ダウンロード / "Downloads",
and download:

- the answer model, Gemma 4 E2B (2.8 GB);
- the search model, EmbeddingGemma 2 (310 MB).

The app loads them as soon as their checksums are checked, on every
platform. Downloads use Wi-Fi only by default. The list comes from
[assets/downloads/catalog.json](../assets/downloads/catalog.json); see
[data-packages.md](data-packages.md).

Older ways still work:

- **macOS:** click **Load GGUF file** and pick a model. The app copies it
  into its own storage.
- **Android and iOS:** the app downloads the model from the URL field
  (default: Gemma 4 E2B Q4_0 from `ggml-org/gemma-4-E2B-it-GGUF`).

## Test

```bash
flutter test
```

**Run test questions** (in the Developer part of the ⋮ menu) asks eight
fixed Japanese questions
([lib/spike/bench_prompts.dart](../lib/spike/bench_prompts.dart)) and
saves the answers with timings as JSON in the app's documents folder.
`--dart-define=AUTO_BENCH=true` runs them on start.

### Downloads from a local server

To test downloads without the internet, serve a folder with a
`catalog.json` and its files. The server supports Range requests, so
resume works.

```bash
python3 -I tool/serve_downloads.py <folder> 8765
flutter run -d macos --dart-define=DOWNLOAD_BASE_URL=http://127.0.0.1:8765/
```

All other flags: [dev-flags.md](dev-flags.md).

## Repository layout

- `lib/`: the app.
  - `lib/llm/local_llm.dart` is the only code that talks to the model
    engine.
  - `lib/download/`: the catalog, downloads, publishers and followed
    catalogs.
  - `lib/base/`: the base (server, browser page data, QR codes). The
    browser page itself is `assets/web/base.html`.
  - `lib/ui/`: Home, first steps and the tour.
- `packages/lychnion_format`: signed records, in pure Dart. The signing
  tool in lychnion-data uses it too.
- `packages/lychnion_fetch`: downloads with resume and hash checks, in
  pure Dart.
- `packages/lychnion_node`: the headless node (see
  [its README](../packages/lychnion_node/README.md)).
- `help/`: the user help, in Japanese and English
  ([help/README.md](../help/README.md)).
- `tool/`: tools for the app's own assets (icons, fonts, regions, help)
  and the local download server. Tools for packages and maps are in
  [lychnion-data](https://github.com/lychnion/lychnion-data).
- `docs/`: these pages ([index](README.md)).

## Saved files

Users keep their data across app updates, so every file the app saves
carries a format number, `"format": n` (none means 0). The rules are in
`lib/util/versioned_file.dart`:

- When you change what a file holds, raise its `format` constant and
  keep reading the old formats. The next save writes the new one.
- A broken file is kept as `<name>.broken`, a file from a newer app as
  `<name>.newer` (with a time in the name if such a copy is already
  there; copies are never written over). If the copy fails, the app does
  not write over the file in that run. The app never crashes on either,
  and Settings shows a line.
- Install markers (`<id>.installed.json`) are trusted only with a signed
  record. Old unsigned ones are checked against the signed catalog by
  size and SHA-256 at start, never trusted as they are.
- Test old, broken and newer files (see
  `test/storage_versions_test.dart`). To try old data in the real app,
  build it with another app id and copy the data into that app, never
  into the installed one.

## Name, brand and app assets

Lychnion (Greek λυχνίον, "small lamp") is the public name. "fieldkit" was
the code name; base QR codes made with it (`fieldkit://`) still work. The
brand (logo, colours, icons) follows the Lychnion brand canvas.

- App icons: `tool/build_icons.py`.
- Fonts: `tool/build_fonts.py`. BIZ UDPGothic for app text, cut down to
  the common Japanese characters; Lexend for the wordmark; Zen Maru
  Gothic for リクニオン.
- Region boundaries: `tool/build_regions.py`.
- Built-in help package: `tool/build_help.py`.
