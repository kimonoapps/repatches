#!/usr/bin/env bash
# Shared helpers. Source, don't run.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_app() {
  APP="${1:?usage: $0 <app> ...}"
  APP_DIR="$ROOT/apps/$APP"
  UPSTREAM="$ROOT/upstream/$APP"
  [[ -f "$APP_DIR/upstream.env" ]] || { echo "unknown app: $APP" >&2; exit 1; }
  # shellcheck disable=SC1091
  source "$APP_DIR/upstream.env"
  [[ -e "$UPSTREAM/.git" ]] || git -C "$ROOT" submodule update --init --depth 1 "upstream/$APP"
  # The pin is the commit recorded for the submodule in repatches' index, not
  # wherever the submodule checkout happens to be.
  PIN="$(git -C "$ROOT" ls-files -s "upstream/$APP" | awk '{print $2}')"
  [[ -n "$PIN" ]] || { echo "upstream/$APP is not a submodule" >&2; exit 1; }
}

# Patch parts are the subdirectories of patches/, applied in sorted order.
parts_of() {
  local only="${1:-}"
  if [[ -n "$only" ]]; then echo "$only"; return; fi
  find "$APP_DIR/patches" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort
}
