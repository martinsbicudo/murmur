#!/usr/bin/env bash
# Compiles Murmur and assembles a signed build/Murmur.app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

source "$ROOT/scripts/signing.env"
BUILD="$(date +%Y%m%d%H%M)"
APP="$ROOT/build/Murmur.app"

swift build -c release --product Murmur
BIN="$(swift build -c release --show-bin-path)/Murmur"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Murmur"
cp Resources/AppIcon.icns Resources/menubar-*.png "$APP/Contents/Resources/"
cp .env.example "$APP/Contents/Resources/env.example"
sed -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"

if [[ -f "$SIGN_KEYCHAIN" ]] && security find-identity -p codesigning "$SIGN_KEYCHAIN" | grep -q "\"$SIGN_IDENTITY\""; then
  security unlock-keychain -p "$SIGN_KEYCHAIN_PASSWORD" "$SIGN_KEYCHAIN"
  codesign --force --keychain "$SIGN_KEYCHAIN" --sign "$SIGN_IDENTITY" --identifier local.murmur.app "$APP"
else
  echo "warning: signing identity \"$SIGN_IDENTITY\" not found; using ad-hoc signing." >&2
  echo "         macOS will ask for permissions again after every rebuild. Run 'make cert' once to fix." >&2
  codesign --force --sign - --identifier local.murmur.app "$APP"
fi

echo "built $APP (build $BUILD)"
