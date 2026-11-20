# Mawaqit Bar

Prayer times in your top bar, for **GNOME** and **macOS**. Both versions show the next
prayer with a countdown (for example `Maghrib in 2h15min`), today's prayer windows,
Islamic midnight, the last third of the night, and notifications.

| | GNOME | macOS |
|---|---|---|
| Lives in | Top bar (Shell extension) | Menu bar (native app) |
| Folder | [`gnome/`](gnome/mawaqit@akramb.com) | [`macos/`](macos/README.md) |
| Install | One-line script | Notarized `.dmg` |

![Mawaqit GNOME extension](screenshot.png)

## Features (both versions)

- Search Mawaqit mosques by name, city, coordinates, or a pasted mosque URL.
- A location button beside search finds your position, lists nearby mosques, and
  offers calculated times.
- If no suitable mosque is nearby, use calculated times from the
  [AlAdhan API](https://aladhan.com/prayer-times-api) for `City, Country` or
  `latitude, longitude`. These are labeled with their provider and calculation method
  because they may differ from a local mosque or religious authority.
- Each prayer row shows when it ends; the upcoming prayer shows its countdown.
- Night & sunrise section: Islamic midnight, last third, sunrise.
- Notifications at each prayer and at the start of the last third of the night.
- Offline cache with hourly refresh.
- Icon-only mode for the top bar or menu bar.

The two versions only differ in styling and platform integration. GNOME uses
Shell's popup menu styling and loads at login when the extension is enabled. macOS
uses Liquid Glass on macOS 26+ (with a material fallback on older releases), keeps
settings in a popover from its glass panel, and has a Launch at Login switch.

## GNOME

Install the latest release:

```sh
curl -fsSL https://raw.githubusercontent.com/akramboussanni/mawaqit-bar/main/install.sh | sh
```

Log out and back in to load it. Supports GNOME Shell 45–50.

Run the tests locally:

```sh
node gnome/mawaqit@akramb.com/tests/presentation.mjs
# On Linux with GJS installed:
gjs -m gnome/mawaqit@akramb.com/tests/calendar.js
gjs -m gnome/mawaqit@akramb.com/tests/notifications.js
```

## macOS

Download `Mawaqit.dmg` from the
[latest release](https://github.com/akramboussanni/mawaqit-bar/releases/latest), open
it, and drag Mawaqit to Applications. Requires macOS 13 or newer.

Building, local signing, and the release pipeline are documented in
[`macos/README.md`](macos/README.md).

## Releases

Pushing a `v*` tag runs [the release workflow](.github/workflows/release.yml). It tests
both versions, packages the GNOME extension, builds, signs, and notarizes the Mac app,
then publishes all three files to a GitHub release.
