#!/usr/bin/env bash
# install.sh <checkout> — copy Kimono Prayer's Mac icon and DMG background over upstream's.
# The files are made by generate.mjs. Every file copied must already exist upstream, so an
# upstream rename shows up here as a failure instead of a stray file.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:?checkout required}"
cd "$HERE/files"
missing=0
while IFS= read -r -d '' f; do
  f="${f#./}"
  if [[ ! -e "$DEST/$f" ]]; then echo "branding/macos: upstream no longer has $f" >&2; missing=1; fi
done < <(find . -type f -print0)
(( missing == 0 )) || exit 1
find . -type f -print0 | while IFS= read -r -d '' f; do cp "$f" "$DEST/$f"; done
echo "branding/macos: copied $(find . -type f | wc -l | tr -d ' ') files"
