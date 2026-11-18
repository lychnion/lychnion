# lychnion_format

The record format Lychnion uses for downloads, as pure Dart (no Flutter):

- `PackageRecord`: one version of a package, map area or model, with its
  files (name, size, SHA-256), signed by its publisher (Ed25519).
- `canonicalJson`: the exact text a signature covers.
- `compareVersions`, `isOlder`: versions only go up.
- `TrustedKeys`, `builtInPublishers`: whose records are accepted;
  `lychnionPublicKey` is Lychnion's public key.

Used by the app, by the signing tool in
[lychnion-data](https://github.com/lychnion/lychnion-data), and later by
headless nodes. Format numbers and when they change:
[docs/versioning.md](../../docs/versioning.md).

Other Dart projects use it from Git:

```yaml
dependencies:
  lychnion_format:
    git:
      url: https://github.com/lychnion/lychnion.git
      path: packages/lychnion_format
      ref: main
```

Licence: AGPL-3.0, as the app.
