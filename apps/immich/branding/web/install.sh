#!/usr/bin/env bash
# install.sh <checkout> — copy Kimono Photos' web brand assets over the checkout (binary files make bad
# patches). files/ mirrors checkout paths. Overwrites upstream's favicons/app icons in web/static and
# adds the logo SVGs that the web patches' Vite hook swaps in for @immich/ui's Immich logos.
# Regenerate files/ with tools/make-assets.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:?usage: install.sh <checkout>}"
[[ -d "$DEST/web/static" ]] || { echo "not an immich checkout: $DEST" >&2; exit 1; }
cp -R "$HERE/files/." "$DEST/"
echo "installed web branding ($(find "$HERE/files" -type f | wc -l | tr -d ' ') files)"
