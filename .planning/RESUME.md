# Resume — Claude Launcher

**Paused:** 2026-08-03 · **Reason:** v1.0.3 published; installed copy not yet upgraded
**Phase/Task:** Phase 6 — theme trim and resume-note summary both shipped
**Tree:** clean · **Last commit:** `043fafc` Show where each project left off, under its path

## State
- **v1.0.3 is released and contains both changes** (`c3c7aa4` themes, `043fafc`
  resume notes). Tag pushed, GitHub release live, tap cask updated.
- **`/Applications/ClaudeLauncher.app` is still the Jul 27 build.** The dev build
  at `dist/` has the new behaviour; the installed copy does not. This caused a
  full "the feature doesn't work" round-trip this session.
- Theme picker offers exactly five dark profiles: Clear Dark, Grass, Homebrew,
  Ocean, Red Sands. Verified in the running app.
- Resume-note summary verified against all 38 `.planning/RESUME.md` files under
  `~/Ai` — 24 next-step, 13 context, 1 blocked (`cognito`). Amber blocked banner
  confirmed on screen.
- No automated tests exist. Both features were verified by compiling the real
  types into a throwaway probe binary and by screenshotting the app.

## Next action
1. `brew upgrade --cask claude-launcher` — then relaunch from Spotlight and
   confirm the five themes and the summary line are present in the installed app.
2. Homebrew records `1.0.1` installed while the app reported `1.0.2`, so
   something overwrote `/Applications` outside brew. If the upgrade balks,
   `brew reinstall --cask claude-launcher`.
3. `-n/--name` flag — sets session name and Terminal window title.

## Gotchas
- The cask is **`claude-launcher`**, not `claudelauncher`.
- Never `./build.sh --install` while the Homebrew copy is in `/Applications`;
  that is what desynced the versions above. Dev builds run from `dist/`.
- Don't drive the app with System Events keystrokes — a stray Return hit Launch
  and started a real session this session. `set selected of row N of outline 1`
  works; `click at {x, y}` silently does not change SwiftUI selection.
- Only 1 of 38 notes uses an explicit `Blocked:` label. Several are blocked in
  substance ("Nothing until Apple responds") and show as **Next**. Writing
  `Blocked:` in the note is the reliable fix; inferring intent is not.
