#!/usr/bin/env bash
# versions.sh <app> — print shell assignments describing what a build is:
#   UPSTREAM_TAG     v3.1.0                 (apps/<app>/upstream.env)
#   KIMONO_REVISION  1                      (from a release tag <app>/v3.1.0-kimono.N, else 0)
#   VERSION          3.1.0-kimono.1         (image tag, release name)
#   BUILD_NAME       3.1.0                  (what phones show)
#   BUILD_NUMBER     305701                 (upstream build × 100 + revision: always increases)
#   FLUTTER_VERSION  3.44.8                 (upstream mobile/mise.toml)
source "$(dirname "$0")/lib.sh"
load_app "$1"
ref="${GITHUB_REF_NAME:-}"
rev=0
if [[ "$ref" =~ ^$APP/v[0-9.]+-kimono\.([0-9]+)$ ]]; then rev="${BASH_REMATCH[1]}"; fi
name="${UPSTREAM_TAG#v}"
pubspec="$(git -C "$UPSTREAM" show "$PIN:mobile/pubspec.yaml" 2>/dev/null || true)"
upstream_build="$(sed -n 's/^version: *[0-9.]*+\([0-9]*\).*/\1/p' <<<"$pubspec")"
flutter="$(git -C "$UPSTREAM" show "$PIN:mobile/mise.toml" 2>/dev/null | sed -n 's/^"aqua:flutter\/flutter" *= *"\(.*\)"/\1/p')"
echo "UPSTREAM_TAG=$UPSTREAM_TAG"
echo "KIMONO_REVISION=$rev"
echo "VERSION=$name-kimono.$rev"
echo "BUILD_NAME=$name"
echo "BUILD_NUMBER=$(( ${upstream_build:-0} * 100 + rev ))"
echo "FLUTTER_VERSION=$flutter"
