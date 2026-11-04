import 'package:path_provider/path_provider.dart';

/// Resolves `docs:relative/path` to the app's Documents folder.
///
/// On iOS the absolute container path is not known at build time; files are
/// copied there with `xcrun devicectl device copy to … --domain-type
/// appDataContainer`. Other paths are returned unchanged.
Future<String> resolvePath(String path) async {
  if (!path.startsWith('docs:')) return path;
  final docs = await getApplicationDocumentsDirectory();
  return '${docs.path}/${path.substring(5)}';
}
