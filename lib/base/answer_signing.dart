import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../facts/signing.dart';

/// Signed answers from a base (lychnion/lychnion#36).
///
/// The phone sends a new random nonce with each question. The base signs
/// the exact bytes of its answer together with that nonce, with the key
/// phones pin from its QR code, and sends the signature in
/// [answerSignatureHeader]. So an answer cannot be changed on the way,
/// sent by another computer, or replayed for a later question. The phone
/// also checks that the answer is for the question it asked: someone in
/// between could send the base another question with the phone's nonce.
///
/// The answer format itself is unchanged (still protocol 1): old phones
/// send no nonce and get no signature, and the browser page stays
/// unsigned.
const answerSignatureHeader = 'x-lychnion-signature';

/// Sent first in every signed message, so an answer signature can never
/// pass for a fact signature made with the same key, or the other way.
const _domain = 'lychnion-answer-1';

final _nonceShape = RegExp(r'^[A-Za-z0-9_-]{16,64}$');

/// Whether [s] is a nonce a base signs with (base64url, 16 to 64
/// characters). Anything else is ignored: the answer goes unsigned.
bool isAnswerNonce(Object? s) => s is String && _nonceShape.hasMatch(s);

final _random = Random.secure();

/// A new nonce for one question: 16 random bytes, base64url.
String newAnswerNonce() => base64Url
    .encode([for (var i = 0; i < 16; i++) _random.nextInt(256)])
    .replaceAll('=', '');

List<int> _message(String nonce, List<int> body) => [
  ...utf8.encode('$_domain\n$nonce\n'),
  ...body,
];

/// The header value for [body] answering the question sent with [nonce]:
/// `<keyId>.<signature>`.
Future<String> signAnswer(
  FactSigner signer,
  String nonce,
  List<int> body,
) async => '${signer.keyId}.${await signer.signBytes(_message(nonce, body))}';

/// What the phone made of an answer's signature.
enum AnswerSignature {
  /// Signed by the pinned key, for this question.
  valid,

  /// No signature: an old base (or one stripped on the way).
  missing,

  /// A signature that does not check out against the pinned key.
  bad,
}

List<int>? _unb64(String s) {
  try {
    return base64Url.decode(base64Url.normalize(s));
  } on FormatException {
    return null;
  }
}

/// Checks [header] (the base's [answerSignatureHeader]) over [body], the
/// answer bytes as received, for the question sent with [nonce], against
/// [pinnedKey] (the public key from the base's QR code).
Future<AnswerSignature> checkAnswerSignature({
  required String? header,
  required String nonce,
  required List<int> body,
  required String pinnedKey,
}) async {
  if (header == null || header.isEmpty) return AnswerSignature.missing;
  final key = _unb64(pinnedKey);
  final dot = header.indexOf('.');
  if (key == null || key.length != 32 || dot <= 0) return AnswerSignature.bad;
  // The key id tells which key signed: another one is someone else.
  if (header.substring(0, dot) != keyIdOf(key)) return AnswerSignature.bad;
  final sig = _unb64(header.substring(dot + 1));
  if (sig == null || sig.length != 64) return AnswerSignature.bad;
  try {
    final ok = await Ed25519().verify(
      _message(nonce, body),
      signature: Signature(
        sig,
        publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
      ),
    );
    return ok ? AnswerSignature.valid : AnswerSignature.bad;
  } on Object {
    return AnswerSignature.bad;
  }
}

/// A base answer whose signature did not check out against the pinned
/// key, or that answers another question: the phone answers itself.
class BadAnswerSignature implements Exception {
  const BadAnswerSignature(this.reason);
  final String reason;

  @override
  String toString() => 'base answer: $reason';
}
