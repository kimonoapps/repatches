#!/usr/bin/env bash
# checks/mobile.sh [checkout] [--apk] — fails if the phone app stops being Kimono Photos.
#
#   static     identity, link schemes, no address on screen, straight-to-Kimono sign-in
#   analyze    dart analyze --fatal-infos lib (upstream's own bar)
#   test       checks/mobile/*_test.dart, run inside the checkout
#   --apk      build a release APK and read its package id and label back out
#
# Needs Flutter (version from mobile/mise.toml) on PATH; --apk also needs the
# Android SDK (ANDROID_HOME) and JDK 21.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
CHECKOUT="${REPATCHES_WORK:-$ROOT/work/immich}"; APK=0
for arg in "$@"; do
  case "$arg" in --apk) APK=1 ;; *) CHECKOUT="$arg" ;; esac
done
M="$CHECKOUT/mobile"
[[ -d "$M/lib" ]] || { echo "no mobile app at $M" >&2; exit 2; }

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1" >&2; failures=$((failures + 1)); }
expect() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi; }
absent() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$what"; "$@" | head -5 | sed 's/^/        /' >&2; else pass "$what"; fi; }

echo "== static"
expect "Android app id is app.kimono.photos" grep -q 'applicationId "app.kimono.photos"' "$M/android/app/build.gradle"
expect "Android launcher label is Kimono Photos" grep -q 'android:label="Kimono Photos"' "$M/android/app/src/main/AndroidManifest.xml"
absent "no Android label mentions Immich (release or debug)" grep -rn 'android:label="[^"]*Immich' "$M/android/app/src/main/AndroidManifest.xml" "$M/android/app/src/debug/AndroidManifest.xml"
expect "iOS bundle id is app.kimono.photos" grep -Eq '^IMMICH_BUNDLE_ID_PROD = app\.kimono\.photos$' "$M/ios/Signing.xcconfig"
expect "iOS App Group is group.app.kimono.photos" grep -Eq '^IMMICH_GROUP_ID = group\.app\.kimono\.photos$' "$M/ios/Signing.xcconfig"
expect "iOS display name is Kimono Photos" grep -A1 -q 'CFBundleDisplayName' "$M/ios/Runner/Info.plist"
expect "  ...and it says Kimono Photos" bash -c "grep -A1 CFBundleDisplayName '$M/ios/Runner/Info.plist' | grep -q 'Kimono Photos'"
expect "kimono-photos:// is declared on Android" grep -q 'android:scheme="kimono-photos"' "$M/android/app/src/main/AndroidManifest.xml"
expect "kimono-photos:// is declared on iOS" grep -q '<string>kimono-photos</string>' "$M/ios/Runner/Info.plist"
expect "OAuth returns to app.kimono.photos:///oauth-callback" grep -q "callbackUrlScheme = 'app.kimono.photos'" "$M/lib/services/oauth.service.dart"
absent "no immich:// or app.immich: links left" grep -rnE '"immich://|'"'"'immich://|scheme="immich"|scheme="app\.immich"|<string>immich</string>|app\.immich:/' \
  "$M/lib" "$M/android/app/src/main" "$M/ios/Runner" "$M/ios/WidgetExtension" --include=*.dart --include=*.kt --include=*.xml --include=*.plist --include=*.swift
absent "no my.immich.app links" grep -rn 'my\.immich\.app' "$M/android/app/src/main/AndroidManifest.xml" "$M/ios/Runner/Runner.entitlements" "$M/ios/Runner/RunnerProfile.entitlements"
expect "connect links are routed" grep -q 'KimonoConnect.isConnectLink' "$M/lib/main.dart"
expect "sign-in screen takes its address from KimonoConnect" grep -q 'KimonoConnect.server' "$M/lib/widgets/forms/login/login_form.dart"
# (Networking settings still have address fields; the next-but-one check keeps that section unlisted.)
absent "no address field on the sign-in screens" grep -rln 'ImmichURLInput(\|login_form_endpoint_url' "$M/lib/widgets/forms/login" "$M/lib/pages/login"
absent "the account sheet doesn't show the address" grep -rn 'server_info_box_server_url' "$M/lib" --include=*.dart --exclude=*.g.dart --exclude-dir=generated
absent "Networking settings aren't listed" grep -n 'SettingSection\.values\.\(map\|where\|first\)' "$M/lib/pages/common/settings.page.dart"
expect "sign-in starts Kimono's sign-in by itself" grep -q 'await oAuthLogin()' "$M/lib/widgets/forms/login/login_form.dart"
expect "tapping Sign out stops the automatic sign-in" grep -q 'KimonoConnect.signedOut = true' "$M/lib/widgets/common/app_bar_dialog/app_bar_dialog.dart"
# Immich also signs out by itself (start-up with no session): that must not stop the first automatic sign-in.
absent "the app's own sign-outs don't stop it" grep -n 'KimonoConnect.signedOut = true' "$M/lib/services/auth.service.dart" "$M/lib/providers/auth.provider.dart" "$M/lib/pages/common/splash_screen.page.dart"
absent "no Immich docs/GitHub/Discord links" grep -rnE 'docs\.immich\.app|github\.com/immich-app/immich(/issues)?'"'"'|discord\.immich\.app' "$M/lib" --include=*.dart
expect "branding: launcher icon replaced" bash -c "cmp -s '$ROOT/apps/immich/branding/mobile/files/mobile/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png' '$M/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png'"
expect "branding: iOS icon replaced" bash -c "cmp -s '$ROOT/apps/immich/branding/mobile/files/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/1024.png' '$M/ios/Runner/Assets.xcassets/AppIcon.appiconset/1024.png'"

# Every Immich logo the app loads must be ours: catches a new upstream use of an asset we never replaced.
stale=""
for asset in $(grep -rhoE "assets/immich[A-Za-z0-9_.-]*\.(png|svg|json)" "$M/lib" --include=*.dart | sort -u); do
  if [[ -f "$ROOT/upstream/immich/mobile/$asset" ]] && cmp -s "$ROOT/upstream/immich/mobile/$asset" "$M/$asset"; then stale+=" $asset"; fi
done
if [[ -z "$stale" ]]; then pass "every Immich logo the app loads is replaced"; else fail "still upstream's artwork:$stale"; fi

if (( failures )); then echo "$failures static check(s) failed" >&2; exit 1; fi

command -v flutter >/dev/null || { echo "flutter not on PATH; stopping after static checks" >&2; exit 1; }
cd "$M"
echo "== analyze"
flutter pub get --enforce-lockfile >/dev/null
dart run easy_localization:generate -S ../i18n >/dev/null
dart run bin/generate_keys.dart >/dev/null
dart analyze --fatal-infos lib

echo "== test"
mkdir -p test/kimono
cp "$HERE"/mobile/*_test.dart test/kimono/
flutter test test/kimono

if (( APK )); then
  echo "== apk"
  flutter build apk --release --target-platform android-arm64 --split-per-abi
  apk="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
  aapt2="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)/aapt2"
  badging="$("$aapt2" dump badging "$apk")"
  grep -q "package: name='app.kimono.photos'" <<<"$badging" && pass "APK package is app.kimono.photos" || fail "APK package is app.kimono.photos"
  grep -q "application-label:'Kimono Photos'" <<<"$badging" && pass "APK label is Kimono Photos" || fail "APK label is Kimono Photos"
  (( failures == 0 )) || exit 1
fi
echo "mobile checks passed"
