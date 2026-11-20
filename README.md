# repatches

Upstream apps, patched into Kimono apps. Each app is an upstream release pinned
as a git submodule, plus a small patch series and artwork that make it look and
behave like part of Kimono. Nothing upstream is forked or vendored.

| App | Upstream | Becomes | Outputs |
| --- | --- | --- | --- |
| `immich` | [immich-app/immich](https://github.com/immich-app/immich) `v3.3.6` | Kimono Photos | server image (web included), Android APK, iPhone (TestFlight) |
| `mawaqit-bar` | [akramboussanni/mawaqit-bar](https://github.com/akramboussanni/mawaqit-bar) `v1.2.2` | Kimono Prayer (menu bar / top bar) | Mac app (DMG, zip), GNOME extension zip |

## Layout

```
upstream/<app>/                 submodule, exactly the pinned release (never edited)
apps/<app>/
  upstream.env                  UPSTREAM_TAG — CI checks the submodule is that tag
  patches/<part>/NNNN-*.patch   the changes, one concern per patch (immich: mobile, web; mawaqit-bar: macos, gnome)
  branding/<part>/              artwork copied over upstream's (binary, so not patches)
  intent/<part>.md              what each patch must achieve: the spec repairs work from
  checks/<part>.sh              the gate: identity, behaviour, builds
  build/                        build scripts (images, apps, zips)
scripts/                        apply / export / check, shared by every app
work/                           patched checkouts (git-ignored)
```

## Working on patches

```bash
git submodule update --init --depth 1
scripts/apply.sh immich             # work/immich: pin + patches as commits + branding
# edit in work/immich, commit with a subject starting "mobile: " or "web: "
scripts/export.sh immich mobile     # commits → apps/immich/patches/mobile/
scripts/check.sh immich             # reapply from scratch and run the quick checks
scripts/check.sh immich --full      # also build the APK and server image
scripts/check.sh mawaqit-bar --full # the Mac app (needs a Mac) and the GNOME zip
```

The commit body is part of the patch. It says why the change exists and what
must survive upstream changes, because that's what a repair works from when
the diff no longer applies. `REPATCHES_WORK=<dir>` keeps a second checkout
beside the first.

## Releases

Tag `immich/v<upstream>-kimono.<n>`, for example `immich/v3.1.0-kimono.1`. That
publishes three things:

- `ghcr.io/kimonoapps/kimono-photos-server:3.1.0-kimono.1`
- the signed APK, on the GitHub release
- the iPhone build, to TestFlight

Phones get build number `<upstream build> × 100 + n`, so every release
outranks the last one.

Kimono Prayer's tag is `mawaqit-bar/v<upstream>-kimono.<n>`, e.g.
`mawaqit-bar/v1.2.2-kimono.1`. It puts `kimono-prayer-<version>.dmg`, its
`-macos.zip` and `prayer@kimono.app.shell-extension.zip` on the GitHub release.
The Mac build number is `<major·minor·patch as 10203> × 100 + n`. The Mac app is
signed and notarized only if the optional Developer ID secrets below are set;
otherwise it's ad-hoc signed and Gatekeeper asks on first open.

## Following upstream

`Follow upstream releases` runs every morning. When an app has a newer
upstream release, it moves the pin on `bump/<app>-<tag>`, reapplies the
patches and runs the quick checks:

- **Patches still apply and pass:** it opens a PR. The PR's CI runs the full
  builds.
- **They don't:** Claude Code repairs the patches from `intent/` until
  `scripts/check.sh` passes, then a PR says so. If it can't get the checks to
  pass, the PR opens as a draft with the log.

`Repair a broken main` does the same when a build on `main` fails.

The repair can't touch `apps/*/checks/`, `.github/`, `scripts/` or
`upstream.env`: the workflow throws its result away if it does, and
CODEOWNERS covers those paths too. Merging is always a person's call.

`patched/<app>` is published on every push to `main`. It is generated: one
commit of pure upstream, then one with Kimono's changes. Read and diff it on
GitHub, but never edit it.

## Repository settings this needs

| Secret | For |
| --- | --- |
| `GHCR_TOKEN` (+ `GHCR_USERNAME`), optional | only if an org policy stops the built-in token publishing `ghcr.io/kimonoapps/kimono-photos-server` |
| `KIMONO_ANDROID_KEYSTORE`, `KIMONO_ANDROID_KEYSTORE_PASSWORD` | in the `mobile-release` environment: the Kimono signing key (base64 .jks, alias `kimono`) |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY`, `APPLE_TEAM_ID` | in `mobile-release`: App Store Connect API key for TestFlight |
| `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` | the repair job (`claude setup-token` makes the latter) |
| `REPATCHES_BOT_TOKEN` | pushes and PRs from the daily job, so their CI runs (contents + pull-requests write) |
| `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD`, optional | Kimono Prayer's Mac app: Developer ID signing and notarization (the same secrets mawaqit-bar's own release uses) |

The `mobile-release` environment should allow only `immich/v*` tags.

Kimono's side of Kimono Photos lives in the kimono repo
(`apps/portal/app-definitions/immich/app.json`): the image, the
`app.kimono.photos:///oauth-callback` redirect URI, and the phone setup step
that opens `kimono-photos://connect?server=…`.

Kimono's side of Kimono Prayer is Prayer in the kimono repo
(`apps/portal/src/lib/prayer`, `apps/portal/src/app/api/v1/prayer`): the
personal link `…/api/v1/prayer/feed/<token>` the apps read through, and the
`mawaqit-kimono://connect?link=…` address its Connect button opens.
