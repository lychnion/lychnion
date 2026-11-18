/// Lychnion's guide files (knowledge packages, `<id>.sqlite`): the
/// tables (`createGuideTables`), writing one (`writeGuide`) and checking
/// that the app can open it (`checkGuide`).
///
/// The app reads guides in lib/knowledge/knowledge_package.dart; its
/// tests check that every guide `checkGuide` accepts opens there.
/// lychnion-data's tool/build_package.py writes the same tables.
library;

export 'src/check.dart';
export 'src/schema.dart';
export 'src/shapes.dart';
export 'src/write.dart';
