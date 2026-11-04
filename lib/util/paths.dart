import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Resolves `docs:relative/path` to the folder where test files are copied
/// from the computer:
///
/// - iOS: the app's Documents folder (`xcrun devicectl device copy to …
///   --domain-type appDataContainer`).
/// - Android: the app's folder on shared storage,
///   `Android/data/<package>/files` (`adb push`). Release builds keep their
///   private folder closed to adb.
///
/// Other paths are returned unchanged.
Future<String> resolvePath(String path) async {
  if (!path.startsWith('docs:')) return path;
  return '${(await exchangeDirectory()).path}/${path.substring(5)}';
}

/// Where test files come in and results go out.
Future<Directory> exchangeDirectory() async {
  if (Platform.isAndroid) {
    final ext = await getExternalStorageDirectory();
    if (ext != null) return ext;
  }
  return getApplicationDocumentsDirectory();
}
