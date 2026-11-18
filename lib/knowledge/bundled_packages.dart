import '../download/download_store.dart';
import 'knowledge_package.dart';

/// Knowledge packages built into the app (`assets/packages/<id>.sqlite`).
/// A newer download from the catalog replaces the built-in copy.
const bundledPackages = [
  'jp.bousai.core',
  'jp.outdoor.hiking',
  'intl.firstaid.basics',
];

Future<List<PackageInfo>> builtInPackageInfo() async {
  final store = await DownloadStore.instance();
  return [
    for (final id in bundledPackages)
      KnowledgePackage.readInfo(await store.packagePath(id, '$id.sqlite')),
  ];
}
