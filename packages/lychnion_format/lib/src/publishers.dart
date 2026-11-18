import 'record.dart';

/// Lychnion's public key for package records (Ed25519, base64url). The
/// private key is in 1Password (`lychnion-package-signing-key`); see
/// lychnion-data/tool/records.dart.
const lychnionPublicKey = 'vRIbo4GifCc3Rk6OAsrK7yjiQOAJo2287zQsH9FHMLc';

/// Publishers whose records the app accepts without the user adding them.
final builtInPublishers = TrustedKeys({
  'lychnion': [lychnionPublicKey],
});
