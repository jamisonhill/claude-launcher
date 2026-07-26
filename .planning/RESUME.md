# Resume: Claude Launcher

**Paused:** 2026-07-25, evening
**Reason:** v1.0.0 shipped, verified end to end, and installable via Homebrew.
Clean stopping point — nothing is broken or half-finished.
**Phase:** 5 of 5 complete. Phase 6 (optional polish) not started.

---

## Where things stand

Everything asked for is done and verified. There is **no blocker** and no
partially-applied change; the working tree is clean and pushed.

Verified this session, not assumed:
- Apple notarization returned `status: Accepted`; ticket stapled
- `spctl --assess` → `accepted / source=Notarized Developer ID`
- `brew install --cask` succeeded, and the app **launched with no Gatekeeper
  prompt** despite Homebrew setting the quarantine flag — the real test
- GitHub Actions build passed on a clean `macos-14` runner
- The curated library survived the Homebrew reinstall (settings live in
  `~/Library/Application Support/ClaudeLauncher`, which the cask only touches
  on an explicit `brew zap`)

## The one thing worth remembering

Discovery was rewritten because the original design was wrong in a way that was
*invisible*: it decided what counted as a project by looking for marker files,
and silently omitted real ones. `exec-dashboard` and `ops-dashboard` were
missing with no way to notice. The fix was to make the scanner only *offer*
folders and let the user tick them. If a future change reintroduces automatic
filtering, it reintroduces that bug.

`ops-dashboard` still doesn't pre-tick — it has two marker-bearing children
(`mockup/index.html`, `pipeline/requirements.txt`), so the container heuristic
reads it as a container. That's a genuine judgment call no rule wins, which is
why the checkboxes exist. Threshold is one comparison in `ProjectScanner`.

## Next action (pick one — all optional)

1. **App icon.** The most visible gap now that it's publicly installable; it
   ships with the generic blank document icon.
2. **`-n/--name`.** Sets the session name *and* the Terminal window title.
   Would compound nicely with the per-project colour themes.
3. Session control (`--continue` / `--resume`), previously declined.
4. Tests around `ProjectScanner` — the container heuristic is the part most
   likely to be quietly wrong on someone else's folder layout.

## To resume

```bash
cd ~/Ai/Personal/apps/claudeLauncher
./build.sh          # dev build into dist/ — do NOT use --install, see below
open dist/ClaudeLauncher.app
```

Avoid `./build.sh --install` while the Homebrew copy is in `/Applications`.

Shipping a change is one command:
```bash
./publish.sh 1.0.1
```
It builds, signs, notarizes, verifies the staple, tags, uploads to Releases,
and rewrites the cask's version and sha256 in the tap. It refuses to publish an
unstapled DMG.

## Credential note

Notarization now works from a keychain profile named `claude-launcher`, holding
an Apple **app-specific** password (not the Apple ID password). It lives in the
login keychain on this Mac only — it is not in 1Password, and it is not in this
repo. If this Mac is lost or the keychain is reset, regenerate the password at
appleid.apple.com and re-run `xcrun notarytool store-credentials`.
