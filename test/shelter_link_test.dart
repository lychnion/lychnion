import 'package:lychnion/shelter/shelter_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('typed addresses get http and the default port', () {
    expect(ShelterLink.normalize('192.168.1.20'), 'http://192.168.1.20:8642');
    expect(
      ShelterLink.normalize(' http://192.168.1.20:9000/ '),
      'http://192.168.1.20:9000',
    );
    expect(ShelterLink.normalize('shelter.local'), 'http://shelter.local:8642');
  });

  test('other input is refused', () {
    expect(ShelterLink.normalize(''), isNull);
    expect(ShelterLink.normalize('ftp://192.168.1.20'), isNull);
    expect(ShelterLink.normalize('http://192.168.1.20/ask?x=1'), isNull);
    expect(ShelterLink.normalize('javascript:alert(1)'), isNull);
  });

  test('link round trip, with a Japanese name', () {
    const link = ShelterLink('http://192.168.1.20:8642', name: '西宮市役所');
    final back = ShelterLink.fromUri(Uri.parse(link.toUri().toString()))!;
    expect(back.url, link.url);
    expect(back.name, '西宮市役所');
  });

  test('links for other apps or with bad addresses are ignored', () {
    expect(ShelterLink.fromUri(Uri.parse('https://example.com')), isNull);
    expect(
      ShelterLink.fromUri(Uri.parse('lychnion://shelter?url=file:///etc')),
      isNull,
    );
  });

  test('links use lychnion://, old fieldkit:// codes still work', () {
    const link = ShelterLink('http://192.168.1.20:8642');
    expect(link.toUri().scheme, 'lychnion');
    final old = ShelterLink.fromUri(
      Uri.parse('fieldkit://shelter?url=http://192.168.1.20:8642'),
    );
    expect(old?.url, 'http://192.168.1.20:8642');
  });
}
