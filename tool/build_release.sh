#!/usr/bin/env bash
# Builds a release APK or app bundle signed with Lychnion's Android upload
# key. The key lives only in 1Password (item lychnion-android-upload-key
# in the Private vault): it is read into a temporary file for the build
# and removed afterwards, also when the build fails.
#
#   tool/build_release.sh            # APK  → build/app/outputs/flutter-apk/
#   tool/build_release.sh appbundle  # AAB  → build/app/outputs/bundle/release/
#   tool/build_release.sh apk --dart-define=DEV_MENU=true
#
# Check the signature afterwards:
#   $ANDROID_HOME/build-tools/<version>/apksigner verify --print-certs <apk>
# The certificate SHA-256 must match the "certificate SHA-256" field of
# the 1Password item.
set -euo pipefail
cd "$(dirname "$0")/.."

item="op://Private/lychnion-android-upload-key"
work="$(mktemp -d "${TMPDIR:-/tmp}/lychnion-sign.XXXXXX")"
cleanup() {
  if [ -f "$work/upload.p12" ]; then rm -P "$work/upload.p12"; fi
  rmdir "$work" 2>/dev/null || true
}
trap cleanup EXIT

op read "$item/keystore/p12" --out-file "$work/upload.p12" --force >/dev/null
export LYCHNION_UPLOAD_KEYSTORE="$work/upload.p12"
LYCHNION_UPLOAD_PASSWORD="$(op read "$item/credential")"
export LYCHNION_UPLOAD_PASSWORD

target="${1:-apk}"
shift || true
flutter build "$target" --release "$@"
