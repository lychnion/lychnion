# Release builds

How version numbers work: [versioning.md](versioning.md).

## Android

```bash
tool/build_release.sh            # APK for testers
tool/build_release.sh appbundle  # app bundle for Google Play
```

The APK goes to `build/app/outputs/flutter-apk/`, the app bundle to
`build/app/outputs/bundle/release/`.

### Signing

Builds are signed with Lychnion's Android upload key. The key lives only
in 1Password (`lychnion-android-upload-key`). The script reads it into a
temporary file and removes it after the build, also when the build fails.

Certificate SHA-256:

```text
E2:E5:99:5F:0C:BE:88:0A:69:D4:3C:B3:EB:94:3C:4A:D9:A7:24:41:CD:BC:5F:FC:CA:C8:0F:B6:49:21:59:B8
```

To check a build:

```bash
$ANDROID_HOME/build-tools/<version>/apksigner verify --print-certs <apk>
```

Without the key (`flutter build apk --release`), the build is signed with
the debug key. It cannot update an app installed from a signed build.

### Developer menu

Release builds hide the Developer menu. For test builds that need it:

```bash
tool/build_release.sh apk --dart-define=DEV_MENU=true
```

## iOS and macOS

Not written down yet. The iPad test in
[device-results.md](device-results.md) used a release build signed with a
free Apple ID (personal team).
