# Releasing

Checklist for an app release. Version rules:
[versioning.md](versioning.md). Builds and signing:
[release-builds.md](release-builds.md).

## 1. Prepare (in a pull request)

- [ ] `pubspec.yaml`: set `version:`, for example `0.2.0+5`. Raise
      `+BUILD` for every build that goes to a store or to testers.
- [ ] `CHANGELOG.md`: rename `[Unreleased]` to `[0.2.0] - YYYY-MM-DD`,
      add a new empty `[Unreleased]` above it, and update the links at
      the bottom.
- [ ] Note any new format number (catalog, signed record, base protocol)
      in the changelog.
- [ ] Bundled data: name the lychnion-data release in the changelog.
- [ ] CI is green. Merge the pull request.

## 2. Build from the merged commit

```bash
git switch main && git pull
tool/build_release.sh            # APK for testers
tool/build_release.sh appbundle  # app bundle for Google Play
```

- [ ] Check the signature with `apksigner verify --print-certs`; the
      certificate SHA-256 must match
      [release-builds.md](release-builds.md#signing).
- [ ] iOS and macOS: not written down yet. Until then, build in Xcode
      from the same commit and note in the release which builds exist.
- [ ] Install the build on a real device and ask one question offline.

## 3. Tag and publish

- [ ] The repository is public, so everyone who gets the app can get the
      source of the tagged commit (AGPL; see
      [LICENSE-APPSTORE-EXCEPTION.md](../LICENSE-APPSTORE-EXCEPTION.md)).
- [ ] Tag only the merged release commit on `main`, never a branch:

      ```bash
      git tag -a v0.2.0 -m "Lychnion 0.2.0"
      git push origin v0.2.0
      ```

- [ ] GitHub Release from the tag: title `Lychnion 0.2.0`, text = the
      version's changelog section. Mark it as a pre-release while the
      version is 0.x. Attach the signed APK if testers need it.
- [ ] Never attach keys, keystores or passwords. The upload key stays in
      1Password.
