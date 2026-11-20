# Mawaqit Bar macOS patches: intent

What `patches/macos/` + `branding/macos/` guarantee for Kimono Prayer's menu bar app. When upstream
moves code, re-create each behaviour wherever it now lives. `checks/macos.sh` is the gate: static
checks, `swift build` and `swift test`, then (`--app`) the built bundle. Locations are as of
Mawaqit Bar v1.2.2 (`macos/`, a SwiftPM executable wrapped into an .app by `build-app.sh`).

Kimono's side is in the kimono repo: `apps/portal/src/lib/prayer/model.ts` (the shapes) and
`apps/portal/src/app/api/v1/prayer/feed/[token]/route.ts` (the link). Kimono Prayer on the web hands
each person a link, `https://<kimono>/api/v1/prayer/feed/<token>`, and a Connect button that opens
`mawaqit-kimono://connect?link=<urlencoded link>`.

## 0001 Identity (`macos: Give the menu bar app the Kimono Prayer identity`)

- Installs beside the original: bundle id `app.kimono.prayer.menubar`, name and display name
  `Kimono Prayer`, state in `~/Library/Application Support/Kimono Prayer/state.json` (never
  upstream's `Mawaqit` folder). UserDefaults and Login Items follow the bundle id by themselves.
- Everything a person reads says Kimono Prayer: menus (Open, About, Quit), the status item's
  tooltip and accessibility name, location and Login Items messages, the location permission text.
- The Notification Settings deep link uses the new bundle id.
- `build-app.sh`, `release.sh` and `dmg-settings.py` make `dist/Kimono Prayer.app`, `.zip`, `.dmg`.
- Internal names stay upstream's (the `MawaqitMac` target and executable, `Mawaqit.icns`, type
  names): renaming them only makes repairs harder.

## 0002 Connecting (`macos: Connect with the link from Kimono Prayer`)

- `Info.plist` declares the `mawaqit-kimono` URL scheme; the app delegate's `application(_:open:)`
  passes `mawaqit-kimono://connect?link=…` to `MawaqitStore.connect` and opens the panel.
- `KimonoLink.parse` takes that address or the bare link, http(s) only, path
  `/api/v1/prayer/feed/<token>`, query and fragment dropped. Anything else isn't a link.
- No link yet: the search field asks for the link ("Paste your Kimono Prayer link"), the location
  button is hidden, and the status line says to paste the link. Pasting it in the search field and
  pressing Return connects.
- The link is `SavedState.link`, in the state file (0700 folder, complete file protection). Not the
  Keychain: ad-hoc signed builds would prompt for it after every update.
- Connecting starts fresh (keeps only the notifications switch) and loads at once. Settings has a
  Kimono section with Disconnect.

## 0003 Source (`macos: Take prayer times from Kimono instead of Mawaqit and AlAdhan`)

- `KimonoService` (Network.swift) is the only network code, always through the link:
  `GET <link>` → `{place, timetable, recent, problem?}`; `GET <link>?q=` and
  `GET <link>?lat=&lon=&tz=` → `{places}`; `PUT <link> {"id"}` → like GET. Errors are `{error}`.
- 401 = the link was renewed: forget the link, keep the times on screen, and show Kimono's message
  ("This link no longer works. Connect again from Kimono Prayer.").
- No mawaqit.net or AlAdhan address remains in Sources; the Mawaqit page/slug parsers, the AlAdhan
  parser and the separate "Use calculated prayer times" option are gone. Calculated places come back
  from Kimono as ordinary search results (the location button sends the Mac's time zone so Kimono
  can offer them).
- `KimonoTimetable.prayerCalendar()` turns `timetable.days` into upstream's `PrayerCalendar`
  (`calendar[month - 1]["<day>"]`, day without a leading zero). Everything downstream of
  `PrayerCalendar` is upstream's and must stay so: `ScheduleBuilder`, current/next highlighting,
  night milestones, the countdown title, notification scheduling, settings.
- The yearly "Refresh required for the new year" gate is gone: the feed spans the new year.
- `SavedState` holds Kimono's place (`id, kind, name, detail, url`). The panel's source button reads
  `Kimono · Mawaqit` / `MasjidBox` / `Calculated`; Settings says where times come from and shows the
  place's detail (the method, for calculated times). Calculated notifications end "· Calculated".
- Refresh: on launch, hourly while connected (a place chosen on another device shows up), and on
  the Refresh button.
- Tests: `KimonoLinkTests.swift`, and the feed tests in `ScheduleTests.swift` (decoding, a year end,
  bad days). Upstream's parser tests that tested removed code are removed with it.

## Branding (`branding/macos/`)

Kimono Prayer's bloom (crescent glyph, Prayer's accent from `app-definitions/prayer/app.json`) on
Kimono's paper, run through upstream's own `make-icon.swift` and `iconutil`, replaces
`Assets/Mawaqit.icns`, `AppIcon.iconset/`, `AppIcon.icon/Assets/artwork.png` and
`AppIcon-master.png`; upstream's DMG background is redrawn to say "Drag Kimono Prayer to
Applications". Regenerate with `node apps/mawaqit-bar/branding/macos/generate.mjs ~/dev/kimono`.
The menu bar glyph stays upstream's SF Symbol.
