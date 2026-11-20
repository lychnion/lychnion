import 'dart:async';

import '../app/settings.dart';
import '../facts/fact_store.dart';
import '../facts/signing.dart';
import '../knowledge/grounded_answer.dart';
import 'answer_signing.dart' show BadAnswerSignature;
import 'base_client.dart';

/// What the phone made of a base's key (from its /info).
enum BaseKeyCheck {
  /// No key from a link: answers and downloads are used (checked by
  /// signature anyway), but the base's facts stay unverified.
  notPinned,

  /// Another key than the link's: someone else at that address. The
  /// phone does not connect.
  mismatch,

  /// The link's key, but its code was not compared in person yet: the
  /// phone connects, and the base's facts stay unverified.
  pinned,

  /// The link's key, and the user compared its code in person: the base's
  /// facts are trusted.
  trusted;

  /// Whether the phone connects to the base.
  bool get connects => this != mismatch;

  /// The event the phone logs.
  String get logEvent => switch (this) {
    notPinned => 'base_key_not_pinned',
    mismatch => 'base_key_mismatch',
    pinned => 'base_key_pinned',
    trusted => 'base_key_trusted',
  };
}

/// Checks the key a base sent against the one from its link ([pinned]).
///
/// A link can come from the base's QR code or from a web page or message,
/// and the app cannot tell which (lychnion/lychnion#63). So a matching key
/// only confirms that this is the computer the link named; its facts are
/// trusted only when [trust] holds the key already, which happens after
/// the user compared its code ([trustBaseKey]).
BaseKeyCheck checkBaseKey(
  Map<String, dynamic> info, {
  required String? pinned,
  TrustList? trust,
}) {
  if (pinned == null) return BaseKeyCheck.notPinned;
  final key = info['key'];
  if (key is! String || key != pinned) return BaseKeyCheck.mismatch;
  return trust?.trustsKey(pinned) ?? false
      ? BaseKeyCheck.trusted
      : BaseKeyCheck.pinned;
}

/// The user compared the code of [keyText] with the one on the base's
/// screen: its signed facts are trusted from now on, and facts pulled
/// before are checked again. Returns false for a malformed key.
Future<bool> trustBaseKey(
  String keyText, {
  required String name,
  required FactStore facts,
}) async {
  final trust = facts.trust;
  if (trust == null) return false;
  final id = await trust.add(keyText, name);
  if (id == null) return false;
  await facts.reverify();
  return true;
}

/// The user removed the base key [id] (named [name]): its facts count as
/// unconfirmed again.
///
/// The facts are written first: if the app stops in between, the key is
/// still listed and can be removed again, and no fact stays official
/// without a trusted key. Facts signed by the key that arrive meanwhile
/// are marked unconfirmed at the next start (FactStore.load).
Future<void> forgetBaseKey(
  String id, {
  required String name,
  required FactStore facts,
}) async {
  await facts.forgetKey(id, name: name);
  await facts.trust?.remove(id);
}

/// The base's answer to [question], or null when the base failed
/// (network, timeout, not the protocol, a bad signature): the phone then
/// answers with its own model. [onError] gets the reason, for the log.
///
/// [pinnedKey] is the key from the base's link that matched its /info
/// when the phone connected. Without one the answer is unchecked: its
/// signature would only prove it came from whoever sent that /info.
/// [keyTrusted] says whether the user compared that key's code with the
/// base's screen; until then the answer is unchecked too: a link from a
/// web page can name any computer, and the signature only proves it is
/// that one (lychnion/lychnion#63).
///
/// [signedKey] is the pinned key whose base signed before: then an answer
/// without a signature is refused too. [onSigned] is called when the
/// answer was signed by [pinnedKey], to remember that.
Future<GroundedAnswer?> answerFromBase(
  BaseClient base,
  String question, {
  required String? pinnedKey,
  bool keyTrusted = true,
  String? signedKey,
  void Function(String pinnedKey)? onSigned,
  void Function(Object error)? onError,
}) async {
  final GroundedAnswer a;
  try {
    a = await base.ask(
      question,
      pinnedKey: pinnedKey,
      requireSignature: pinnedKey != null && signedKey == pinnedKey,
    );
  } on Object catch (e) {
    onError?.call(e);
    return null;
  }
  if (pinnedKey != null && !a.baseUnsigned) onSigned?.call(pinnedKey);
  return a
    ..answeredBy = base.name
    ..baseUnchecked = pinnedKey == null || !keyTrusted;
}

/// What the Ask page gets from the base: its answer, or null; `refused`
/// when that was for the answer's signature (the phone then says so).
typedef BaseReply = ({GroundedAnswer? answer, bool refused});

/// [answerFromBase] as the Ask page calls it: [settings] knows whether
/// the base signs (from its QR code or an earlier answer) and remembers
/// when it does.
Future<BaseReply> askBase(
  BaseClient base,
  String question, {
  required String? pinnedKey,
  required AppSettings? settings,
  bool keyTrusted = true,
  void Function(Object error)? onError,
}) async {
  var refused = false;
  final answer = await answerFromBase(
    base,
    question,
    pinnedKey: pinnedKey,
    keyTrusted: keyTrusted,
    signedKey: settings?.baseSignedKey,
    onSigned: (key) => unawaited(settings?.setBaseSigned(key)),
    onError: (e) {
      refused = refused || e is BadAnswerSignature;
      onError?.call(e);
    },
  );
  return (answer: answer, refused: refused);
}
