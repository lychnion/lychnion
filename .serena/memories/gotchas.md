# Gotchas (not in the docs)

- Material widgets come from `package:material_ui` (Flutter 3.50 split),
  which also brings cupertino_ui. Localisation delegates are in
  `lib/app/text_delegates.dart` (`appTextDelegates`); use that list in
  tests that pump `MaterialApp`.
- Generated l10n files carry `// ignore_for_file: deprecated_member_use`
  via the header in `l10n.yaml`; keep it when regenerating.
- The answer card renders in the answer's language, not the UI language:
  widget tests with a Japanese answer must look for Japanese text.
- Map stack (vector tiles / PMTiles) is blocked for now: the PMTiles plugin
  needs `archive` 3, llamadart needs `archive` 4. Check that before
  proposing a map library upgrade.
- `flutter_edge_ai_llama` pins llamadart exactly; a llamadart bump needs a
  matching `llamadart_llama_cpp_flutter` (see the comment in pubspec.yaml).
- `lib/base/watched_socket.dart` relies on HttpServer reading on while a
  request is answered; `base_limits_test` guards that across Dart updates.
