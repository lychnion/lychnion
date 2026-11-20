/// The code people compare to trust a base's key in person
/// (lychnion/lychnion#63).
///
/// A `lychnion://base` link can come from a web page or a message as well
/// as from the base's QR code, and the app cannot tell them apart. So a
/// link only connects; the base's notices count as official only after
/// the user checks that the code on the phone is the one on the base's
/// screen.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Letters and digits that are hard to mix up (Crockford's base32: no I,
/// L, O or U).
const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Length of the code without its dashes: 12 characters, 60 bits of the
/// key's SHA-256. Making a key with the same code as a given base takes
/// about 2^60 tries.
const baseKeyCodeLength = 12;

/// The comparison code of [keyText] (a base's public key, base64url), as
/// `XXXX-XXXX-XXXX`; null when it is not a 32-byte key.
String? baseKeyCode(String? keyText) {
  if (keyText == null) return null;
  final List<int> key;
  try {
    key = base64Url.decode(base64Url.normalize(keyText));
  } on FormatException {
    return null;
  }
  if (key.length != 32) return null;
  final digest = sha256.convert(key).bytes;
  // The first 60 bits, five at a time.
  var bits = 0, value = 0;
  final out = StringBuffer();
  for (final b in digest) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5 && out.length < baseKeyCodeLength) {
      bits -= 5;
      out.write(_alphabet[(value >> bits) & 31]);
    }
    value &= (1 << bits) - 1;
    if (out.length == baseKeyCodeLength) break;
  }
  final s = out.toString();
  return '${s.substring(0, 4)}-${s.substring(4, 8)}-${s.substring(8)}';
}
