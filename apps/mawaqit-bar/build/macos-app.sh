#!/usr/bin/env bash
# build/macos-app.sh <checkout> <out-dir> — Kimono Prayer.app as a zip and a DMG.
#
# Signed and notarized when SIGN_IDENTITY names a Developer ID Application identity in the
# keychain and APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD are set (upstream's release.sh,
# patched to Kimono's names, does the work). Otherwise ad-hoc signed: it runs, but Gatekeeper
# asks the first time (right-click → Open).
#
# BUILD_NAME / BUILD_NUMBER / VERSION (scripts/versions.sh) set the app's version and file names.
# Needs macOS with Xcode (actool compiles the Liquid Glass icon); dmgbuild, if on PATH, draws the
# DMG window, else it's a plain DMG.
set -euo pipefail
CO="$(cd "${1:?checkout required}" && pwd)"
OUT="${2:?out dir required}"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
M="$CO/macos"
NAME="Kimono Prayer"
STEM="kimono-prayer-${VERSION:-dev}"
export APP_VERSION="${BUILD_NAME:-}" APP_BUILD="${BUILD_NUMBER:-1}"
[[ -n "$APP_VERSION" ]] || unset APP_VERSION

if [[ -n "${SIGN_IDENTITY:-}" && -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
  (cd "$M" && ./release.sh)
  cp "$M/dist/$NAME.dmg" "$OUT/$STEM.dmg"
  cp "$M/dist/$NAME.zip" "$OUT/$STEM-macos.zip"
else
  (cd "$M" && ./build-app.sh)
  ditto -c -k --sequesterRsrc --keepParent "$M/dist/$NAME.app" "$OUT/$STEM-macos.zip"
  rm -f "$OUT/$STEM.dmg"
  if command -v dmgbuild >/dev/null; then
    dmgbuild -s "$M/dmg-settings.py" -D app="$M/dist/$NAME.app" -D icon="$M/Assets/Mawaqit.icns" \
      -D background="$M/Assets/dmg-background.tiff" "$NAME" "$OUT/$STEM.dmg"
  else
    stage="$(mktemp -d)"
    cp -R "$M/dist/$NAME.app" "$stage/"
    ln -s /Applications "$stage/Applications"
    hdiutil create -quiet -volname "$NAME" -srcfolder "$stage" -ov -format UDZO "$OUT/$STEM.dmg"
    rm -rf "$stage"
  fi
fi
echo "built $OUT/$STEM.dmg and $OUT/$STEM-macos.zip"
