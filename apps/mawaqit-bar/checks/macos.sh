#!/usr/bin/env bash
# checks/macos.sh [checkout] [--app] — fails if the menu bar app stops being Kimono Prayer.
#
#   static   identity, the mawaqit-kimono:// connect address, every request through the Kimono
#            link, no Mawaqit / AlAdhan addresses left in Sources, branding installed
#   build    swift build, swift test (upstream's tests plus the patches')
#   --app    also build Kimono Prayer.app (build/macos-app.sh, ad-hoc signed) and read its
#            identity and URL scheme back out of the bundle
#
# Needs macOS with a Swift 6 toolchain; --app also needs Xcode (actool).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
CHECKOUT="${REPATCHES_WORK:-$ROOT/work/mawaqit-bar}"; APP=0
for arg in "$@"; do
  case "$arg" in --app) APP=1 ;; *) CHECKOUT="$arg" ;; esac
done
CHECKOUT="$(cd "$CHECKOUT" 2>/dev/null && pwd || echo "$CHECKOUT")"
M="$CHECKOUT/macos"
S="$M/Sources/MawaqitMac"
[[ -f "$M/Package.swift" ]] || { echo "no macOS app at $M" >&2; exit 2; }

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1" >&2; failures=$((failures + 1)); }
expect() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi; }
absent() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$what"; "$@" | head -5 | sed 's/^/        /' >&2; else pass "$what"; fi; }
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null; }

echo "== static"
expect "bundle id is app.kimono.prayer.menubar" grep -q '<key>CFBundleIdentifier</key><string>app.kimono.prayer.menubar</string>' "$M/Info.plist"
expect "bundle name is Kimono Prayer" grep -q '<key>CFBundleName</key><string>Kimono Prayer</string>' "$M/Info.plist"
expect "display name is Kimono Prayer" grep -q '<key>CFBundleDisplayName</key><string>Kimono Prayer</string>' "$M/Info.plist"
# (CFBundleExecutable MawaqitMac and the Mawaqit.icns file name are internal and stay.)
absent "Info.plist shows no Mawaqit name or id" grep -nE '<string>Mawaqit( |<)|Mawaqit uses|com\.akramb' "$M/Info.plist"
expect "mawaqit-kimono:// is declared" grep -q '<string>mawaqit-kimono</string>' "$M/Info.plist"
expect "the app opens mawaqit-kimono://connect links" grep -q 'func application(_ application: NSApplication, open urls: \[URL\])' "$S/MawaqitMac.swift"
expect "  ...and connects with them" grep -q 'store.connect(link)' "$S/MawaqitMac.swift"
expect "KimonoLink reads the connect address" grep -q 'static let scheme = "mawaqit-kimono"' "$S/KimonoLink.swift"
expect "KimonoLink takes only feed links" grep -q 'api/v1/prayer/feed/' "$S/KimonoLink.swift"
expect "state is kept apart from upstream's" grep -q 'appendingPathComponent("Kimono Prayer", isDirectory: true)' "$S/Store.swift"
absent "no menu or message says Mawaqit" grep -rnE '"(Open|About|Quit) Mawaqit"|"Mawaqit Prayer Times"|Allow Mawaqit|Approve Mawaqit|for Mawaqit in' "$S"
expect "Notification Settings opens Kimono Prayer's page" grep -q 'id=app.kimono.prayer.menubar' "$S/MenuView.swift"
expect "the build makes Kimono Prayer.app" grep -q 'dist/Kimono Prayer.app' "$M/build-app.sh"
absent "no mawaqit.net, AlAdhan or other source address in Sources" grep -rniE 'mawaqit\.net|aladhan|masjidbox\.com|https?://[a-z0-9]' "$S"
expect "the store reads through KimonoService" grep -q 'private let service = KimonoService()' "$S/Store.swift"
expect "  ...which GETs the link" grep -q 'func mine(link: URL)' "$S/Network.swift"
expect "  ...searches it with q, and lat/lon/tz" bash -c "grep -q 'name: \"q\"' '$S/Network.swift' && grep -q 'name: \"tz\"' '$S/Network.swift'"
expect "  ...and PUTs a choice" grep -q 'request.httpMethod = "PUT"' "$S/Network.swift"
expect "a dead link (401) asks to connect again" bash -c "grep -q 'status == 401' '$S/Network.swift' && grep -q 'Connect again from Kimono Prayer' '$S/Network.swift'"
expect "the timetable becomes upstream's calendar" grep -q 'func prayerCalendar() throws -> PrayerCalendar' "$S/Models.swift"
expect "upstream's ScheduleBuilder is still what builds the view" grep -q 'enum ScheduleBuilder' "$S/Schedule.swift"
expect "the source reads Kimono · <kind>" grep -q 'sourceLabel' "$S/MenuView.swift"
for f in Mawaqit.icns AppIcon.icon/Assets/artwork.png AppIcon.iconset/icon_512x512@2x.png dmg-background.tiff; do
  expect "branding: Assets/$f replaced" cmp -s "$ROOT/apps/mawaqit-bar/branding/macos/files/macos/Assets/$f" "$M/Assets/$f"
done
if (( failures )); then echo "$failures static check(s) failed" >&2; exit 1; fi

# AppKit and SwiftUI only build on a Mac. Elsewhere (the daily upstream job and repairs run on
# Linux) the static checks are the gate, and the PR's macos job builds and tests.
if [[ "$(uname)" != Darwin ]]; then echo "  skip  swift build, swift test and --app (need macOS)"; echo "macos: static checks passed"; exit 0; fi
command -v swift >/dev/null || { echo "swift not on PATH; stopping after static checks" >&2; exit 1; }
cd "$M"
echo "== build"
swift build
echo "== test"
swift test

if (( APP )); then
  echo "== app"
  OUT="$ROOT/work/mawaqit-bar-dist"
  "$ROOT/apps/mawaqit-bar/build/macos-app.sh" "$CHECKOUT" "$OUT"
  BUNDLE="$M/dist/Kimono Prayer.app"
  expect "the bundle is app.kimono.prayer.menubar" test "$(plist "$BUNDLE/Contents/Info.plist" CFBundleIdentifier)" = app.kimono.prayer.menubar
  expect "the bundle is named Kimono Prayer" test "$(plist "$BUNDLE/Contents/Info.plist" CFBundleDisplayName)" = "Kimono Prayer"
  expect "the bundle opens mawaqit-kimono://" test "$(plist "$BUNDLE/Contents/Info.plist" CFBundleURLTypes:0:CFBundleURLSchemes:0)" = mawaqit-kimono
  absent "the binary holds no mawaqit.net or AlAdhan address" grep -aiE 'mawaqit\.net|api\.aladhan' "$BUNDLE/Contents/MacOS/MawaqitMac"
  expect "the signature verifies" codesign --verify --deep --strict "$BUNDLE"
  expect "a DMG was made" bash -c "ls '$OUT'/kimono-prayer-*.dmg"
  if (( failures )); then echo "$failures app check(s) failed" >&2; exit 1; fi
fi
echo "macos: all checks passed"
