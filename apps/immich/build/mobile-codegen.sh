#!/usr/bin/env bash
# mobile-codegen.sh [checkout] — fetch the phone app's packages and generate its code, as upstream's CI does.
# Since v3.3 upstream commits none of it: the Dart API client (mobile/generated/openapi), build_runner's
# output, the Drift migrations and schema tests, Pigeon's platform code and the translation keys all come
# from `mise //mobile:install:ci` and `mise //mobile:codegen`. Run it after apply.sh, so the client and the
# translations are generated from the patched tree (the web patches own i18n/en.json).
#   checkout  default $REPATCHES_WORK, else work/immich
# Needs mise with upstream's tools installed (CI: .github/actions/immich-toolchain).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CO="$(cd "${1:-${REPATCHES_WORK:-$ROOT/work/immich}}" && pwd)"
[[ -f "$CO/mise.toml" && -d "$CO/mobile/lib" ]] || { echo "not an immich checkout: $CO" >&2; exit 2; }
command -v mise >/dev/null || { echo "mise not on PATH (https://mise.jdx.dev); it runs upstream's codegen" >&2; exit 1; }
export MISE_TRUSTED_CONFIG_PATHS="$CO${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}"
cd "$CO"
# codegen's translation step formats i18n/ first with the root package's prettier.
pnpm --filter immich-monorepo install --frozen-lockfile
cd mobile
mise //mobile:install:ci
mise //mobile:codegen
