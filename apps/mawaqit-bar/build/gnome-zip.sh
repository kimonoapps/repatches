#!/usr/bin/env bash
# build/gnome-zip.sh <checkout> <out-dir> — the GNOME Shell extension zip, named after its uuid
# (install with: gnome-extensions install --force <zip>). Tests are left out, as upstream does.
set -euo pipefail
CO="$(cd "${1:?checkout required}" && pwd)"
OUT="${2:?out dir required}"; mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
EXT="$CO/gnome/mawaqit@akramb.com"
uuid="$(sed -n 's/^ *"uuid": *"\([^"]*\)".*/\1/p' "$EXT/metadata.json")"
[[ -n "$uuid" ]] || { echo "no uuid in $EXT/metadata.json" >&2; exit 1; }
rm -f "$OUT/$uuid.shell-extension.zip"
(cd "$EXT" && zip -q -r "$OUT/$uuid.shell-extension.zip" . -x 'tests/*')
echo "built $OUT/$uuid.shell-extension.zip"
