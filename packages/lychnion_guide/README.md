# lychnion_guide

Lychnion's guide files (knowledge packages, `<id>.sqlite`), in pure Dart:

- `createGuideTables`: the tables, as lychnion-data's
  `tool/build_package.py` writes them;
- `writeGuide`: writes a guide, checks it, and only then replaces the file;
- `checkGuide`: opens a guide the way the app does
  (`lib/knowledge/knowledge_package.dart`) and says what is wrong.

Used by the desktop app before it signs a guide, and by
[lychnion-studio](https://github.com/lychnion/lychnion-studio). The app's
tests make sure every guide `checkGuide` accepts opens in the app.

```sh
dart pub get
dart test
```
