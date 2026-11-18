import 'package:lychnion/base/base_link.dart';
import 'package:lychnion/base/base_panel.dart' show baseAppLink;
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

  test('new links use lychnion://base; old shelter and fieldkit links '
      'still work; other hosts are refused', () {
    const link = BaseLink('http://192.168.1.20:8642', name: 'Hall', key: 'k1');
    final uri = Uri.parse(link.toUri().toString());
    expect((uri.scheme, uri.host), ('lychnion', 'base'));
    final back = BaseLink.fromUri(uri)!;
    expect((back.url, back.name, back.key), (link.url, 'Hall', 'k1'));
    for (final old in [
      'lychnion://shelter?url=http://192.168.1.20:8642&key=k1',
      'fieldkit://shelter?url=http://192.168.1.20:8642&key=k1',
    ]) {
      final l = BaseLink.fromUri(Uri.parse(old));
      expect((l?.url, l?.key), ('http://192.168.1.20:8642', 'k1'), reason: old);
    }
    for (final other in [
      'lychnion://bases?url=http://192.168.1.20:8642',
      'lychnion://share?url=http://192.168.1.20:8642',
      'lychnion://?url=http://192.168.1.20:8642',
      'https://base?url=http://192.168.1.20:8642',
    ]) {
      expect(BaseLink.fromUri(Uri.parse(other)), isNull, reason: other);
    }
  });

  test('links use lychnion://, old fieldkit:// codes still work', () {
    const link = BaseLink('http://192.168.1.20:8642');
    expect(link.toUri().scheme, 'lychnion');
    final old = BaseLink.fromUri(
      Uri.parse('fieldkit://shelter?url=http://192.168.1.20:8642'),
    );
    expect(old?.url, 'http://192.168.1.20:8642');
  });

  group('a base that signs its answers', () {
    const base = 'http://192.168.1.20:8642';

    test('says so in its link, read back', () {
      const link = BaseLink(base, key: 'k1', signs: true);
      expect(link.toUri().queryParameters['s'], '1');
      final back = BaseLink.fromUri(Uri.parse(link.toUri().toString()))!;
      expect((back.key, back.signs), ('k1', true));
    });

    test('old links, and links without a key, do not say so', () {
      final old = BaseLink.fromUri(
        Uri.parse('lychnion://shelter?url=$base&key=k1'),
      )!;
      expect(old.signs, isFalse);
      // Without a key nothing could check the signature.
      final noKey = BaseLink.fromUri(
        Uri.parse('lychnion://shelter?url=$base&s=1'),
      )!;
      expect(noKey.signs, isFalse);
      expect(const BaseLink(base, signs: true).toUri().queryParameters, {
        'url': base,
      });
      expect(
        BaseLink.fromUri(Uri.parse('lychnion://shelter?url=$base&key=k1&s=0'))!
            .signs,
        isFalse,
      );
    });

    test('the same base scanned again changes something only when '
        'the link says it signs and the phone did not know', () {
      bool same(BaseLink l, {String? key, String? signed}) =>
          l.changesNothing(url: base, key: key, signedKey: signed);
      const plain = BaseLink(base, key: 'k1');
      const signs = BaseLink(base, key: 'k1', signs: true);
      expect(same(const BaseLink(base), key: 'k1'), isTrue);
      expect(same(plain, key: 'k1'), isTrue);
      expect(same(plain, key: 'k2'), isFalse);
      expect(same(signs, key: 'k1'), isFalse);
      expect(same(signs, key: 'k1', signed: 'k1'), isTrue);
      expect(
        signs.changesNothing(
          url: 'http://192.168.1.21:8642',
          key: 'k1',
          signedKey: 'k1',
        ),
        isFalse,
      );
    });

    test('the QR code a base shows says it signs when it has a key', () {
      expect(baseAppLink(base, name: 'Hall', keyText: 'k1').signs, isTrue);
      expect(baseAppLink(base, name: 'Hall', keyText: null).signs, isFalse);
    });
  });
}
