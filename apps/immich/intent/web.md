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
- **Colour.** Primary comes from `#8d7fb5 / #3b3357 / #e2dcf0`. `web/src/app.css` overrides
  `--immich-ui-primary-50…950` for light (`:root, .light`) and `.dark`, plus the legacy
  `--immich-primary` and `--immich-dark-primary` RGB triplets. Flat colours only, no gradients.
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
