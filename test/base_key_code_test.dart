// The code people compare before a base's notices count as official
// (lychnion/lychnion#63).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lychnion/base/base_key_code.dart';
import 'package:lychnion/facts/signing.dart';

void main() {
  test('a known key has a known code', () {
    // 32 zero bytes: SHA-256 66687aadf862bd77…, its first 60 bits in
    // Crockford base32 (worked out separately, in Python).
    final zero = base64Url.encode(List.filled(32, 0)).replaceAll('=', '');
    expect(baseKeyCode(zero), 'CSM7-NBFR-CAYQ');
    // With or without base64 padding.
    expect(baseKeyCode(base64Url.encode(List.filled(32, 0))), 'CSM7-NBFR-CAYQ');
  });

  test('each key has its own code, the same every time', () async {
    final a = (await FactSigner.generate()).publicKeyText;
    final b = (await FactSigner.generate()).publicKeyText;
    expect(baseKeyCode(a), baseKeyCode(a));
    expect(baseKeyCode(a), isNot(baseKeyCode(b)));
    expect(baseKeyCode(a)!.replaceAll('-', ''), hasLength(baseKeyCodeLength));
  });

  test('no code for something that is not a key', () {
    expect(baseKeyCode(null), isNull);
    expect(baseKeyCode(''), isNull);
    expect(baseKeyCode('not base64!'), isNull);
    expect(baseKeyCode(base64Url.encode(List.filled(16, 1))), isNull);
  });
}
