import 'package:lychnion/base/base_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('typed addresses get http and the default port', () {
    expect(BaseLink.normalize('192.168.1.20'), 'http://192.168.1.20:8642');
    expect(
      BaseLink.normalize(' http://192.168.1.20:9000/ '),
      'http://192.168.1.20:9000',
    );
    expect(BaseLink.normalize('base.local'), 'http://base.local:8642');
  });

  test('other input is refused', () {
    expect(BaseLink.normalize(''), isNull);
    expect(BaseLink.normalize('ftp://192.168.1.20'), isNull);
    expect(BaseLink.normalize('http://192.168.1.20/ask?x=1'), isNull);
    expect(BaseLink.normalize('javascript:alert(1)'), isNull);
  });

  test('link round trip, with a Japanese name', () {
    const link = BaseLink('http://192.168.1.20:8642', name: '西宮市役所');
    final back = BaseLink.fromUri(Uri.parse(link.toUri().toString()))!;
    expect(back.url, link.url);
    expect(back.name, '西宮市役所');
  });

  test('links for other apps or with bad addresses are ignored', () {
    expect(BaseLink.fromUri(Uri.parse('https://example.com')), isNull);
    expect(
      BaseLink.fromUri(Uri.parse('lychnion://shelter?url=file:///etc')),
      isNull,
    );
  });

  test('links use lychnion://, old fieldkit:// codes still work', () {
    const link = BaseLink('http://192.168.1.20:8642');
    expect(link.toUri().scheme, 'lychnion');
    final old = BaseLink.fromUri(
      Uri.parse('fieldkit://shelter?url=http://192.168.1.20:8642'),
    );
    expect(old?.url, 'http://192.168.1.20:8642');
  });
}
