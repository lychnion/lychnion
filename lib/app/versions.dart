import 'package:package_info_plus/package_info_plus.dart' as pi;

import '../download/catalog.dart' show ItemKind;
import '../download/download_store.dart';
import '../knowledge/knowledge_package.dart' show PackageInfo;
import '../knowledge/language.dart' show pick;

/// The app's version and the versions of the guides, maps and models on
/// this device, for Settings → About and for bug reports.
class Versions {
  const Versions(this.app, this.build, this.data);

  /// '0.1.0' and '1' (pubspec.yaml version 0.1.0+1).
  final String app, build;

  /// (title, version), guides first, then maps, then models.
  final List<(String, String)> data;

  /// One line to paste into a report.
  String report(String appName) =>
      ['$appName $app+$build', for (final (t, v) in data) '$t $v'].join(' · ');

  /// Reads the installed app and [bundled] packages; downloaded ones
  /// replace the bundled version of the same id.
  static Future<Versions> load(
    String lang, {
    Future<List<PackageInfo>> Function()? bundled,
  }) async {
    final info = await pi.PackageInfo.fromPlatform();
    final byId = <String, (int, String, String)>{};
    try {
      for (final p
          in await (bundled?.call() ?? Future.value(<PackageInfo>[]))) {
        byId[p.id] = (0, p.title, p.version);
      }
    } on Object {
      // No bundled packages to show.
    }
    try {
      final store = await DownloadStore.instance();
      const order = [ItemKind.package, ItemKind.map, ItemKind.model];
      for (final kind in order) {
        for (final i in store.allInstalled(kind)) {
          final title = pick(i.record.texts('title'), lang) ?? i.id;
          byId[i.id] = (order.indexOf(kind), title, i.version);
        }
      }
    } on Object {
      // Storage not readable: the app version alone still helps.
    }
    final rows = byId.values.toList()
      ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2.compareTo(b.$2));
    return Versions(info.version, info.buildNumber, [
      for (final r in rows) (r.$2, r.$3),
    ]);
  }
}
