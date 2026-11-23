import 'package:lychnion_format/lychnion_format.dart' show voucherPublisher;

import '../download/download_store.dart';
import '../download/publisher_label.dart';
import '../knowledge/grounded_answer.dart';
import '../knowledge/knowledge_package.dart';
import '../l10n/app_localizations.dart';

/// The line under a source in an answer: who signed its guide and whether
/// Lychnion checked that publisher (lychnion/lychnion#119). Null for
/// Lychnion's own guides and sources without a label. [fromBase]: the
/// label is the base's word, and says so.
String? sourceLabelText(
  AppLocalizations l,
  SourceLabel? label,
  String lang, {
  bool fromBase = false,
}) {
  if (label == null || label.isBuiltIn) return null;
  final app = l.appName, name = label.titleIn(lang);
  final text = switch (label.check) {
    PublisherCheck.builtIn => null,
    PublisherCheck.vouched => l.answerSourceChecked(app, name),
    PublisherCheck.notChecked => l.answerSourceNotChecked(app, name),
    PublisherCheck.withdrawn => l.answerSourceWithdrawn(app, name),
    PublisherCheck.otherKey => l.answerSourceOtherKey(app, name),
    PublisherCheck.revoked => l.answerSourceRevoked(name),
  };
  if (text == null) return null;
  return fromBase ? l.answerSourceBaseSays(text) : text;
}

/// The label of [s] in [answer]: for a base's answer the base's word
/// ([Source.label]); for this device's own, looked up from who signed the
/// guide with [store], so it follows the vouches and publishers now.
SourceLabel? sourceLabelFor(
  GroundedAnswer answer,
  Source s,
  DownloadStore? store,
) {
  if (answer.answeredBy != null) return s.label;
  if (store != null) return store.sourceLabelOf(s.signer, s.signerKeyId);
  // Before Downloads are loaded: another publisher's guide is never shown
  // as if it were Lychnion's.
  final signer = s.signer;
  return signer == null || signer == voucherPublisher
      ? null
      : SourceLabel(PublisherCheck.notChecked, name: signer);
}
