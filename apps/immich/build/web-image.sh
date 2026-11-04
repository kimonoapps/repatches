#!/usr/bin/env bash
# web-image.sh [tag] [checkout] — build the Kimono Photos server image (API + bundled web app) from a
# patched checkout. Upstream's server/Dockerfile builds the web app into /build/www, so this is the
# only image the web patches need. Never pushes.
#   tag      default ghcr.io/kimonoapps/kimono-photos-server:3.1.0-kimono.1
#   checkout default $REPATCHES_WORK, else work/immich (make it with scripts/apply.sh immich)
# Env: PLATFORM (default: the host's docker platform), BUILD_ARGS (extra args for docker buildx build).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TAG="${1:-ghcr.io/kimonoapps/kimono-photos-server:3.1.0-kimono.1}"
SRC="${2:-${REPATCHES_WORK:-$ROOT/work/immich}}"
[[ -f "$SRC/server/Dockerfile" ]] || { echo "no checkout at $SRC (run scripts/apply.sh immich first)" >&2; exit 1; }
# Refuse an unpatched/unbranded checkout: the image would silently be stock Immich.
[[ -f "$SRC/web/static/kimono-photos-mark.svg" ]] || { echo "$SRC has no Kimono branding (apply.sh not run?)" >&2; exit 1; }
[[ -n "$(git -C "$SRC" log -1 --format=%s --grep='^web: ')" ]] || { echo "$SRC has no web: patches applied" >&2; exit 1; }

COMMIT="$(git -C "$SRC" rev-parse --short HEAD)"
echo "building $TAG from $SRC ($COMMIT)"
docker buildx build \
  ${PLATFORM:+--platform "$PLATFORM"} \
  --file "$SRC/server/Dockerfile" \
  --build-arg BUILD_ID="kimono-$COMMIT" \
  --build-arg BUILD_IMAGE="$TAG" \
  --build-arg BUILD_SOURCE_REF="kimono" \
  --build-arg BUILD_SOURCE_COMMIT="$COMMIT" \
  --tag "$TAG" \
  --load \
  ${BUILD_ARGS:-} \
  "$SRC"
echo "built $TAG"
