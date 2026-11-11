#!/usr/bin/env bash
# checks/web.sh [checkout] [--image TAG] [--skip-build] — the behaviour gate for the web/server patches.
#
#   checkout      a patched checkout (default $REPATCHES_WORK, else work/immich; make one with
#                 scripts/apply.sh immich). Must include the web branding (apply.sh installs it).
#   --image TAG   also run the behaviour smoke test against a built server image
#                 (apps/immich/build/web-image.sh). Without it, only static + build checks run.
#   --skip-build  skip the pnpm install / type check / web build / unit test stage.
#
# Stages, cheapest first; exits non-zero on the first failing stage, after printing every failure in it.
#   1. static  no "Immich" in en.json values, page titles, manifest or app.html; brand assets installed;
#              promo/support/update nags and upstream links unreachable; server auto-launch hook present.
#   2. build   pnpm install, svelte-check, tsc, vite build (and the built bundle carries no Immich logo),
#              server type check + AuthService/ApiService unit tests.
#   3. smoke   docker compose: the image + postgres + valkey + a mock OIDC provider, oauth.autoLaunch on;
#              curl asserts the redirects, the escape hatch, the full OAuth round trip and sign-out.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CHECKOUT="" IMAGE="" SKIP_BUILD=0
while (($#)); do
  case "$1" in
    --image) IMAGE="${2:?--image needs a tag}"; shift 2 ;;
    --image=*) IMAGE="${1#*=}"; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) CHECKOUT="$1"; shift ;;
  esac
done
CO="$(cd "${CHECKOUT:-${REPATCHES_WORK:-$ROOT/work/immich}}" && pwd)"
[[ -f "$CO/server/Dockerfile" && -d "$CO/web" ]] || { echo "not an immich checkout: $CO" >&2; exit 2; }
PIN="$(git -C "$ROOT" ls-files -s upstream/immich | awk '{print $2}')"

FAILS=0
ok() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAILS=$((FAILS + 1)); }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
stage() { printf '\n== %s\n' "$*"; }
end_stage() { ((FAILS == 0)) || { printf '\n%d check(s) failed in this stage\n' "$FAILS"; exit 1; }; }
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
pnpm_() { corepack pnpm "$@"; }

echo "checkout: $CO"

# ─── 1. static ───────────────────────────────────────────────────────────────────────────────
stage "static"
cd "$CO"

immich_in_en() {
  node -e '
    const walk = (o, p) => Object.entries(o).flatMap(([k, v]) => typeof v === "object" ? walk(v, p + k + ".") : [[p + k, v]]);
    const hits = walk(require(process.argv[1]), "").filter(([, v]) => /immich/i.test(v));
    for (const [k, v] of hits) console.error(`    en.json ${k} = ${JSON.stringify(v)}`);
    process.exit(hits.length ? 1 : 0);' "$CO/i18n/en.json"
}
check "no en.json value names Immich" immich_in_en

no_matches() { # no_matches <description-for-output> <grep args...>: true when grep finds nothing
  local out; out="$(grep "${@:2}" 2>/dev/null || true)"
  [[ -z "$out" ]] || { printf '%s\n' "$out" | sed 's/^/    /' | head -20; return 1; }
}
check "no page <title> names Immich" no_matches titles -rnE '<title>[^<]*Immich|title: .Immich|Immich.;$' web/src
check "app.html (stencil/noscript) has no Immich" no_matches app -n 'Immich' web/src/app.html
manifest_ok() { node -e 'const m=require(process.argv[1]); process.exit(m.name==="Kimono Photos" && !/immich/i.test(JSON.stringify(m)) ? 0 : 1)' "$CO/web/static/manifest.json"; }
check "PWA manifest is Kimono Photos" manifest_ok

assets_ok() {
  local f missing=0
  for f in web/static/kimono-photos-mark.svg web/src/lib/assets/kimono/logo-icon.svg \
           web/src/lib/assets/kimono/logo-inline-light.svg web/src/lib/assets/kimono/logo-inline-dark.svg; do
    [[ -s "$f" ]] || { echo "    missing $f"; missing=1; }
  done
  # The icons must not be upstream's: compare with the pinned upstream blobs.
  for f in favicon.ico favicon.png favicon-16.png favicon-32.png favicon-48.png favicon-96.png favicon-144.png \
           apple-icon-180.png manifest-icon-192.maskable.png manifest-icon-512.maskable.png; do
    if [[ ! -s "web/static/$f" ]]; then echo "    missing web/static/$f"; missing=1
    elif [[ "$(git hash-object "web/static/$f")" == "$(git rev-parse "$PIN:web/static/$f" 2>/dev/null)" ]]; then
      echo "    web/static/$f is still upstream's"; missing=1
    fi
  done
  return $missing
}
check "brand assets installed (logos, favicons, app icons)" assets_ok
check "Vite swaps @immich/ui's logos" grep -q 'kimonoBrand()' web/vite.config.ts

