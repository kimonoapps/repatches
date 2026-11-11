# Kimono Photos phone app — what the mobile patches guarantee

The Immich Flutter app (`mobile/` in upstream) ships as **Kimono Photos**. When
an upstream release moves code, keep these behaviours, not the old diff. The
checks in `apps/immich/checks/mobile.sh` hold each one; never weaken a check to
make a patch pass.

## 1. Identity — `0001-mobile-Give-the-app-Kimono-Photos-identity.patch`

| Behaviour | Where upstream keeps it (v3.1.0) |
| --- | --- |
| Android `applicationId` is `app.kimono.photos`; the Kotlin `namespace` stays `app.alextran.immich` so upstream classes don't move | `mobile/android/app/build.gradle` |
| Launcher label and the share/view intent labels say "Kimono Photos" (debug builds: "Kimono Photos Debug", `src/debug/AndroidManifest.xml`) | `mobile/android/app/src/main/AndroidManifest.xml` |
| iOS bundle ids `app.kimono.photos` (release) / `app.kimono.photos.dev`, App Group `group.app.kimono.photos`, team empty (CI passes `DEVELOPMENT_TEAM`) | `mobile/ios/Signing.xcconfig` |
| iOS display name "Kimono Photos" | `mobile/ios/Runner/Info.plist` `CFBundleDisplayName` |
| App links use `kimono-photos://` instead of `immich://`: declared, routed and built (home-screen widgets too) | Manifest, `Info.plist`, `lib/main.dart` `_deepLinkBuilder`, `ios/WidgetExtension/ImmichAPI.swift`, `android/.../widget/*.kt` |
| OAuth returns to `app.kimono.photos:///oauth-callback` (Kimono registers this redirect URI) | `lib/services/oauth.service.dart`, manifest `CallbackActivity` filter |
| iOS permission prompts are plain English and name Kimono Photos | `mobile/ios/Runner/Info.plist` `NS*UsageDescription` |
| Immich's `my.immich.app` universal links are gone | Manifest, `Runner.entitlements`, `RunnerProfile.entitlements` |

## 2. No address, straight to Kimono — `0002-mobile-Connect-from-a-Kimono-link-and-go-straight-to.patch`

- `lib/kimono/kimono_connect.dart` (new file) owns the address. It is saved from
  `kimono-photos://connect?server=<https origin>`, which the Kimono Portal opens
  on the phone. Links are accepted only while signed out, plain http only in
  debug builds, and only the origin is kept. Alternatively the address is baked
  in with `--dart-define=KIMONO_PHOTOS_SERVER=…`. It is stored in
  `StoreKey.serverUrl`, the key upstream's `validateServerUrl` also writes.
- The router handles the connect link before any other `kimono-photos://` link.
- **Nobody types or sees the address.** The sign-in screen (`lib/widgets/forms/login/login_form.dart`)
  has no URL field, no address text, no Back and no Settings button. The
  account sheet (`app_bar_server_info.dart`) doesn't list the server URL. The
  Networking section of Settings (`settings.page.dart`) isn't listed, because it
  shows and edits addresses.
- **Straight to Kimono.** With a known address the sign-in screen resolves the
  server and, when OAuth is on, opens Kimono's sign-in immediately, showing a
  spinner meanwhile. With no address it says "Open Photos from Kimono on this
  phone to connect." On failure it offers "Try again".
- Before opening the sign-in sheet by itself, it waits until the app is the
  active foreground app (`KimonoConnect.untilForeground`). iOS rejects the
  sheet otherwise (ASWebAuthenticationSession error 3), and a connect link
  arrives while iOS is still dismissing its "Open in Kimono Photos?" prompt.
- **Kimono is the only way in.** The sign-in screen has no email and password
  form at all, even if the server allows passwords. If Kimono sign-in fails or
  is cancelled, the screen offers "Sign in with Kimono" again. If the server has
  OAuth off, it says "Kimono sign-in is off for Photos."
- After a person taps **Sign out** (the account sheet,
  `app_bar_dialog.dart`, sets `KimonoConnect.signedOut`) the screen waits on
  the Kimono button instead of bouncing straight back in. Nothing else may set
  it: Immich signs out by itself at start-up when there's no saved session
  (`splash_screen.page.dart`), and the first open from the Portal must still go
  straight to Kimono.
- "Open in browser" is never offered on a photo (`lib/utils/action_button.utils.dart`, `ActionButtonType.openInBrowser`), because it would show the server address in the browser.
- Immich's hidden demo-server shortcuts on the logo are removed.

## 3. No Immich links — `0003-mobile-Drop-Immich-s-own-links-from-the-app.patch`

- The account sheet footer keeps only "Licenses".
- The start-up error screen keeps "Clear app data" but drops the Discord and
  GitHub issue links.
- Update reminders are left alone: Kimono turns Immich's version check off and
  ships app and server together.

## 4. Colours — `0004-mobile-Wear-Kimono-Photos-colours.patch`

- Default theme brand colours: light `#482F74`, dark `#E2DCF0`
  (`lib/constants/colors.dart`).
- Launcher adaptive background and splash background are `#f7f1e8`, with a dark
  splash of `#1c1618` (`values/colors.xml`, `values-v31` and
  `values-night-v31/styles.xml`, `flutter_native_splash.yaml`).
- The vector adaptive-icon layers `drawable/ic_launcher_{foreground,monochrome}.xml`
  are deleted, because branding ships PNGs with the same names.

## 5. Tells Kimono its version — `0005-mobile-Tell-Kimono-which-version-is-installed.patch`

- The iPhone app shares Kimono's keychain group: `keychain-access-groups` in
  `Runner.entitlements` and `RunnerProfile.entitlements` lists
  `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)` first (so upstream's own
  keychain items stay where they were), then `$(AppIdentifierPrefix)app.kimono.shared`.
  `Info.plist` names the shared one as `KimonoKeychainGroup`.
- On every launch `AppDelegate.swift` writes `"<CFBundleShortVersionString>\n<CFBundleVersion>"`
  there as a generic password (service `app.kimono.installed`, account the bundle
  ID). Kimono reads it to offer TestFlight's newer build as an update; iOS gives
  it no other way to know. Not an App Group: that needs the App ID set up by
  hand, and CI's automatic signing can't.

## Artwork (not a patch)

`branding/mobile/install.sh` copies `branding/mobile/files/` over upstream's
images: the launcher icons, adaptive layers, notification icon, splash and
launch images, iOS AppIcon set, in-app logo (`assets/immich-logo.png`) and the
sign-in lockup (`assets/immich-text-{light,dark}.png`). It fails when upstream
drops or renames one of those files. Fix that by updating the file list in
`generate.mjs` and re-running it; don't skip the file.

## Strings

`i18n/en.json` is shared with the web app and owned by the **web** patches.
The phone patches never touch it.
