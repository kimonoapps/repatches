#!/usr/bin/env bash
# checks/gnome.sh [checkout] [--zip] — fails if the GNOME extension stops being Kimono Prayer.
#
#   static   identity (uuid, name, state folder), connecting by link, every request through the
#            Kimono link, no Mawaqit / AlAdhan addresses left
#   syntax   node --check on every module
#   test     node tests/*.mjs; gjs -m tests/*.js too when gjs is installed (CI has it; a Mac doesn't)
#   --zip    also build the extension zip (build/gnome-zip.sh) and read its metadata back
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
CHECKOUT="${REPATCHES_WORK:-$ROOT/work/mawaqit-bar}"; ZIP=0
for arg in "$@"; do
  case "$arg" in --zip) ZIP=1 ;; *) CHECKOUT="$arg" ;; esac
done
CHECKOUT="$(cd "$CHECKOUT" 2>/dev/null && pwd || echo "$CHECKOUT")"
E="$CHECKOUT/gnome/mawaqit@akramb.com"
[[ -f "$E/extension.js" ]] || { echo "no GNOME extension at $E" >&2; exit 2; }

failures=0
pass() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1" >&2; failures=$((failures + 1)); }
expect() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$what"; else fail "$what"; fi; }
absent() { local what="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$what"; "$@" | head -5 | sed 's/^/        /' >&2; else pass "$what"; fi; }

echo "== static"
expect "uuid is prayer@kimono.app" grep -q '"uuid": "prayer@kimono.app"' "$E/metadata.json"
expect "name is Kimono Prayer" grep -q '"name": "Kimono Prayer"' "$E/metadata.json"
absent "metadata doesn't say Mawaqit or AlAdhan" grep -niE 'mawaqit|aladhan|akramb\.com' "$E/metadata.json"
expect "state is kept apart from upstream's" grep -q "'kimono-prayer', 'state.json'" "$E/extension.js"
expect "the panel button is Kimono Prayer" grep -q "new PanelMenu.Button(0.0, 'Kimono Prayer')" "$E/extension.js"
absent "no mawaqit.net, AlAdhan or other source address in the extension" grep -rniE 'mawaqit\.net|aladhan|masjidbox\.com|https?://[a-z0-9]' "$E" --include=*.js --exclude-dir=tests
expect "a pasted link or mawaqit-kimono://connect connects" bash -c "grep -q 'mawaqit-kimono' '$E/kimono.js' && grep -q 'kimonoLink(query)' '$E/extension.js'"
expect "only feed links are taken" grep -qF 'api\/v1\/prayer\/feed\/' "$E/kimono.js"
expect "not connected, the entry asks for the link" grep -q "'Paste your Kimono Prayer link'" "$E/extension.js"
expect "the link is saved in the state" grep -q 'iconOnlyMenuBar === true, link}' "$E/extension.js"
expect "searches go through the link (q, lat/lon/tz)" bash -c "grep -q '\${this._state.link}?\${params}' '$E/extension.js' && grep -q 'q=\${encodeURIComponent(query)}' '$E/extension.js' && grep -q '&tz=' '$E/extension.js'"
expect "choosing a place PUTs its id" grep -q "method: 'PUT', body: {id: place.id}" "$E/extension.js"
expect "a dead link (401) asks to connect again" bash -c "grep -q 'statusCode === 401' '$E/extension.js' && grep -q 'Connect again from Kimono Prayer' '$E/extension.js'"
expect "the timetable becomes upstream's calendar" grep -q 'calendarFromTimetable(mine.timetable)' "$E/extension.js"
expect "the source line reads Kimono · <kind>" grep -q 'sourceLabel(this._state.place)' "$E/extension.js"
if (( failures )); then echo "$failures static check(s) failed" >&2; exit 1; fi

command -v node >/dev/null || { echo "node not on PATH; stopping after static checks" >&2; exit 1; }
echo "== syntax"
for f in "$E"/*.js "$E"/tests/*.js "$E"/tests/*.mjs; do node --check "$f"; done
echo "  ok    node --check"
echo "== test"
(cd "$E" && for t in tests/*.mjs; do node "$t"; done)
if command -v gjs >/dev/null; then
  (cd "$E" && for t in tests/*.js; do gjs -m "$t"; done)
else
  echo "  skip  gjs tests (gjs not installed)"
fi

if (( ZIP )); then
  echo "== zip"
  OUT="$ROOT/work/mawaqit-bar-dist"
  "$ROOT/apps/mawaqit-bar/build/gnome-zip.sh" "$CHECKOUT" "$OUT"
  Z="$OUT/prayer@kimono.app.shell-extension.zip"
  expect "the zip carries prayer@kimono.app's metadata" bash -c "unzip -p '$Z' metadata.json | grep -q '\"uuid\": \"prayer@kimono.app\"'"
  expect "  ...and every module" bash -c "for f in extension.js calendar.js kimono.js notifications.js presentation.js stylesheet.css; do unzip -l '$Z' \"\$f\" | grep -q \"\$f\" || exit 1; done"
  absent "  ...but no tests" bash -c "unzip -l '$Z' | grep -q 'tests/'"
  if (( failures )); then echo "$failures zip check(s) failed" >&2; exit 1; fi
fi
echo "gnome: all checks passed"
