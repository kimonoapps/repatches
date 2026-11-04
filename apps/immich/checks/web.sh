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
    echo "    --- server warnings/errors (last 15) ---"
    compose logs --no-color server 2>/dev/null | grep -E 'WARN|ERROR' | tail -15 | sed 's/^/    /' || true
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
  "reverseGeocoding": { "enabled": false }
}
JSON
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
      DB_HOSTNAME: database
      DB_USERNAME: immich
      DB_PASSWORD: smoke
      DB_DATABASE_NAME: immich
      REDIS_HOSTNAME: redis
      IMMICH_MACHINE_LEARNING_ENABLED: "false"
    volumes:
      - $WORK/config.json:/config/config.json:ro
    ports: ["127.0.0.1::2283"]
    depends_on: [database, redis, oidc]
  database:
    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
    environment:
      POSTGRES_USER: immich
      POSTGRES_PASSWORD: smoke
      POSTGRES_DB: immich
      POSTGRES_INITDB_ARGS: --data-checksums
    shm_size: 128mb
  redis:
    image: docker.io/valkey/valkey:9
  oidc:
    image: ghcr.io/navikt/mock-oauth2-server:2.1.10
    environment:
      JSON_CONFIG: '$MOCK_CONFIG'
    ports: ["127.0.0.1::8080"]
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
