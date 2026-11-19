# Before you call a change done

1. `flutter analyze` and `flutter test` for the app.
2. For a change in `packages/*`: `dart test` in that package, formatted
   with dart_style 3.1.9 (see `mem:suggested_commands`).
3. Saved-file change: raise its `format` and test old files
   (`docs/development.md`, "Saved files").
4. Commits with `git commit -s` (DCO); changes go through a PR.
5. A self-review of the whole diff before the PR is marked ready.
