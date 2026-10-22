#!/usr/bin/env bash
# Creates the iOS and Android parts of the project, allows the app to talk
# to the server on your home network (plain http, local network) and
# generates the app icon. Run once:  ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. Install it first: https://docs.flutter.dev/get-started/install"
  exit 1
fi

echo "==> Creating platform files (iOS + Android)…"
flutter create --project-name vacuula --org se.hemma --platforms=ios,android .

# ---------- Android ----------
M=android/app/src/main/AndroidManifest.xml
if [ -f "$M" ]; then
  echo "==> Android: http on the home network, notifications and background watcher"
  python3 android_extra/patch_android.py .
  perl -pi -e 's/android:label="vacuula"/android:label="Vacuula"/' "$M"
fi

# ---------- iOS ----------
P=ios/Runner/Info.plist
if [ -f "$P" ] && command -v plutil >/dev/null 2>&1; then
  echo "==> iOS: allowing http and local network access"
  plutil -replace CFBundleDisplayName -string "Vacuula" "$P"
  plutil -replace NSLocalNetworkUsageDescription \
    -string "Vacuula needs to find and talk to your Vacuula server on your home network." "$P"
  plutil -replace NSAppTransportSecurity \
    -json '{"NSAllowsArbitraryLoads":true,"NSAllowsLocalNetworking":true}' "$P"
elif [ -f "$P" ]; then
  echo "NOTE: plutil not found (not a Mac?) - skipped iOS settings."
fi

echo "==> Fetching packages…"
flutter pub get

echo "==> Generating app icons from the Vacuula logo…"
dart run flutter_launcher_icons
if ls android/app/src/main/res/mipmap-*/ic_launcher*.png >/dev/null 2>&1; then
  echo "    Android icons: OK"
else
  echo "    WARNING: Android icons were not created - see the error above."
fi

echo
echo "Done! Uninstall any old version of the app from your phone, connect it and run:"
echo "  flutter run --release --dart-define=VACUULA_SERVER=192.168.1.250"
echo "(change the address if your server uses a different one)"