# The Kata theme (paper, ink, Mincho, seals) is wired in at the root.
theme_ok() {
  local f=web/src/kimono.css missing=0 t
  grep -q "@import './kimono.css'" web/src/app.css || { echo "    app.css does not import kimono.css"; missing=1; }
  [[ -s $f ]] || { echo "    $f missing"; return 1; }
  for t in "--font-sans: var(--k-sans)" "--color-neutral-100" "--immich-ui-primary-500: #482f74" \
           "--immich-ui-light: #1d1417" "--radius-xl: 2px" "[data-k='seal']" "[data-k-nav='active']" \
           "#dashboard-navbar::after" "[data-k-avatar]"; do
    grep -qF -- "$t" "$f" || { echo "    kimono.css lacks: $t"; missing=1; }
  done
  # The hooks kimono.css relies on must still be injected into @immich/ui.
  for t in "data-k={icon ? 'icon' : 'seal'}" 'data-k-heading' "data-k-nav={active" 'data-k-avatar'; do
    grep -qF -- "$t" web/vite.config.ts || { echo "    vite.config.ts lacks hook: $t"; missing=1; }
  done
  grep -q 'data-k-avatar' web/src/lib/components/shared-components/UserAvatar.svelte || { echo "    UserAvatar lacks data-k-avatar"; missing=1; }
  # The theme must never reach into the map (MapLibre owns its canvas and controls).
  if grep -inE 'maplibre|mapbox|canvas' "$f" | grep -v '^\s*[0-9]*:\s*/\?\*' | grep -q .; then
    echo "    kimono.css targets the map: $(grep -inE 'maplibre|mapbox|canvas' "$f" | head -3 | tr '\n' ' ')"; missing=1
  fi
  return $missing
}
check "Kata theme wired in (kimono.css, @immich/ui hooks)" theme_ok
fonts_ok() {
  local f missing=0
  for f in zen-maru-gothic-latin-400-normal zen-maru-gothic-latin-500-normal zen-maru-gothic-latin-700-normal shippori-mincho-600-latin; do
    [[ -s "web/static/fonts/kimono/$f.woff2" ]] || { echo "    missing web/static/fonts/kimono/$f.woff2"; missing=1; }
  done
  return $missing
}
check "Kimono fonts installed (Zen Maru Gothic, Shippori Mincho)" fonts_ok

# Components that carry purchase/support/update nags or upstream links must not be mounted anywhere.
not_imported() {
  local hits=0 c
  for c in PurchaseInfo ServerStatus 'VersionAnnouncement.svelte' HelpAndFeedbackModal UserPurchaseSettings; do
    if grep -rlE "import .*${c}" web/src | grep -v "/${c%.svelte}\.svelte$" | grep -q .; then
      echo "    $c is still imported by: $(grep -rlE "import .*${c}" web/src | tr '\n' ' ')"; hits=1
    fi
  done
  return $hits
}
check "purchase, support and update-announcement UI unmounted" not_imported
# Upstream links may only remain inside those unmounted components.
check "no immich.app / GitHub / Discord links in mounted UI" no_matches links -rnE \
  --include='*.svelte' --include='*.ts' --exclude='*.spec.ts' \
  --exclude=HelpAndFeedbackModal.svelte --exclude=VersionAnnouncementModal.svelte --exclude=ServerStatus.svelte \
  --exclude-dir=purchasing --exclude-dir=buy --exclude-dir=link --exclude=license-utils.ts --exclude=route.ts \
  'https?://([a-z0-9.-]+\.)?immich\.app|github\.com/immich-app|discord\.immich' web/src
check "server: auto-launch redirect hook in the web index middleware" \
  grep -q 'redirectToOAuth(request, res)' server/src/services/api.service.ts
