# Mawaqit Bar for macOS

Native macOS menu-bar version of Mawaqit Bar. It has the same features as the
[GNOME extension](../gnome/mawaqit@akramb.com): mosque search, prayer windows, Islamic
midnight and last-third calculations, caching, refresh cycle, and notifications. The app icon is an original crescent-night design stored under
`Assets/`; transient search and refresh status appears at the bottom of the popover.

Mawaqit mosque schedules remain the primary source. If no suitable mosque is nearby,
every location search also offers calculated times from the
[AlAdhan API](https://aladhan.com/prayer-times-api). Enter a city with its country or
latitude/longitude. The app caches the returned annual calendar and clearly displays
the provider and calculation method. Calculated times may differ from a local mosque
or religious authority because local schedules can include tuned adjustments.

## Build and run

Requires macOS 13 or newer at runtime, Swift 6 and a macOS 26 or newer SDK to build.
Search uses AppKit’s native search field, and buttons, switches and popovers are standard system controls, so they pick up Liquid Glass on macOS 26 or later.
The menu-bar panel is 340 points wide and sizes to its content. On macOS 26 and later,
its background uses NSGlassEffectView. Escape, clicking outside, or switching apps dismisses the panel.
Settings open in a popover from the gear button (also Settings… or Command–Comma); click away or press Escape to close it.
The location arrow beside search requests a one-time location, searches nearby
Mawaqit mosques, and offers AlAdhan calculated times. Your saved schedule changes
only when you choose a result.
Opening the app again from Applications shows its window, even if a menu-bar
manager has hidden the icon. The build
script automatically uses the toolchain selected by Swiftly when one is present.

```sh
cd macos
chmod +x build-app.sh
./build-app.sh
open dist/Mawaqit.app
```

Left-click the menu-bar item to open Mawaqit and enable **Launch at Login** in the
settings panel. Right-click the menu-bar item to open the main window, settings, or quit. Move the app into `/Applications`
before enabling automatic launch so macOS keeps a stable login-item path.

## Release from GitHub Actions

Pushing a `v*` tag (for example `git tag v1.1 && git push origin v1.1`) builds, signs,
notarizes, and staples the app, then attaches `Mawaqit.dmg` and `Mawaqit.zip` to a
GitHub release. Pushes to `main` run the same notarized build and keep the files as
workflow artifacts. The workflow needs these repository secrets:

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12` | Base64 of your exported **Developer ID Application** certificate and private key (`.p12`) |
| `MACOS_CERTIFICATE_PASSWORD` | The password you chose when exporting the `.p12` |
| `APPLE_ID` | Your Apple Account email |
| `APPLE_TEAM_ID` | Your 10-character Team ID |
| `APPLE_APP_PASSWORD` | An app-specific password from account.apple.com |

Run this once to set them. It exports only the Developer ID identity, asks for your
Apple Account email and an app-specific password, checks them with Apple, uploads the
secrets, and starts a signed build:

```sh
./macos/setup-ci-secrets.sh
```

## Release from your Mac

For a local Gatekeeper-approved release, save your notarization credentials to
Keychain once (use an app-specific password, not your Apple Account password):

```sh
xcrun notarytool store-credentials mawaqit-release \
  --apple-id "you@example.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Then build, sign, notarize, staple, and package the app:

```sh
cd macos
./release.sh
```

The primary shareable file is `dist/Mawaqit.dmg`, with `Mawaqit.app` and an
Applications shortcut for drag-to-install. A notarized `dist/Mawaqit.zip` is also
produced. The script picks the first installed `Developer ID Application` identity.
Override it or the Keychain profile if needed:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="mawaqit-release" ./release.sh
```

For day-to-day development:

```sh
swift test
swift run MawaqitMac
```

The schedule itself does not scroll. Both providers share a three-line header, five
prayer rows, and three night/sunrise rows. Click the provider label to open Settings
for source details. Only the separate search-results area scrolls.
