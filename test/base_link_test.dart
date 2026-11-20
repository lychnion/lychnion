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

  // lychnion/lychnion#72: a base is on the local network; a link must not
  // send questions to a server on the internet.
  test('only local-network hosts are bases', () {
    for (final ok in [
      '10.0.0.5',
      '172.16.4.1',
      '192.168.43.1',
      '100.64.1.2',
      '169.254.10.20',
      '127.0.0.1',
      'base.local',
      'BASE.LOCAL',
      '[fe80::1]',
      '[fd12:3456::7]',
      '[::1]',
    ]) {
      expect(BaseLink.normalize(ok), isNotNull, reason: ok);
    }
    for (final bad in [
      '203.0.113.5',
      '8.8.8.8',
      '172.32.0.1',
      'example.com',
      'evil.example',
      'base',
      '.local',
      'https://example.com',
      '[2001:db8::1]',
      'http://user@192.168.1.20',
    ]) {
      expect(BaseLink.normalize(bad), isNull, reason: bad);
    }
    // IPv6 keeps its brackets.
    expect(BaseLink.normalize('[fe80::1]'), 'http://[fe80::1]:8642');
    // Ports must be real ones.
    expect(BaseLink.normalize('192.168.1.20:0'), isNull);
    expect(BaseLink.normalize('192.168.1.20:99999'), isNull);
    // Loopback only where a simulator or this computer's own base can
    // be there (debug builds, desktops); on a phone it is another app.
    expect(BaseLink.isLocalHost('127.0.0.1', loopback: false), isFalse);
    expect(BaseLink.isLocalHost('::1', loopback: false), isFalse);
    expect(BaseLink.isLocalHost('127.0.0.1', loopback: true), isTrue);
    // A link to a public host is not a base link at all.
    expect(
      BaseLink.fromUri(
        Uri.parse('lychnion://base?url=http%3A%2F%2F203.0.113.5%3A8642'),
      ),
      isNull,
    );
    expect(
      ShareLink.fromUri(Uri.parse('lychnion://share?url=example.com')),
      isNull,
    );
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

  test('new links use lychnion://base; old shelter links still work; '
      'other hosts and schemes are refused', () {
    const link = BaseLink('http://192.168.1.20:8642', name: 'Hall', key: 'k1');
    final uri = Uri.parse(link.toUri().toString());
    expect((uri.scheme, uri.host), ('lychnion', 'base'));
    final back = BaseLink.fromUri(uri)!;
    expect((back.url, back.name, back.key), (link.url, 'Hall', 'k1'));
    final old = BaseLink.fromUri(
      Uri.parse('lychnion://shelter?url=http://192.168.1.20:8642&key=k1'),
    );
    expect((old?.url, old?.key), ('http://192.168.1.20:8642', 'k1'));
    for (final other in [
      'lychnion://bases?url=http://192.168.1.20:8642',
      'lychnion://share?url=http://192.168.1.20:8642',
      'lychnion://?url=http://192.168.1.20:8642',
      'https://base?url=http://192.168.1.20:8642',
      'other://base?url=http://192.168.1.20:8642',
    ]) {
      expect(BaseLink.fromUri(Uri.parse(other)), isNull, reason: other);
    }
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

    // lychnion/lychnion#63: a key that is pinned but not trusted yet is
    // asked about again, so the user can compare its code.
    test('the same key scanned again is asked about while not trusted', () {
      const plain = BaseLink(base, key: 'k1');
      bool same({required bool trusted}) => plain.changesNothing(
        url: base,
        key: 'k1',
        signedKey: null,
        keyTrusted: trusted,
      );
      expect(same(trusted: true), isTrue);
      expect(same(trusted: false), isFalse);
      // A link without a key has nothing to compare.
      expect(
        const BaseLink(base).changesNothing(
          url: base,
          key: 'k1',
          signedKey: null,
          keyTrusted: false,
        ),
        isTrue,
      );
    });
  });

  // lychnion/lychnion#63: anyone can write a link, and its name is shown
  // in the connect dialog and in Settings.
  test('the name from a link is cleaned and capped', () {
    BaseLink? read(String name) => BaseLink.fromUri(
      Uri(
        scheme: 'lychnion',
        host: 'base',
        queryParameters: {'url': '192.168.1.20', 'name': name},
      ),
    );
    expect(read('Hall\u202e\u200b\n')!.name, 'Hall');
    expect(read('  \u2066 ')!.name, isNull);
    expect(read('あ' * 100)!.name, 'あ' * 60);
  });
}
