import '../facts/fact_store.dart';
import '../knowledge/grounded_answer.dart';
import 'base_client.dart';

/// What the phone made of a base's key (from its /info).
enum BaseKeyCheck {
  /// No key from a QR code: answers and downloads are used (checked by
  /// signature anyway), but the base's facts stay unverified.
  notPinned,

  /// Another key than the QR code's: someone else at that address. The
  /// phone does not connect.
  mismatch,

  /// The QR code's key: the base's facts are trusted.
  trusted,
}

/// Checks the key a base sent against the one from its QR code
/// ([pinned], checked in person). When they match, the key is trusted for
/// the base's signed facts, and facts pulled before are checked again.
Future<BaseKeyCheck> checkBaseKey(
  Map<String, dynamic> info, {
  required String? pinned,
  FactStore? facts,
  String name = 'base',
}) async {
  if (pinned == null) return BaseKeyCheck.notPinned;
  final key = info['key'];
  if (key is! String || key != pinned) return BaseKeyCheck.mismatch;
  final trust = facts?.trust;
  if (trust != null) {
    await trust.add(pinned, name);
    // Facts pulled before the QR code was scanned.
    await facts!.reverify();
  }
  return BaseKeyCheck.trusted;
}

/// The base's answer to [question], or null when the base failed
/// (network, timeout, not the protocol): the phone then answers with its
/// own model. [onError] gets the reason, for the log.
Future<GroundedAnswer?> answerFromBase(
  BaseClient base,
  String question, {
  required bool unchecked,
  void Function(Object error)? onError,
}) async {
  try {
    return await base.ask(question)
      ..answeredBy = base.name
      ..baseUnchecked = unchecked;
  } on Object catch (e) {
    onError?.call(e);
    return null;
  }
}
