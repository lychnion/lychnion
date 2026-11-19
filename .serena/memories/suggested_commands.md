# Commands

Main commands (run, test, local download server, asset tools): see
`docs/development.md`. What CI checks: `.github/workflows/ci.yml`.

Not written down elsewhere:
- The app builds with Flutter 3.50 / Dart 3.14, but CI tests `packages/*`
  (lychnion_format, lychnion_fetch, lychnion_node) on Dart 3.12.2. The
  formatters differ, so format those packages with the matching
  dart_style, not with `dart format` from Flutter 3.50:
  `dart pub global activate dart_style 3.1.9` then
  `dart pub global run dart_style:format <files>`.
- Package tests run without Flutter: `cd packages/<name> && dart test`.
