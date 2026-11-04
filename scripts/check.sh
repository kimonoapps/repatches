#!/usr/bin/env bash
# check.sh <app> [--full] — apply every patch part from scratch and run the app's checks.
# Default is the quick gate (static checks, analysis, unit tests); --full adds the
# slow ones (APK build, server image build and its smoke test). Exit 0 = all good.
source "$(dirname "$0")/lib.sh"
load_app "$1"
FULL=0; [[ "${2:-}" == "--full" ]] && FULL=1
log="$ROOT/work/$APP-check.log"
mkdir -p "$ROOT/work"
{
  "$ROOT/scripts/apply.sh" "$APP"
  CHECKOUT="$ROOT/work/$APP"
  for check in "$APP_DIR"/checks/*.sh; do
    part="$(basename "$check" .sh)"
    echo "== $part"
    args=("$CHECKOUT")
    if (( FULL )); then
      case "$part" in
        mobile) args+=(--apk) ;;
        web) "$APP_DIR/build/web-image.sh" "repatches/$APP-check:local"; args+=(--image "repatches/$APP-check:local") ;;
      esac
    fi
    "$check" "${args[@]}"
  done
} 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
echo "log: ${log#$ROOT/}"
exit "$status"
