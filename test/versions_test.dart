import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/app/versions.dart';
import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:package_info_plus/package_info_plus.dart' as pi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app version, bundled guides, and one line for reports', () async {
    pi.PackageInfo.setMockInitialValues(
      appName: 'Lychnion',
      packageName: 'com.lychnion.app',
      version: '0.1.0',
      buildNumber: '7',
      buildSignature: '',
    );
    final v = await Versions.load(
      'ja',
      bundled: () async => [
        PackageInfo('jp.outdoor.hiking', '登山（基本）', '2026.11.3', 48),
        PackageInfo('jp.bousai.core', '防災（基本）', '2026.11.4', 123),
      ],
    );
    expect(v.app, '0.1.0');
    expect(v.build, '7');
    // Sorted by title within the guides.
    expect(v.data, [('登山（基本）', '2026.11.3'), ('防災（基本）', '2026.11.4')]);
    expect(
      v.report('リクニオン'),
      'リクニオン 0.1.0+7 · 登山（基本） 2026.11.3 · 防災（基本） 2026.11.4',
    );
  });
}