check "server: AuthService.getOAuthAutoLaunch present" grep -q 'async getOAuthAutoLaunch' server/src/services/auth.service.ts
# The phone app comes from Kimono: no store badges, F-Droid or Obtainium (all upstream's app), only /get-app.
no_store_ui() {
  local hits=0 c
  for c in AppDownloadModal ObtainiumConfigModal; do
    if grep -rlE "import .*${c}" web/src | grep -v "/${c}\.svelte$" | grep -q .; then
      echo "    $c is still imported by: $(grep -rlE "import .*${c}" web/src | tr '\n' ' ')"; hits=1
    fi
  done
  return $hits
}
check "app store / Obtainium links unmounted" no_store_ui
check "Get the app links go to /get-app" grep -q 'href="/get-app"' 'web/src/routes/(user)/utilities/UtilitiesMenu.svelte' web/src/routes/auth/onboarding/OnboardingMobileApp.svelte
check "server: /get-app redirects to KIMONO_GET_APP_URL" grep -q 'KIMONO_GET_APP_URL' server/src/services/api.service.ts
end_stage

# ─── 2. build ────────────────────────────────────────────────────────────────────────────────
if ((SKIP_BUILD == 0)); then
  stage "build (pnpm $(corepack pnpm -v 2>/dev/null || echo '?'), node $(node -v))"
  LOG="$(mktemp -d)"
  run() { # run <name> <cmd...>: quiet unless it fails
    local name="$1"; shift
    if "$@" >"$LOG/out" 2>&1; then ok "$name"; else bad "$name"; tail -40 "$LOG/out" | sed 's/^/    /'; end_stage; fi
  }
  export SHARP_IGNORE_GLOBAL_LIBVIPS=true
  run "pnpm install (sdk, plugin-sdk, web, server)" \
    pnpm_ --filter @immich/sdk --filter @immich/plugin-sdk --filter immich-web --filter immich install --frozen-lockfile
  run "build @immich/sdk + @immich/plugin-sdk" pnpm_ --filter @immich/sdk --filter @immich/plugin-sdk build
  run "web: svelte-check" pnpm_ --dir web run check:svelte
  run "web: tsc" pnpm_ --dir web run check:typescript
  run "web: vite build" pnpm_ --dir web run build
  bundle_ok() {
    [[ -f web/build/index.html ]] || return 1
    ! ls web/build/_app/immutable/assets 2>/dev/null | grep -q 'immich-logo' &&
      ls web/build/_app/immutable/assets | grep -q 'logo-inline' &&
      ! grep -q 'Immich' web/build/index.html
  }
  check "web bundle: Kimono logos in, Immich logos and name out of index.html" bundle_ok
  # The hooks must survive the real build (they run on @immich/ui inside node_modules).
  theme_bundle_ok() {
    grep -rqF 'Zen Maru Gothic Kimono' web/build/_app/immutable/assets/ &&
      grep -rqF 'data-k-variant' web/build/_app/immutable/ &&
      grep -rqF 'data-k-nav' web/build/_app/immutable/
  }
  check "web bundle: Kata theme CSS and seal/nav hooks compiled in" theme_bundle_ok
  run "server: tsc" pnpm_ --dir server exec tsc --noEmit
  run "server: AuthService/ApiService unit tests" pnpm_ --dir server exec vitest run --config test/vitest.config.mjs \
    src/services/auth.service.spec.ts src/services/api.service.spec.ts
  end_stage
fi

# ─── 3. smoke ────────────────────────────────────────────────────────────────────────────────
if [[ -z "$IMAGE" ]]; then
  printf '\nall static/build checks passed (no --image: behaviour smoke test skipped)\n'
  exit 0
fi
stage "smoke ($IMAGE)"
docker image inspect "$IMAGE" >/dev/null 2>&1 || { bad "image $IMAGE not found locally (build it with apps/immich/build/web-image.sh)"; end_stage; }

WORK="$(mktemp -d)"
PROJECT="kimono-web-check-$$"
compose() { docker compose -p "$PROJECT" -f "$WORK/compose.yaml" "$@"; }
cleanup() {
  local rc=$?
  if ((rc != 0)) && [[ -f "$WORK/compose.yaml" ]]; then
    echo "    --- containers ---"
    compose ps -a 2>/dev/null | sed 's/^/    /' || true
    echo "    --- server log (last 80 lines) ---"
    compose logs --no-color --tail 80 server 2>/dev/null | sed 's/^/    /' || true
  fi
  [[ -f "$WORK/compose.yaml" ]] && compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$WORK"
  exit $rc
}
trap cleanup EXIT INT TERM

