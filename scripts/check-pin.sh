#!/usr/bin/env bash
# check-pin.sh <app> — the submodule must sit exactly on UPSTREAM_TAG's commit.
source "$(dirname "$0")/lib.sh"
load_app "$1"
url="$(git -C "$UPSTREAM" remote get-url origin)"
tag_commit="$(git ls-remote --tags "$url" "refs/tags/$UPSTREAM_TAG^{}" "refs/tags/$UPSTREAM_TAG" | awk '{print $1}' | head -1)"
# ls-remote lists the peeled (^{}) line after the tag line; prefer it when present.
peeled="$(git ls-remote --tags "$url" "refs/tags/$UPSTREAM_TAG^{}" | awk '{print $1}')"
tag_commit="${peeled:-$tag_commit}"
[[ -n "$tag_commit" ]] || { echo "$APP: tag $UPSTREAM_TAG not found upstream" >&2; exit 1; }
if [[ "$tag_commit" != "$PIN" ]]; then
  echo "$APP: submodule is at $PIN but $UPSTREAM_TAG is $tag_commit" >&2; exit 1
fi
echo "$APP: pinned to $UPSTREAM_TAG ($PIN)"
