#!/usr/bin/env bash
# export.sh <app> <part> — write the commits in work/<app> whose subject starts with
# "<part>: " back out as apps/<app>/patches/<part>/NNNN-*.patch. Commit your edits first.
source "$(dirname "$0")/lib.sh"
load_app "$1"
PART="${2:?part required (e.g. mobile, web)}"
DEST="${REPATCHES_WORK:-$ROOT/work/$APP}"  # override to keep separate checkouts side by side
OUT="$APP_DIR/patches/$PART"
mkdir -p "$OUT" && rm -f "$OUT"/*.patch
n=0
for c in $(git -C "$DEST" rev-list --reverse "$PIN..HEAD"); do
  subject="$(git -C "$DEST" log -1 --format=%s "$c")"
  [[ "$subject" == "$PART: "* ]] || continue
  n=$((n + 1))
  git -C "$DEST" format-patch -q -1 --zero-commit --no-signature --no-stat \
    --start-number "$n" -o "$OUT" "$c"
done
echo "exported $n $PART patch(es) to ${OUT#$ROOT/}"
