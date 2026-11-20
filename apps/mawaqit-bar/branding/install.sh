#!/usr/bin/env bash
# install.sh <checkout> [part] — run each part's branding/<part>/install.sh against the checkout.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$1"; ONLY="${2:-}"
for dir in "$HERE"/*/; do
  part="$(basename "$dir")"
  [[ -z "$ONLY" || "$ONLY" == "$part" ]] || continue
  [[ -x "$dir/install.sh" ]] && "$dir/install.sh" "$DEST"
done
true
