#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR="$SCRIPT_DIR/dist/Mawaqit.app"
ZIP_PATH="$SCRIPT_DIR/dist/Mawaqit.zip"
SWIFT_COMMAND=$(command -v swift)

# Swiftly's shim can fall back to Apple's bundled compiler when invoked from
# non-interactive shells. Prefer its selected toolchain executable directly.
SWIFTLY_CONFIG="${SWIFTLY_HOME_DIR:-$HOME/.swiftly}/config.json"
SWIFTLY_TOOLCHAINS="${SWIFTLY_TOOLCHAINS_DIR:-$HOME/Library/Developer/Toolchains}"
if [ -r "$SWIFTLY_CONFIG" ]; then
    SWIFTLY_VERSION=$(sed -n 's/.*"inUse"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SWIFTLY_CONFIG" | head -n 1)
    SWIFTLY_SWIFT="$SWIFTLY_TOOLCHAINS/swift-$SWIFTLY_VERSION-RELEASE.xctoolchain/usr/bin/swift"
    if [ -n "$SWIFTLY_VERSION" ] && [ -x "$SWIFTLY_SWIFT" ]; then
        SWIFT_COMMAND="$SWIFTLY_SWIFT"
    fi
fi

cd "$SCRIPT_DIR"
SDK_PATH="${MACOS_SDK_PATH:-$(xcrun --show-sdk-path)}"
# Prefer the newer installed SDK when available.
if [ -z "${MACOS_SDK_PATH:-}" ] && [ -d "$SDK_PATH/../MacOSX26.sdk" ]; then
    SDK_PATH="$SDK_PATH/../MacOSX26.sdk"
fi
"$SWIFT_COMMAND" build --sdk "$SDK_PATH" -c release -debug-info-format none --disable-sandbox
BUILD_DIR=$("$SWIFT_COMMAND" build --sdk "$SDK_PATH" -c release -debug-info-format none --show-bin-path --disable-sandbox)
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/MawaqitMac" "$APP_DIR/Contents/MacOS/MawaqitMac"
# Some toolchains record the deployment target as the SDK version, which makes macOS
# treat the app as pre-Tahoe and skip Liquid Glass on system controls. Record the real SDK.
SDK_VERSION=$(xcrun --sdk "$SDK_PATH" --show-sdk-version)
vtool -set-build-version macos 13.0 "$SDK_VERSION" -replace \
    -output "$APP_DIR/Contents/MacOS/MawaqitMac" "$APP_DIR/Contents/MacOS/MawaqitMac"
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -n "${APP_VERSION:-}" ]; then
    plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP_DIR/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "${APP_BUILD:-1}" "$APP_DIR/Contents/Info.plist"
fi
cp "$SCRIPT_DIR/Assets/Mawaqit.icns" "$APP_DIR/Contents/Resources/Mawaqit.icns"
# macOS 26+ frames legacy .icns icons, so compile the Icon Composer icon when Xcode is available.
if xcrun --find actool >/dev/null 2>&1; then
    xcrun actool "$SCRIPT_DIR/Assets/AppIcon.icon" --compile "$APP_DIR/Contents/Resources" \
        --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon \
        --output-partial-info-plist "$SCRIPT_DIR/.build/icon-info.plist" >/dev/null
    test -f "$APP_DIR/Contents/Resources/Assets.car"
    plutil -replace CFBundleIconName -string AppIcon "$APP_DIR/Contents/Info.plist"
    # actool also emits a fallback AppIcon.icns; keep the hand-tuned Mawaqit.icns instead.
    rm -f "$APP_DIR/Contents/Resources/AppIcon.icns"
else
    echo "actool not found (install Xcode); using the legacy icon only." >&2
fi
if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    codesign --force --sign - "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
printf '%s\n' "Built $APP_DIR" "Archived $ZIP_PATH"