# The config file Kimono renders (see the Kimono app definition): OAuth on, auto-launch on, password kept.
# allowInsecureRequests only because the mock provider speaks plain HTTP.
cat >"$WORK/config.json" <<'JSON'
{
  "oauth": {
    "enabled": true,
    "autoLaunch": true,
    "autoRegister": true,
    "allowInsecureRequests": true,
    "buttonText": "Sign in with Kimono",
    "clientId": "kimono-photos",
    "clientSecret": "smoke-secret",
    "issuerUrl": "http://oidc:8080/default",
    "scope": "openid email profile",
    "signingAlgorithm": "RS256",
    "tokenEndpointAuthMethod": "client_secret_post"
  },
  "passwordLogin": { "enabled": true },
  "machineLearning": { "enabled": false },
  "newVersionCheck": { "enabled": false },
  "reverseGeocoding": { "enabled": false },
  "map": { "enabled": true, "lightStyle": "http://style/style.json", "darkStyle": "http://style/style.json" }
}
JSON
# The map's style lives inside the compose network, so the map check needs no internet: one flat
# background colour that the check then looks for on screen.
MAP_GREEN='#2e8b57'
mkdir -p "$WORK/style"
cat >"$WORK/style/style.json" <<JSON
{ "version": 8, "name": "kimono-check", "sources": {},
  "layers": [{ "id": "ground", "type": "background", "paint": { "background-color": "$MAP_GREEN" } }] }
JSON
cat >"$WORK/style/default.conf" <<'NGINX'
server {
  listen 80;
  location / { root /usr/share/nginx/html; add_header Access-Control-Allow-Origin * always; }
}
NGINX
# The mock provider signs everyone in without a form, as one fixed person. Immich only accepts an
# OAuth first user who is admin (role claim, default "immich_role"), so the person carries it.
MOCK_CONFIG='{"interactiveLogin":false,"tokenCallbacks":[{"issuerId":"default","tokenExpiry":3600,"requestMappings":[{"requestParam":"grant_type","match":"*","claims":{"sub":"kimono-smoke","email":"smoke@kimono.test","name":"Smoke Test","immich_role":"admin","aud":["kimono-photos"]}}]}]}'
cat >"$WORK/compose.yaml" <<YAML
name: $PROJECT
services:
  server:
    image: $IMAGE
    environment:
      IMMICH_CONFIG_FILE: /config/config.json
      KIMONO_GET_APP_URL: https://kimono.smoke.test/get-app
      DB_HOSTNAME: database
      DB_USERNAME: immich
      DB_PASSWORD: smoke
      DB_DATABASE_NAME: immich
      REDIS_HOSTNAME: redis
      IMMICH_MACHINE_LEARNING_ENABLED: "false"
    volumes:
      - $WORK/config.json:/config/config.json:ro
    ports: ["127.0.0.1::2283"]
    # The server exits if Postgres isn't accepting connections yet (a fresh database is still
    # initialising), so start it only once the database and Redis report healthy.
    depends_on:
      database: { condition: service_healthy }
      redis: { condition: service_healthy }
      oidc: { condition: service_started }
  database:
    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
    environment:
      POSTGRES_USER: immich
      POSTGRES_PASSWORD: smoke
      POSTGRES_DB: immich
      POSTGRES_INITDB_ARGS: --data-checksums
    shm_size: 128mb
    # Over TCP: while the image initialises the database its temporary server takes only the socket.
    healthcheck:
      test: pg_isready -h 127.0.0.1 -U immich -d immich
      interval: 2s
  redis:
    image: docker.io/valkey/valkey:9
    healthcheck:
      test: redis-cli ping | grep -q PONG || exit 1
      interval: 2s
  oidc:
    image: ghcr.io/navikt/mock-oauth2-server:2.1.10
    environment:
      JSON_CONFIG: '$MOCK_CONFIG'
    ports: ["127.0.0.1::8080"]
  style:
    image: nginx:1.27-alpine
    volumes:
      - $WORK/style/style.json:/usr/share/nginx/html/style.json:ro
      - $WORK/style/default.conf:/etc/nginx/conf.d/default.conf:ro
