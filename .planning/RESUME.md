# Resume — OWL — AI Launcher

**Paused:** 2026-08-15 · **Reason:** rebrand + multi-tool done; 1.0.5 not cut yet
**Phase/Task:** Phase 7 — code complete, release and deploy pending
**Tree:** clean · **Last commit:** `77ca534` Rebrand to OWL — AI Launcher

## State
- Multi-tool support ships: Claude Code and Gemini CLI built in, custom tools
  for anything else. Verified in the running app — the panel swaps to Gemini's
  Approval Mode and drops Model/Effort/First Command.
- Rebranded to **OWL — AI Launcher** everywhere public. The support folder,
  bundle id, SwiftPM target and GitHub repo keep the old name on purpose.
- **Both commits are already on `origin/main`.** Not by a hook — nothing in
  this repo pushes automatically, so assume it was pushed by hand.
- **The website is committed but not deployed, and points at
  `OWL-AI-Launcher-1.0.5.dmg`, which returns 404.** No release exists yet.
- `/Applications` still holds the old `ClaudeLauncher.app` 1.0.4. The new
  bundle is only at `dist/OWL — AI Launcher.app`.
- Unpushed elsewhere: `llc` 13 commits, `bug-reporting` 1 commit.

## Next action
1. `./publish.sh 1.0.5` — builds, notarizes, tags, releases, rewrites the tap
   cask as `owl-ai-launcher` and deletes the old `claude-launcher.rb`.
2. `cd ~/Ai/Personal/llc/website && ./deploy.sh` — **only after step 1**, or the
   download button 404s. Needs the NAS sudo password.
3. Load https://obedworks.com/apps/owl/ and check the download works and the
   counter still reads (it queries the repo's releases, not the app name).
4. `git -C ~/Ai/Personal/apps/bug-reporting push` — sends the 500-not-502 fix
   to GHCR; Watchtower picks it up within ~5 min.

## Gotchas
- **Publish before deploy.** The order is the whole trap in this pause.
- Never rename `~/Library/Application Support/ClaudeLauncher` — it holds the
  44-project library, and nothing in the app looks for another name.
- The cask token changed to `owl-ai-launcher`; the old one stops working.
- After deploy, `imazing` and `power-automate` in the bug tracker will start
  failing loudly instead of showing empty — neither repo exists on GitHub.
- Don't drive the app with `click at {x, y}`; it silently misses SwiftUI
  controls. `click radio button N of radio group M …` works.
