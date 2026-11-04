#!/usr/bin/env bash
# apply.sh <app> [part] — a fresh worktree of the pin at work/<app> (or $REPATCHES_WORK) with patches applied
# as commits on branch "kimono". The submodule itself is never modified.
source "$(dirname "$0")/lib.sh"
load_app "$1"
PART="${2:-}"
DEST="${REPATCHES_WORK:-$ROOT/work/$APP}"  # override to keep separate checkouts side by side
if [[ -e "$DEST" ]]; then
  git -C "$UPSTREAM" worktree remove --force "$DEST" 2>/dev/null || rm -rf "$DEST"
fi
git -C "$UPSTREAM" worktree prune
mkdir -p "$ROOT/work"
git -C "$UPSTREAM" worktree add -q -f -B "kimono-$(basename "$DEST")" "$DEST" "$PIN"
for part in $(parts_of "$PART"); do
  shopt -s nullglob
  patches=("$APP_DIR/patches/$part"/*.patch)
  shopt -u nullglob
  (( ${#patches[@]} )) || continue
  if ! git -C "$DEST" -c user.name=repatches -c user.email=repatches@kimono.invalid \
      am -q --3way --keep-cr "${patches[@]}"; then
    echo "FAILED applying $part patches; resolve in $DEST (git am --continue), then scripts/export.sh $APP $part" >&2
    exit 1
  fi
  echo "applied ${#patches[@]} $part patch(es)"
done
# Branding assets are copied in, not diffed: binary files make bad patches.
# They're committed as "branding: ..." so export.sh never sweeps them into a patch.
if [[ -x "$APP_DIR/branding/install.sh" ]]; then
  "$APP_DIR/branding/install.sh" "$DEST" ${PART:+"$PART"}
  if [[ -n "$(git -C "$DEST" status --porcelain)" ]]; then
    git -C "$DEST" add -A
    git -C "$DEST" -c user.name=repatches -c user.email=repatches@kimono.invalid \
      commit -q -m "branding: artwork copied in by apply.sh (not a patch)"
  fi
fi
echo "ready: ${DEST#$ROOT/}"