YAML

compose up -d --quiet-pull >"$WORK/up.log" 2>&1 || { cat "$WORK/up.log"; bad "docker compose up"; end_stage; }
PORT="$(compose port server 2283 | awk -F: '{print $NF}')"
OIDC_PORT="$(compose port oidc 8080 | awk -F: '{print $NF}')"
APP="http://localhost:$PORT"
# The provider is "oidc:8080" to the server; route that name to its published port for curl.
CURL=(curl -sS --max-time 20 --connect-to "oidc:8080:127.0.0.1:$OIDC_PORT" -H 'Accept: text/html')

ready=0
for _ in $(seq 1 120); do
  if curl -sf --max-time 2 "$APP/api/server/ping" 2>/dev/null | grep -q pong; then ready=1; break; fi
  sleep 2
done
((ready)) && ok "server up on $APP" || { bad "server did not answer /api/server/ping within 240s"; end_stage; }

# head_of <url> [curl args]: prints "<status> <location>"
head_of() { local url="$1"; shift; "${CURL[@]}" -o /dev/null -D "$WORK/headers" -w '%{http_code} %{redirect_url}' "$@" "$url"; }
expect_idp() { # expect_idp <path>
  local res status loc
  res="$(head_of "$APP$1")"; status="${res%% *}"; loc="${res#* }"
  [[ "$status" == 302 ]] || { echo "    $1 -> $status (want 302)"; return 1; }
  [[ "$loc" == "http://oidc:8080/default/authorize?"* ]] || { echo "    $1 -> $loc"; return 1; }
  [[ "$loc" == *"redirect_uri=http%3A%2F%2Flocalhost%3A$PORT%2Fauth%2Flogin"* ]] || { echo "    redirect_uri wrong: $loc"; return 1; }
  [[ "$loc" == *"code_challenge="* && "$loc" == *"state="* ]] || { echo "    no state/PKCE: $loc"; return 1; }
  grep -qi '^set-cookie: immich_oauth_state=' "$WORK/headers" && grep -qi '^set-cookie: immich_oauth_code_verifier=' "$WORK/headers" ||
    { echo "    missing oauth state/verifier cookies"; return 1; }
}
expect_page() { # expect_page <path> [curl args]: 200 HTML, no redirect
  local path="$1"; shift; local res
  res="$(head_of "$APP$path" "$@")"
  [[ "$res" == "200 " ]] || { echo "    $path -> $res (want 200, no redirect)"; return 1; }
}
check "GET /auth/login redirects to the provider (state + PKCE cookies set)" expect_idp /auth/login
check "GET / redirects to the provider" expect_idp /
check "GET /auth/login?continue=/albums redirects to the provider" expect_idp '/auth/login?continue=%2Falbums'
check "escape hatch: /auth/login?autoLaunch=0 serves the page" expect_page '/auth/login?autoLaunch=0'
check "escape hatch: /auth/login?password=1 serves the page" expect_page '/auth/login?password=1'
check "OAuth callback /auth/login?code=…&state=… serves the page" expect_page '/auth/login?code=x&state=y'
check "deep links (/photos) still serve the app" expect_page /photos
get_app_ok() { [[ "$(head_of "$APP/get-app?for=ios")" == "302 https://kimono.smoke.test/get-app?for=ios" ]]; }
check "GET /get-app?for=ios redirects to Kimono's page, query kept" get_app_ok
share_ok() { [[ "$(head_of "$APP/s/missing")" == "404 " ]]; }
check "share links (/s/…) are not redirected" share_ok
api_ok() { [[ "$(curl -sS "$APP/api/server/ping")" == '{"res":"pong"}' ]] &&
  [[ "$(curl -sS -o /dev/null -w '%{http_code}' "$APP/api/users/me")" == 401 ]]; }
check "API unchanged: /api/server/ping pongs, /api/users/me is 401 without a session" api_ok
features_ok() { curl -sS "$APP/api/server/features" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const f=JSON.parse(s);process.exit(f.oauth&&f.oauthAutoLaunch&&f.passwordLogin?0:1)})'; }
check "server features: oauth + oauthAutoLaunch + passwordLogin" features_ok

