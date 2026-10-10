# Resume — OWL — AI Launcher

**Paused:** 2026-10-10 · **Reason:** 1.0.6 shipped and verified; stopping at a clean line
**Phase/Task:** Phase 7 — distribution done; next is the `-n/--name` flag
**Tree:** clean · **Last commit:** `44fa669` pause: model selector tracks newest models

## State
- **1.0.6 is live everywhere** — release, DMG, tap and website, all verified
  against the live site. The download is byte-identical to the notarized DMG
  (1,020,950 bytes) and the cask sha256 matches.
- **Apple's notarization block cleared itself.** The 403 "required agreement"
  error was on Apple's side during the personal→company conversion. Nothing in
  this repo or the keychain needed changing.
- Nothing is blocked and nothing is half-done. The remaining Phase 7 items are
  new features, not cleanup.

## Next action
1. **`-n/--name` flag** — give a session a name that is also the Terminal window
   title. Add the option group in `AITools.swift` next to the existing Claude
   flags, which is the only place a flag may be declared.
2. Session control: `--continue` / `--resume` / `--fork-session`.
3. Still no automated tests. The scanner and tool-flag building are the obvious
   first candidates if that's worth doing before more features.

## Gotchas
- **Publish before deploy**, or the website's download button 404s.
- **Don't re-run `./publish.sh` for a version already out.** It force-moves the
  tag and clobbers a DMG people have downloaded. 1.0.7 is the next version.
- `deploy.sh` for the website needs **no password** — the site moved off the home
  NAS to `owl-host-1` (root-only key auth) on 2026-09-24. Older notes claiming a
  NAS sudo password are stale.
- Never rename `~/Library/Application Support/ClaudeLauncher`; it holds the
  44-project library and nothing looks for another name.
- Don't drive the app with `click at {x, y}` — it silently misses SwiftUI
  controls. `click radio button N of radio group M …` works.
