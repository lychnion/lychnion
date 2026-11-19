# Before you call a change done

Run what CI runs (`.github/workflows/ci.yml` is the source of truth):

1. App: `dart format --output=none --set-exit-if-changed lib test`,
   `flutter analyze`, `flutter test`.
2. Each changed package in `packages/*`: format with dart_style 3.1.9
   (see `mem:suggested_commands`), `dart analyze --fatal-infos`,
   `dart test`.
3. Saved-file change: raise its `format` and test old files
   (`docs/development.md`, "Saved files").
4. Commits with `git commit -s` (DCO); changes go through a PR.
5. A self-review of the whole diff before the PR is marked ready.
