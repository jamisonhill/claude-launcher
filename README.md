# Claude Launcher

A small native macOS app for starting Claude Code sessions. Pick a project,
pick a model, hit Launch — a new Terminal window opens in that folder with
Claude already running.

Local-only. Not signed for distribution, not intended to leave this machine.

## Build

```bash
./build.sh              # builds dist/ClaudeLauncher.app
./build.sh --install    # also copies it to /Applications
```

Requires macOS 14+ and the Swift toolchain that ships with Xcode. No other
dependencies.

## How it works

Launch writes a short `.command` shell script and asks Terminal.app to open it.
macOS runs `.command` files in a fresh Terminal window, which gets us the new
window, the working directory, and the running process in one step.

The script looks like this:

```zsh
#!/bin/zsh -l
cd '/Users/jamisonhill/Ai/Personal/apps/prayer' || exit 1
clear
exec '/Users/jamisonhill/.local/bin/claude' --model claude-opus-5 --dangerously-skip-permissions
```

Two deliberate choices in there:

- **No AppleScript.** Driving Terminal with Apple Events needs an Automation
  permission grant tied to the app's code signature. Because this app is
  ad-hoc signed, every rebuild would change that identity and re-trigger the
  permission prompt. Opening a file has no such requirement.
- **`exec`** replaces the login shell with Claude, so quitting Claude closes
  the window instead of leaving you in a stray subshell.

## Models

| Button | `--model` value |
| ------ | --------------- |
| Opus   | `claude-opus-5` |
| Fable  | `claude-fable-5` |
| Sonnet | `claude-sonnet-5` |
| Haiku  | `claude-haiku-4-5-20251001` |

To track a new model release, edit `modelID` in `Sources/ClaudeLauncher/Models.swift`.

## Skip permission prompts

The toggle adds `--dangerously-skip-permissions`, which lets Claude run commands
and edit files without asking. **It defaults to on**, and the choice is
remembered per project. The exact command is always shown under "Will run" so
you can see the flag before launching.

## Project discovery

Scanned automatically on every launch, using these rules:

1. Each configured root is itself launchable.
2. Every directory one level under a root is launchable.
3. A directory two levels down is included only if its parent has no project
   markers of its own — that is, the parent looks like a container. This is what
   pulls `~/Ai/Personal/apps/prayer` into the list without also listing every
   subfolder inside a real repo.

Project markers are `.git`, `CLAUDE.md`, `package.json`, `.claude`,
`Package.swift`, `pyproject.toml`, and similar.

Hidden folders and common build output (`node_modules`, `.build`, `dist`,
`venv`, …) are always skipped.

## Sidebar

**Favorites.** Hover any project and click the star, or use the context menu,
the star beside the project name, or ⌘D. Favorites pin to a section at the top
of the sidebar and can be dragged into whatever order you like. Removing a
favorite never touches the project itself.

**Collapsible sections.** Every section — Favorites, Recent, and each folder
group — has a disclosure triangle and remembers whether you left it open. With
a hundred projects in the list, collapsing the groups you're not using is the
difference between a sidebar you scroll and one you scan. The chevron button in
the footer collapses or expands everything at once (also under the Projects
menu).

Searching temporarily replaces all of this with a single flat list of matches,
since sections only get in the way when you already know what you're after.

## Configuration

Two JSON files in `~/Library/Application Support/ClaudeLauncher/`:

- **`config.json`** — which roots to scan and what to exclude. Edit by hand,
  then press ⌘R in the app. Reachable from *File → Show Config File in Finder*.
- **`prefs.json`** — remembered model, permission flag, last-used time,
  favorites, and which sections are collapsed. Managed by the app; safe to
  delete to reset.

Default roots are `~/Ai/MHIT`, `~/Ai/Personal`, and `~/Ai/Playground`.

## Keyboard

| Key | Action |
| --- | ------ |
| `Return` | Launch the selected project |
| `⌘D` | Favorite / unfavorite the selected project |
| `⌘R` | Re-scan for projects |

## Files

```
Package.swift                      SwiftPM manifest
build.sh                           compiles and assembles the .app bundle
Sources/ClaudeLauncher/
  ClaudeLauncherApp.swift          entry point, window, menu commands
  ContentView.swift                sidebar + launch panel UI
  LauncherStore.swift              observable app state
  Launcher.swift                   command building, script writing, Terminal
  ProjectScanner.swift             directory scanning rules
  Prefs.swift                      config.json / prefs.json models
  Models.swift                     ClaudeModel enum, Project struct
```
