#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR="$SCRIPT_DIR/dist/Mawaqit.app"
ZIP_PATH="$SCRIPT_DIR/dist/Mawaqit.zip"
DMG_PATH="$SCRIPT_DIR/dist/Mawaqit.dmg"
NOTARY_PROFILE_NAME="${NOTARY_PROFILE:-mawaqit-release}"

# CI passes Apple credentials through the environment; locally a Keychain profile is used.
notarize() {
    if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
        xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD" --wait
    else
        xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE_NAME" --wait
    fi
}

if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' \
        | head -n 1)
fi
if [ -z "$SIGN_IDENTITY" ]; then
    printf '%s\n' \
        "No Developer ID Application certificate was found." \
        "Install it in Keychain Access or set SIGN_IDENTITY explicitly." >&2
    exit 1
fi

SIGN_IDENTITY="$SIGN_IDENTITY" "$SCRIPT_DIR/build-app.sh"
notarize "$ZIP_PATH"
xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

# dmgbuild writes the Finder layout (background, icon positions) without needing a GUI session.
DMGBUILD=$(command -v dmgbuild || true)
if [ -z "$DMGBUILD" ]; then
    python3 -m venv "$SCRIPT_DIR/.build/dmg-venv"
    "$SCRIPT_DIR/.build/dmg-venv/bin/pip" install --quiet dmgbuild
    DMGBUILD="$SCRIPT_DIR/.build/dmg-venv/bin/dmgbuild"
fi
rm -f "$DMG_PATH"
"$DMGBUILD" -s "$SCRIPT_DIR/dmg-settings.py" -D app="$APP_DIR" \
    -D icon="$SCRIPT_DIR/Assets/Mawaqit.icns" \
    -D background="$SCRIPT_DIR/Assets/dmg-background.tiff" Mawaqit "$DMG_PATH"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
notarize "$DMG_PATH"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"
printf '%s\n' "Notarized ZIP: $ZIP_PATH" "Notarized DMG: $DMG_PATH"
