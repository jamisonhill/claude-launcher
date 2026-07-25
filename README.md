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

A folder is listed only when it looks like something you'd actually launch
Claude in — that is, when it carries a **project marker**: `.git`, `CLAUDE.md`,
`.claude`, `package.json`, `Package.swift`, `pyproject.toml`, `Cargo.toml`,
`go.mod`, `Gemfile`, `Makefile`, `docker-compose.yml`, `index.html`, or an
`.xcodeproj` / `.xcworkspace`.

`README.md` is deliberately *not* a marker. Nearly every documentation folder
has one, so it admits exactly the noise this list exists to filter out.

The traversal:

1. Each configured root is always launchable, marker or not — you chose it
   explicitly, so the app doesn't second-guess it.
2. One level under a root, a folder is listed if it has a marker.
3. A folder *without* a marker is treated as a container, and the scan looks one
   level inside it. That's what surfaces `~/Code/apps/my-app` while ignoring the
   `apps` folder itself.

Turning on **Show folders without projects** (in Settings or the ⋯ toolbar menu)
relaxes rules 2 and 3 to list everything — the escape hatch for launching
somewhere that has no marker file yet.

Hidden folders and common build output (`node_modules`, `.build`, `dist`,
`venv`, …) are always skipped.

### Group names

Section headings are derived from a project's position *relative to its own
root*, never from a hardcoded path:

| Root | Project | Heading |
| ---- | ------- | ------- |
| `~/Ai/Personal` | `~/Ai/Personal/aquarium` | `PERSONAL` |
| `~/Ai/Personal` | `~/Ai/Personal/apps/prayer` | `PERSONAL / APPS` |
| `~/Code` | `~/Code/my-app` | `CODE` |

A nested group holding a single project is folded back into its top-level group,
so `MHIT / FARGO` with one item becomes part of `MHIT`. A section header costs
about as much vertical space as a row does, so a header introducing one project
is pure overhead — and a deep directory tree generates a lot of them.

## Sidebar

**Favorites.** Hover any project and click the star, or use the context menu,
the star beside the project name, or ⌘D. Favorites pin to a section at the top
and can be dragged into whatever order you like.

**Collapsible sections.** Favorites and Recent open by default; folder groups
start collapsed. Only explicit open/closed choices are stored, so a group
discovered by a later rescan gets the sensible default rather than inheriting a
stale entry.

**Searching** replaces the sections with a single flat list of matches. Sections
only get in the way once you know what you're after, and a match hiding inside a
collapsed group reads as "no such project."

Rows show the folder name alone — the section header already says where it
lives. The path appears only in search results, where it's constant and actually
disambiguates. The star's space is always reserved and only its opacity changes,
because showing and hiding the view itself reflowed the row's text every time
the pointer crossed it.

Refresh, collapse-all, and list options live in the window toolbar rather than a
sidebar footer.

## Configuration

Open **Settings** (⌘,) to add or remove project folders with a folder picker,
toggle the show-all-folders escape hatch, and trigger a rescan.

Two JSON files back it, in `~/Library/Application Support/ClaudeLauncher/`:

- **`config.json`** — scan roots, exclusions, and the show-all flag. Editable by
  hand if you prefer; press ⌘R afterward.
- **`prefs.json`** — remembered model, permission flag, last-used time,
  favorites, and which sidebar sections are open. Managed by the app; safe to
  delete to reset.

Both decode field-by-field, so a config written by a newer version won't fail to
load and silently reset your settings on an older one.

There are **no default roots**. The app has no way to know where a given person
keeps their code, so a fresh install asks rather than guessing at paths that
exist on only one machine.

## Keyboard

| Key | Action |
| --- | ------ |
| `Return` | Launch the selected project |
| `⌘D` | Favorite / unfavorite the selected project |
| `⌘O` | Add a project folder |
| `⌘R` | Re-scan for projects |
| `⌘,` | Settings |

## Files

```
Package.swift                      SwiftPM manifest
build.sh                           compiles and assembles the .app bundle
Sources/ClaudeLauncher/
  ClaudeLauncherApp.swift          entry point, window, menus, settings scene
  ContentView.swift                sidebar + launch panel UI
  SettingsView.swift               ⌘, pane for managing scan roots
  LauncherStore.swift              observable app state
  Launcher.swift                   command building, script writing, Terminal
  ProjectScanner.swift             directory scanning rules
  Prefs.swift                      config.json / prefs.json models
  Models.swift                     ClaudeModel enum, Project struct
```
