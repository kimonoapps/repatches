You are repairing Kimono's patch set for an upstream app in this repository
(repatches). Your job is finished when `scripts/check.sh $APP` exits 0.

What broke: $REASON
The failing output is in work/$APP-check.log (read the end of it first).

How this repository works:
- upstream/$APP is a git submodule pinned to the upstream release. Never edit
  it, never move it.
- apps/$APP/patches/<part>/*.patch are applied in order by scripts/apply.sh
  into a worktree at work/$APP (git am --3way --keep-cr), then branding
  files are copied in (apps/$APP/branding/<part>/install.sh) and committed as
  "branding: ...".
- apps/$APP/intent/<part>.md says what each patch must achieve and where that
  lived upstream before. **The intent is the spec, not the old diff.** When
  upstream moved or rewrote code, re-implement the same behaviour in the new
  code.

To fix a patch:
1. `scripts/apply.sh $APP` (it stops at the first patch that fails; use
   `git -C work/$APP am --show-current-patch=diff` to see it).
2. Make the change by hand in work/$APP: resolve the conflict, or
   `git -C work/$APP am --skip` and re-create that patch's behaviour from the
   intent, then commit with the same subject line ("<part>: ...") and a body
   that says why and what must survive upstream changes. Keep each patch to
   one concern and keep diffs small. Preserve each file's line endings (some
   upstream files are CRLF).
3. `git -C work/$APP am --continue` for the remaining patches.
4. `scripts/export.sh $APP <part>` for each part you touched, then run
   `scripts/check.sh $APP` again from scratch. Repeat until it passes.
5. If upstream changed where something lives, update apps/$APP/intent/<part>.md
   (the "where" column, the file names) to match.

Hard rules:
- Do not edit anything under apps/*/checks/, .github/, scripts/, or
  upstream.env files. The workflow rejects the result if you do. If a check
  is wrong for the new upstream, stop, and explain why in your final message
  instead of changing it.
- Do not delete a behaviour to make a check pass.
- No git push, no network calls besides what the build tools need.

Finish with a short report: what upstream changed, what you changed in each
patch, and anything a human should look at.
