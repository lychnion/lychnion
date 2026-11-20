import 'record.dart';

/// Lychnion's public key for package records (Ed25519, base64url). The
/// private key is in 1Password (`lychnion-package-signing-key`); see
/// lychnion-data/tool/records.dart.
const lychnionPublicKey = 'vRIbo4GifCc3Rk6OAsrK7yjiQOAJo2287zQsH9FHMLc';

/// Publishers whose records the app accepts without the user adding them.
final builtInPublishers = TrustedKeys({
  'lychnion': [lychnionPublicKey],
});

/// Kinds only a built-in publisher (Lychnion) may publish: a model's
/// file is parsed by native code (llama.cpp, LiteRT-LM), chat template
/// included, and its text is what answers (lychnion/lychnion#67).
const builtInOnlyKinds = {'model'};

/// Whether [publisher] may publish a record of [kind]: added publishers
/// bring guides and maps, never models. Applied in catalogs, on USB
/// sticks, from bases, when installing and loading, and on nodes.
bool mayPublishKind(String publisher, String kind) =>
    !builtInOnlyKinds.contains(kind) ||
    builtInPublishers.publishers.contains(publisher);
