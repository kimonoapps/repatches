# Mawaqit Bar GNOME patches: intent

What `patches/gnome/` guarantees for Kimono Prayer's GNOME Shell extension. When upstream moves
code, re-create each behaviour wherever it now lives. `checks/gnome.sh` is the gate: static checks,
`node --check`, node tests (and gjs tests where gjs exists), then (`--zip`) the extension zip.
Locations are as of Mawaqit Bar v1.2.2 (`gnome/mawaqit@akramb.com/`).

Kimono's side: see `intent/macos.md` (the same link, the same answers).

## 0001 Identity (`gnome: Give the extension the Kimono Prayer identity`)

- `metadata.json`: uuid `prayer@kimono.app`, name `Kimono Prayer`, its own description and url.
  GNOME installs by uuid, so the source folder keeps upstream's name.
- State in `~/.config/kimono-prayer/state.json`, never upstream's `mrie-mawaqit`.
- Panel button accessible name, user agent and log lines say Kimono Prayer. The `mawaqit-*` style
  classes are internal and stay.

## 0002 Connecting (`gnome: Connect with the link from Kimono Prayer`)

- `kimono.js` (no imports: node can test it) has `kimonoLink()`, the same rules as the Mac's
  `KimonoLink`: the bare link or `mawaqit-kimono://connect?link=…`, http(s), path
  `/api/v1/prayer/feed/<token>`, query dropped.
- The search entry is where the link goes: not connected, its hint says "Paste your Kimono Prayer
  link", the location button is hidden and the status asks for the link.
- `state.link` is saved with the rest of the state (written PRIVATE, as upstream does).
- Connecting starts fresh (keeps the notification and icon-only switches) and loads at once.
  "Disconnect from Kimono" shows while connected.

## 0003 Source (`gnome: Take prayer times from Kimono instead of Mawaqit and AlAdhan`)

- `_request` is the only network code, always through the link: the same GET / `?q=` /
  `?lat=&lon=&tz=` / PUT `{id}` as the Mac. `tz` is the local zone's identifier when it looks like
  an IANA name.
- 401: forget the link, keep the times, show Kimono's message.
- No mawaqit.net or AlAdhan address remains; `calendar.js` keeps only `NAMES` and `schedule()`;
  the calculated-times submenu and suggestion are gone (calculated places are search results).
- `calendarFromTimetable()` (kimono.js) makes upstream's yearly calendar shape from
  `timetable.days`. `schedule()`, the rows, highlighting, night milestones, panel title and
  notifications stay upstream's. The new-year refresh gate is gone.
- `state.place` is Kimono's place; the source line always shows `Kimono · <kind>` and the place's
  detail (plus the may-differ note for calculated times).
- Refresh on enable, hourly while connected, and on Refresh.
- Tests: `tests/kimono.mjs` (node: link parsing, conversion, labels) and `tests/calendar.js` (gjs:
  a New Year scheduled from the feed). Upstream's Mawaqit parser assertions are removed with the
  parser.

## Branding

None: the extension's only artwork is a symbolic system icon, which stays.
