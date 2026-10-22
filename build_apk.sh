#!/usr/bin/env bash
# Builds a shareable APK for testers.
# Usage:  ./build_apk.sh
# The APK ends up in dist/neato-revive-<version>.apk
#
# Do NOT add --dart-define=VACUULA_SERVER=... for shared builds: every tester
# has their own server address and finds it with "Search network" in the app.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d android ]; then
  echo "Run ./setup.sh first."
  exit 1
fi

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
echo "==> Fetching packages…"
flutter pub get
echo "==> Building Neato Revive App $VERSION (release APK)…"
flutter build apk --release "$@"

mkdir -p dist
OUT="dist/neato-revive-$VERSION.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$OUT"
SIZE="$(du -h "$OUT" | cut -f1)"
SHA="$(shasum -a 256 "$OUT" | cut -d' ' -f1)"

cat <<MSG

Done: $OUT ($SIZE)
SHA-256: $SHA

Share the APK together with INSTALL-ANDROID.md.
Tip: build future versions on this same Mac, so testers can update without
uninstalling (Android only accepts updates signed with the same key).
Bump "version:" in pubspec.yaml (e.g. 1.0.1+2) before each new build.
MSG