# Full round trip, as a browser would: app -> provider -> back to /auth/login?code -> POST callback.
JAR="$WORK/jar"
round_trip() {
  local loc back body token
  loc="$("${CURL[@]}" -c "$JAR" -b "$JAR" -o /dev/null -w '%{redirect_url}' "$APP/auth/login")"
  back="$("${CURL[@]}" -o /dev/null -w '%{redirect_url}' "$loc")"
  [[ "$back" == "$APP/auth/login?code="* ]] || { echo "    provider sent us to: $back"; return 1; }
  body="$(curl -sS -c "$JAR" -b "$JAR" -H 'Content-Type: application/json' \
    -d "{\"url\":\"$back\"}" "$APP/api/oauth/callback")"
  token="$(node -e 'try{const b=JSON.parse(process.argv[1]);process.stdout.write(b.accessToken||"")}catch{}' "$body")"
  [[ -n "$token" ]] || { echo "    callback said: $body"; return 1; }
  echo "$token" >"$WORK/token"
}
check "full sign-in: redirect -> provider -> /auth/login?code -> /api/oauth/callback gives a session" round_trip
check "signed-in visitor at /auth/login is not redirected" expect_page /auth/login -b "$JAR"
# The map must actually draw (a blank map once shipped unnoticed): geotag photos, then open /map
# and the photo info panel in headless Chromium inside the compose network, light and dark, and
# require the style's colour on screen, the cluster marker, and nothing painted over the canvas.
JPEG_B64='/9j/2wBDAA0JCgsKCA0LCgsODg0PEyAVExISEyccHhcgLikxMC4pLSwzOko+MzZGNywtQFdBRkxOUlNSMj5aYVpQYEpRUk//2wBDAQ4ODhMREyYVFSZPNS01T09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0//wAARCAAYACADASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAP/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFgEBAQEAAAAAAAAAAAAAAAAAAAIE/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEQMRAD8AsA3KAAAAAAf/2Q=='
geotag() {
  local token ids=() id i
  token="$(cat "$WORK/token")"
  for i in 1 2 3; do
    { printf '%s' "$JPEG_B64" | base64 -d; printf 'kimono-%s' "$i"; } >"$WORK/geo$i.jpg"   # distinct checksums
    id="$(curl -sS -H "Authorization: Bearer $token" -F deviceAssetId=geo$i -F deviceId=check \
      -F fileCreatedAt=2026-10-0${i}T10:00:00.000Z -F fileModifiedAt=2026-10-0${i}T10:00:00.000Z \
      -F "assetData=@$WORK/geo$i.jpg;type=image/jpeg" "$APP/api/assets" |
      node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).id||""))')"
    [[ -n "$id" ]] || { echo "    upload $i failed"; return 1; }
    ids+=("\"$id\"")
  done
  # Kyoto, set through the API (as a person would in the info panel) once metadata extraction is done.
  local body; body="{\"ids\":[$(IFS=,; echo "${ids[*]}")],\"latitude\":35.0116,\"longitude\":135.7681}"
  for _ in $(seq 1 30); do
    curl -sS -o /dev/null -X PUT -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d "$body" "$APP/api/assets"
    [[ "$(curl -sS -H "Authorization: Bearer $token" "$APP/api/map/markers" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).length))')" -ge 3 ]] &&
      { echo "${ids[0]//\"/}" >"$WORK/geo-asset"; return 0; }
    sleep 2
  done
  echo "    /api/map/markers never listed the geotagged photos"; return 1
}
check "seed: three photos geotagged in Kyoto" geotag
cat >"$WORK/map-check.mjs" <<'JS'
// Runs in mcr.microsoft.com/playwright on the compose network. argv: token assetId green
import { chromium } from 'playwright';
const [token, assetId, green] = process.argv.slice(2);
const want = [1, 3, 5].map((i) => parseInt(green.slice(i, i + 2), 16));
const base = 'http://server:2283';
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
let failed = 0;
const say = (ok, msg) => { console.log(`${ok ? 'PASS' : 'FAIL'} ${msg}`); if (!ok) failed++; };
// Share of the clip that is the style colour, measured from a real screenshot (what a person sees).
const greenShare = async (page, box) => {
  const png = await page.screenshot({ clip: box });
  return page.evaluate(async ({ b64, want }) => {
    const img = new Image(); img.src = `data:image/png;base64,${b64}`; await img.decode();
    const c = Object.assign(document.createElement('canvas'), { width: img.width, height: img.height });
    const g = c.getContext('2d'); g.drawImage(img, 0, 0);
    const d = g.getImageData(0, 0, c.width, c.height).data; let hit = 0;
    for (let i = 0; i < d.length; i += 4) if (Math.abs(d[i] - want[0]) + Math.abs(d[i + 1] - want[1]) + Math.abs(d[i + 2] - want[2]) < 24) hit++;
    return hit / (d.length / 4);
  }, { b64: png.toString('base64'), want });
};
const covered = (page) => page.evaluate(() => {
  const cv = document.querySelector('.maplibregl-canvas'); const r = cv.getBoundingClientRect(); const bad = [];
  for (const [fx, fy] of [[0.25, 0.25], [0.75, 0.3], [0.5, 0.75], [0.3, 0.8]]) {
    const el = document.elementFromPoint(r.x + r.width * fx, r.y + r.height * fy);
    if (!el || !(el === cv || el.closest('.maplibregl-map'))) bad.push(el ? el.tagName + '.' + el.className : 'nothing');
  }
  return bad;
});
for (const scheme of ['light', 'dark']) {
  for (const [label, width] of [['desktop', 1280], ['phone', 390]]) {
    const ctx = await browser.newContext({ colorScheme: scheme, viewport: { width, height: 844 } });
    await ctx.addCookies([{ name: 'immich_access_token', value: token, domain: 'server', path: '/' },
      { name: 'immich_is_authenticated', value: 'true', domain: 'server', path: '/' }]);
    const page = await ctx.newPage();
    await page.goto(`${base}/map`);
    const ready = await page.waitForSelector('.maplibregl-marker', { timeout: 45000 }).then(() => true, () => false);
    say(ready, `${scheme} ${label} /map: cluster marker drawn`);
    if (ready) {
      await page.waitForTimeout(1500);
      const box = await page.locator('.maplibregl-canvas').boundingBox();
      const share = await greenShare(page, box);
      say(share > 0.5, `${scheme} ${label} /map: style colour covers ${(share * 100).toFixed(0)}% of the map (need >50%)`);
      const bad = await covered(page);
      say(bad.length === 0, `${scheme} ${label} /map: nothing painted over the map${bad.length ? ' (' + bad.join(', ') + ')' : ''}`);
    }
    if (label === 'desktop') {
      await page.goto(`${base}/photos/${assetId}`); await page.waitForTimeout(1500); await page.keyboard.press('i');
      const mini = await page.waitForSelector('#detail-panel .maplibregl-canvas, .maplibregl-canvas', { timeout: 30000 }).then(() => true, () => false);
      await page.waitForTimeout(3000);
      if (mini) {
        const box = await page.locator('.maplibregl-canvas').boundingBox();
        const share = await greenShare(page, box);
        say(share > 0.4, `${scheme} info-panel mini-map: style colour covers ${(share * 100).toFixed(0)}% (need >40%)`);
      } else say(false, `${scheme} info-panel mini-map: no map canvas`);
    }
    await ctx.close();
  }
}
await browser.close();
process.exit(failed ? 1 : 0);
JS
map_renders() {
  local out
  out="$(docker run --rm --network "${PROJECT}_default" -v "$WORK/map-check.mjs:/check/map-check.mjs:ro" \
    mcr.microsoft.com/playwright:v1.56.1-noble bash -c \
    'cd /check && npm i --silent --no-save --no-audit --no-fund playwright@1.56.1 >/dev/null 2>&1 && node map-check.mjs "$@"' _ \
    "$(cat "$WORK/token")" "$(cat "$WORK/geo-asset")" "$MAP_GREEN" 2>&1)"
  local rc=$?
  printf '%s\n' "$out" | sed 's/^/    /'
  return $rc
}
check "map draws (light/dark, desktop/phone, /map and the info-panel mini-map)" map_renders

signout() {
  local body
  # As the browser does: the session and auth-type cookies set by the callback.
  body="$(curl -sS -X POST -b "$JAR" "$APP/api/auth/logout")"
  node -e 'const b=JSON.parse(process.argv[1]);process.exit(b.successful&&String(b.redirectUri).startsWith("http://oidc:8080/default/endsession")?0:1)' "$body" ||
    { echo "    logout said: $body"; return 1; }
}
check "sign-out lands on the provider's end-session endpoint" signout

end_stage
printf '\nall web checks passed\n'
