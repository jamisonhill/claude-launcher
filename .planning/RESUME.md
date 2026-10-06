# Resume — OWL — AI Launcher

**Paused:** 2026-10-05 · **Reason:** 1.0.6 is built but Apple can't notarize it yet
**Phase/Task:** Phase 7 — model selector done; 1.0.6 blocked on Apple
**Tree:** clean · **Last commit:** `a5cc03c` Describe each model by what it's good for

## State
- **The model selector now follows the newest model per family.** `--model` is
  passed the alias (`opus`, `fable`, `sonnet`, `haiku`), which the CLI resolves
  to the latest release; the old pinned ids had gone a generation stale. No app
  release is needed when Anthropic ships the next model.
- Model subtitles rewritten so they stop pointing at the wrong choice.
- **1.0.5 is live everywhere** — release, DMG, tap, and website. The last pause
  note said no release existed; it was published minutes after that note.
- **1.0.6 is built, signed and verified** at
  `/Users/jamisonhill/Ai/Personal/apps/claudeLauncher/dist/OWL-AI-Launcher-1.0.6.dmg`
  — not notarized, so not publishable.
- **Blocked:** notarization returns `403 A required agreement is missing or has
  expired` while Apple clears the personal→company account conversion. The
  keychain credential is fine — a bad one returns 401. This is a wait, not a fix.

## Next action
1. **Wait for Apple.** Re-check with
   `xcrun notarytool history --keychain-profile claude-launcher` — anything other
   than a 403 means it's cleared. Accept any pending agreement at
   https://developer.apple.com/account (team `HFAWAP3F3Z`) if one is shown.
2. `cd /Users/jamisonhill/Ai/Personal/apps/claudeLauncher && ./publish.sh 1.0.6`
3. Bump `/Users/jamisonhill/Ai/Personal/llc/website/src/content/apps/owl.md`
   lines 12–13 from `1.0.5` to `1.0.6` (both `version:` and `assetName:`), then
   `cd /Users/jamisonhill/Ai/Personal/llc/website && ./deploy.sh`. Needs the NAS
   sudo password.

## Gotchas
- **Publish before deploy**, or the download button 404s.
- **Don't run `./publish.sh 1.0.5`.** It force-moves the tag and clobbers a DMG
  that people have already downloaded. 1.0.6 is the next version.
- Never rename `~/Library/Application Support/ClaudeLauncher` — it holds the
  44-project library, and nothing in the app looks for another name.
- Don't drive the app with `click at {x, y}`; it silently misses SwiftUI
  controls. `click radio button N of radio group M …` works.
