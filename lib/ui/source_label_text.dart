import '../download/publisher_label.dart' show PublisherCheck;
import '../knowledge/source_label.dart';
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
