#!/usr/bin/env bash
# install.sh <checkout> — copy Kimono Photos' phone artwork over upstream's.
# The PNGs are made by generate.mjs; every file copied must already exist
# upstream or be one the mobile patches expect (the adaptive icon layers),
# so an upstream rename shows up here as a failure instead of a stray file.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:?checkout required}"
expected_new=(
  mobile/android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png
  mobile/android/app/src/main/res/drawable-nodpi/ic_launcher_monochrome.png
)
cd "$HERE/files"
missing=0
while IFS= read -r -d '' f; do
  f="${f#./}"
  if [[ ! -e "$DEST/$f" ]] && [[ ! " ${expected_new[*]} " =~ " $f " ]]; then
    echo "branding/mobile: upstream no longer has $f" >&2; missing=1
  fi
done < <(find . -type f -print0)
(( missing == 0 )) || exit 1
find . -type f -print0 | while IFS= read -r -d '' f; do
  mkdir -p "$DEST/$(dirname "$f")" && cp "$f" "$DEST/$f"
done
echo "branding/mobile: copied $(find . -type f | wc -l | tr -d ' ') files"
