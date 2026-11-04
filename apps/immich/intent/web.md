# Immich web/server patches: intent

What `patches/web/` + `branding/web/` guarantee for Kimono Photos. When upstream moves code, re-create
each behaviour wherever it now lives. `checks/web.sh` is the gate: static checks, build, then a
docker smoke test (`--image`). Locations are as of Immich v3.1.0.

## 0001 Branding (`web: brand the web app as Kimono Photos`)

- **Logos.** Every `@immich/ui` `<Logo>` and the `immichLogo` export show Kimono Photos' bloom
  (icon) or lockup (inline/stacked; light and dark). Lives in `web/vite.config.ts`: the `kimonoBrand`
  plugin redirects `@immich/ui`'s `assets/immich-logo*.svg` imports (the package's
  `services/logo-manager.svelte.js` and `index.js`) to `web/src/lib/assets/kimono/*.svg`. It also
  rewrites the `alt` text in `components/Logo/Logo.svelte`. If `@immich/ui` renames its assets or
  exports a logo setter, adapt the hook. Don't edit the individual call sites.
- **Icons.** Favicons, the apple-touch icon and the PWA maskable icons in `web/static/` are Kimono's.
  They are binary, copied by `branding/web/install.sh` from `branding/web/files/` (regenerate with
  `branding/web/tools/make-assets.sh`, which uses Kimono's own bloom renderer and Shippori Mincho).
- **Titles.** Tabs read `<page> - Kimono Photos`, or `Kimono Photos` alone. This is set in
  `web/src/routes/+layout.svelte` (`<svelte:head><title>`), the default `meta.title` in
  `web/src/routes/+layout.ts`, and the shared-link pages (`lib/components/pages/SharedLink*Page.svelte`).
- **Manifest.** `web/static/manifest.json`: name `Kimono Photos`, short_name `Photos`, Kimono paper
  and plum colours.
- **Boot screen.** `web/src/app.html`: the pre-boot `#stencil` shows `/kimono-photos-mark.svg` and
  does not spin. The `<noscript>` text names Kimono Photos.
- **Colour, type and controls** are patch 0005's job, not this one.
- **Auth pages are flat.** `lib/components/layouts/AuthPageLayout.svelte` drops the huge blurred
  logo backdrop (a plain surface instead), and its header shows the inline lockup.
- **Misc.** The "About" modal (`lib/modals/ServerAboutModal.svelte`) and the truncated server error
  toast (`lib/utils/handle-error.ts`) don't say Immich.

## 0002 English copy (`web: say Kimono Photos instead of Immich in English strings`)

- No **value** in `i18n/en.json` contains "Immich" (case-insensitive). Keys stay unchanged.
  - The file is shared with the phone app, so mobile-only strings are covered too. The web part
    owns this file; mobile patches don't touch it.
  - Use "Kimono Photos" for the product, and "your Kimono administrator" or "whoever runs your
    Kimono" for help.
  - Promo copy becomes short and neutral: purchase panel, buy, version announcement, third-party
    support, Discord/GitHub help.
- Keep ICU placeholders and `<tags>` intact.
- "Login" reads "Sign in" (`login`, `to_login`): Kimono's word, seen on the fallback form.
- Only `en.json` is edited. Other locales are untouched.

## 0003 No nags or upstream links (`web: remove upstream promotion, support links and update nags`)

- **Sidebar bottom** (`lib/components/shared-components/side-bar/BottomInfo.svelte`): storage only.
  `PurchaseInfo` (buy/supporter) and `ServerStatus` (version, "update available" link) are not
  mounted.
- **User settings** (`routes/(user)/user-settings/UserSettingsList.svelte`): no Purchase section.
- **Account panel** (`lib/components/shared-components/navigation-bar/AccountInfoPanel.svelte`): no
  "Support & feedback" button, so `HelpAndFeedbackModal` (docs/GitHub/Discord) is unreachable.
- **No release announcement modal.** `<VersionAnnouncement />` is removed from
  `routes/+layout.svelte`.
- **No "My Immich link" command** (copies a `my.immich.app` URL) in `lib/commands.ts`.
- **Error page** (`routes/ErrorLayout.svelte`): no Discord / changelog / docker-help footer.
- **No `docs.immich.app` links** in admin/onboarding/maintenance/duplicates copy. The text stays,
  the `<Link>` goes: `AuthDisableLoginConfirmModal`, `StorageTemplateSettings`, `AuthSettings`,
  `MapSettings`, `OnboardingBackup`, `OnboardingStorageTemplate`, `routes/maintenance/+page.svelte`,
  and the duplicates utility page.
- **Out of scope.** `/buy` and `/link` routes, and the components above, stay in the tree but are
  unmounted. Server emails (`server/src/emails/*`) are not rebranded; Kimono ships SMTP off.

## 0004 Straight to Kimono sign-in (`web: send signed-out visitors straight to Kimono sign-in`)

- **Server redirect.**
  - **When:** a GET/HEAD for `/` or `/auth/login`, with `oauth.enabled && oauth.autoLaunch`, and
    no valid session cookie.
  - **Response:** a **302** to the provider's authorize URL. It sets the same
    `immich_oauth_state` and `immich_oauth_code_verifier` cookies as `POST /api/oauth/authorize`,
    with `redirect_uri = <origin>/auth/login`. That is the URI the web app uses, so upstream's
    callback page completes the sign-in.
  - **Origin:** `server.externalDomain` when it has the request's host, else the request origin.
  - **Where it lives:**
    - The web index catch-all middleware: `ApiService.ssr` / `redirectToOAuth` in
      `server/src/services/api.service.ts`, mounted by `configureExpress` in
      `server/src/app.common.ts` after `sirv`.
    - The logic in `AuthService.getOAuthAutoLaunch` and `isAuthenticatedRequest`
      (`server/src/services/auth.service.ts`).
- **Never redirected:**
  - `?autoLaunch=0` and `?password=1|true`: the escape hatch. It shows upstream's password form if
    password login is enabled. These are upstream's own opt-outs in `web/src/lib/utils.ts`
    `oauth.isAutoLaunchDisabled`.
  - OAuth callbacks (`?code=`, `?error=`).
  - Signed-in visitors, `/api`, share links, and every other route.
- **Provider unreachable:** log a warning and serve the app as usual. The client then shows the
  error and any password form.
- **No flash on the client.** `routes/auth/login/+page.svelte` draws a flat full-screen cover while
  auto-launching or completing a callback. Deep links reach `/auth/login` client-side, so the server
  302 doesn't apply there. The form appears only on error or opt-out.
- **Sign-out** is unchanged upstream behaviour. For an OAuth session (`immich_auth_type=oauth`
  cookie), `POST /api/auth/logout` returns the provider's end-session URL: `oauth.endSessionEndpoint`
  or discovery's `end_session_endpoint`. The browser lands on Kimono's sign-out, not the Immich form.
- **No API changes.** The phone app depends on the API.
- **Tests:** unit tests in `server/src/services/auth.service.spec.ts` (`getOAuthAutoLaunch`), and
  the smoke test in `checks/web.sh`.

## 0005 Kimono's look (`web: dress the web app in Kimono's paper, ink and seals`)

Source of truth: `kimono/docs/design-system.md` and `kimono/packages/ui/src/styles/tokens.css`.
Photos must look like the same product as the Kimono Portal.

- **Mechanism.**
  - All styling is in one **unlayered** stylesheet, `web/src/kimono.css`, imported from
    `web/src/app.css` right after `@immich/ui/theme/default.css`.
  - Tailwind v4 keeps theme variables and utilities in cascade layers, so plain `:root` / `.dark`
    custom properties and rules in an unlayered file win without editing components. Keep it
    unlayered.
  - Don't restyle individual components. Re-point variables, or add a data attribute through
    the Vite hook.
- **Hooks.** The `kimonoBrand` plugin's `transform` in `web/vite.config.ts` adds attributes to
  `@immich/ui` sources:
  - `internal/Button.svelte`: `data-k="seal"|"icon"`, `data-k-variant`, `data-k-color`
  - `Heading/Heading.svelte`: `data-k-heading`
  - `Navbar/NavbarItem.svelte`: `data-k-nav="active"|"idle"`
  - `Avatar/Avatar.svelte`: `data-k-avatar`
  - Immich's own `lib/components/shared-components/UserAvatar.svelte` carries `data-k-avatar`.
  - If `@immich/ui` changes these files, re-find the equivalent spot. `checks/web.sh` checks that
    the attributes reach the built bundle.
  - In `vite dev` `@immich/ui` is pre-bundled, so the hooks only show in `vite build` output.
- **Paper and ink.**
  - Tailwind's `neutral/gray/zinc/slate/stone` scales are one warm ramp, from paper `#fffdf8` to
    urushi `#1d1417`. `@immich/ui`'s `light-*`/`dark-*` scales are built on neutral, so they
    follow.
  - `--color-white` and `--color-black` are paper and plum-black.
  - `--immich-ui-light/dark/gray/muted/default-border` and the legacy `--immich-*` triplets are
    re-pointed.
  - Light paper is the default: sheet `#fbf7ef`, ground `#f7f1e8`, fold `#ebe2d3`, hair
    `#ddd0bf`, ink `#24221f`.
  - Dark is plum-black urushi (`#1d1417` / `#2a1d22`, paper-toned type), never grey.
  - `web/src/app.html`'s pre-paint `html.light` / `html.dark` colours match.
- **Colour roles.**
  - Primary is Photos' deep `#482f74` (pale `#e2dcf0`, accent `#8d7fb5`); dark mode uses the
    pale ramp.
  - Danger is suō `#a84d63`, success is moss, warning is wood, info is plum.
- **Type.** UI text is Zen Maru Gothic (`--font-sans`). Shippori Mincho names things: `<Heading>`,
  the page title `#user-page-header`, and album titles. Fonts are binary branding files in
  `web/static/fonts/kimono/` (`branding/web/files/`).
- **Corners and depth.**
  - `--radius-*`: 1px for controls, 2px for surfaces.
  - Shadow utilities become a 1px plum hairline, and backdrop blur is off.
  - Control bars (`.h-control-bar`) are flat planks, not capsules.
- **Seals, not pills.** Buttons with text are carved hanko blocks: 2px corners, a 2px base, a
  carved inner ring on inked faces, and they sink 1px when pressed.
  - Filled: inked in the accent.
  - Filled-secondary and outline: a quiet seal (fold paper, hair base, no ring).
  - Danger: a rose wash, inked on hover.
  - Ghost: a plain word, unless Immich gave it a surface, in which case it becomes a quiet seal.
  - Icon-only buttons are square-cut.
- **Sidebar.** No pills on the right. The chosen room is a hover-paper row with a 3px marker in
  Photos' colour.
- **The cord.** `#dashboard-navbar` has 2px plum over 1px sakura underneath, as under every
  Kimono header.
- **Portraits.** People without a picture get their initial in plum Mincho on fold paper, never
  Immich's random colour disc.
- **Hands off the map.** The theme never styles MapLibre (`.maplibregl-*`, its canvas, or its
  controls), and nothing it adds may sit over the map.
  - `/map` and the info-panel mini-map must draw, light and dark, desktop and phone.
  - `checks/web.sh` checks this statically (`kimono.css` must not mention maplibre/mapbox/canvas)
    and in the smoke test. There it geotags photos, serves a one-colour style inside the compose
    network, and has headless Chromium require that colour on screen, the cluster marker, and an
    uncovered canvas.

