import 'package:lychnion/knowledge/knowledge_package.dart';
import 'package:lychnion/ui/source_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Source src(String attribution) => Source(
    'kantei',
    '防災の手引き',
    '首相官邸',
    'https://www.kantei.go.jp/jp/headline/bousai/tsunami.html',
    'PDL1.0',
    attribution,
  );

  test('the raw URL is dropped from the shown attribution', () {
    expect(
      SourceLink.label(
        src(
          '出典：首相官邸ホームページ（https://www.kantei.go.jp/jp/headline/bousai/tsunami.html）',
        ),
      ),
      '出典：首相官邸ホームページ',
    );
    expect(
      SourceLink.label(src('出典：政府広報オンライン https://www.gov-online.go.jp/x')),
      '出典：政府広報オンライン',
    );
    expect(SourceLink.label(src('出典：国土地理院')), '出典：国土地理院');
  });
}
