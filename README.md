# Claude Launcher

A native macOS app for starting Claude Code sessions. Pick a project, set the
options, hit Launch — a Terminal window opens in that folder, in the colour
scheme you chose, with Claude already running.

## Build

```bash
./build.sh              # local dev build, ad-hoc signed
./build.sh --install    # also copies it to /Applications
```

Requires macOS 14+ and the Swift toolchain that ships with Xcode. No other
dependencies.

## Distribution

```bash
./release.sh             # signed + hardened, produces dist/Claude Launcher.dmg
./release.sh --notarize   # also submits to Apple and staples the ticket
```

Notarization needs credentials stored once in the keychain:

```bash
xcrun notarytool store-credentials claude-launcher \
  --apple-id "you@example.com" \
  --team-id HFAWAP3F3Z \
  --password "app-specific-password"
```

That's an *app-specific* password from appleid.apple.com → Sign-In and Security,
not your Apple ID password.

### Not the Mac App Store

This app can't ship on the Mac App Store, and no amount of work changes that.
Store apps must run under App Sandbox, which forbids everything this app is:

- spawning `/bin/zsh` to resolve the CLI
- writing an executable script and having Terminal run it
- `NSWorkspace.open` against Terminal.app — App Review treats launching
  arbitrary commands as executing arbitrary code
- reading `com.apple.Terminal`'s preference domain for colour profiles
- writing `.terminal` profiles into Terminal's configuration
- walking arbitrary directories rather than only user-selected ones

No entitlement grants "run a shell command in Terminal", and Guideline 2.5.2
requires apps be self-contained. A sandboxed build wouldn't be a reduced version
of this app; it would be a non-functional one. Developer ID + notarization is
the correct channel and gives recipients the same frictionless install.

## Setup

On first run the app asks for the folder your projects live in, then lists
**everything** inside it with checkboxes. You tick which folders are real
projects.

That inversion is deliberate. An earlier version decided for you by looking for
marker files, and it silently hid `MHIT/DATA-ANALYTICS/exec-dashboard` — a real
project full of docs and schemas, but with no `.git` or `package.json`. There
was no way to discover it was missing. Markers now only decide which boxes start
**ticked**; they never decide what's **visible**.

Re-run the picker any time with **File → Choose Projects…** (⇧⌘O). Your existing
selection comes back pre-ticked.

### How boxes get pre-ticked

- A folder carrying a marker (`.git`, `CLAUDE.md`, `package.json`,
  `Package.swift`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`,
  `Makefile`, `docker-compose.yml`, `index.html`, `.xcodeproj`) is ticked, and
  the scan stops there — a project's subfolders are parts of it, not siblings.
- A folder *without* a marker is judged by how many of its children have one:

  | Marker-bearing children | Read as | Example |
  | --- | --- | --- |
  | 2 or more | a container of projects | `~/Ai/Personal/apps` (11) |
  | exactly 1 | the project itself | `exec-dashboard` |
  | 0 | neither; left unticked | `MHIT/governance` |

This is a guess and it will sometimes be wrong — `ops-dashboard` has two
marker-bearing children and so reads as a container. That's what the checkboxes
are for. Nothing is ever hidden, so a wrong guess costs one click.

## Sidebar

Sections are **yours**: create them, name them, drag projects between them.
Anything unfiled lands in **Unsorted**, so a newly added project can never go
missing. Deleting a section returns its projects to Unsorted rather than
removing them from the library.

Earlier versions derived sections from the folder tree. Those headings made
sense on one machine and nonsense on another, and they couldn't express a
grouping that cuts across directories.

- **Favorites** — star a row on hover, or use ⌘D, the context menu, or the star
  by the project name. Drag to reorder.
- **Recent** — the last five launched.
- **Search** replaces the sections with a flat list of matches, since a match
  hidden inside a collapsed section reads as "no such project".

Favorites and Recent open by default; your own sections start collapsed.

## Launch options

| Control | Flag |
| --- | --- |
| Model | `--model claude-opus-5` / `-fable-5` / `-sonnet-5` / `claude-haiku-4-5-20251001` |
| Permissions | `--permission-mode bypassPermissions \| acceptEdits \| plan \| dontAsk \| auto \| manual` |
| Effort | `--effort low \| medium \| high \| xhigh \| max` (omitted entirely when set to Default) |

Permissions defaults to **Bypass All**, which is exactly what the old
"skip permissions" toggle did — `--dangerously-skip-permissions` and
`--permission-mode bypassPermissions` are the same thing. Exposing the real
modes makes `plan` and `acceptEdits` reachable at launch.

Every choice is remembered per project, and the exact command is shown under
**Will run** before you launch.

## Terminal themes

Pick a colour scheme per project so concurrent sessions are tellable apart at a
glance. The window is also titled after the project.

Themes are read from the profiles already installed in Terminal (Basic, Grass,
Homebrew, Novel, Ocean, Pro, plus anything custom), so the palette matches what
you already know and stays correct on a machine with a different set.

**How it works.** Terminal reads `.terminal` files — plists describing a window
profile. A profile can carry a `CommandString`, so opening one gets us a new
window with the right colours *and* our launch script, with no Apple Events
involved. Same reason the plain path avoids AppleScript: Automation permission
is tied to the code signature, and an ad-hoc signed app re-prompts on every
rebuild.

**Caveat worth knowing.** Opening a `.terminal` file *installs* it as a Terminal
profile. The app emits a small fixed set named `Claude — <theme>` and rewrites
those in place, rather than one throwaway profile per launch. Your own profiles
are read but never modified. Remove them in Terminal → Settings → Profiles.

`CommandString` points at the generated script rather than inlining shell
syntax; inline commands have to survive both XML escaping and Terminal's own
parsing, and quoted paths get mangled in the process.

## How launching works

```zsh
#!/bin/zsh -l
cd '/Users/you/Ai/MHIT/DATA-ANALYTICS/exec-dashboard' || exit 1
clear
exec '/Users/you/.local/bin/claude' '--model' 'claude-opus-5' '--permission-mode' 'bypassPermissions'
```

`-l` gives the session your normal login environment. `exec` replaces the shell
with Claude, so quitting Claude closes the window instead of leaving a stray
subshell. The `claude` binary is resolved up front, so a missing CLI produces a
clear dialog instead of a window that flashes "command not found" and vanishes.

## Configuration

**Settings** (⌘,) manages your main folders and re-runs the project picker.

Three JSON files in `~/Library/Application Support/ClaudeLauncher/`:

- **`config.json`** — main folders to search, and exclusions.
- **`library.json`** — your curated projects and your sections.
- **`prefs.json`** — per-project model, permission mode, effort, theme,
  favorites, recency, and which sections are open.

All three decode field-by-field, so a file written by a newer version can't fail
to load and silently reset your setup. There are no default folders: the app has
no way to know where a given person keeps their code.

## Keyboard

| Key | Action |
| --- | ------ |
| `Return` | Launch the selected project |
| `⌘D` | Favorite / unfavorite |
| `⌘O` | Add a main folder |
| `⇧⌘O` | Choose projects |
| `⌘,` | Settings |

## Files

```
Package.swift                      SwiftPM manifest
build.sh                           compiles and assembles the .app bundle
Sources/ClaudeLauncher/
  ClaudeLauncherApp.swift          entry point, window, menus, settings scene
  ContentView.swift                sidebar + launch panel
  SetupSheet.swift                 the project-picker sheet
  SettingsView.swift               ⌘, pane
  LauncherStore.swift              observable app state
  Launcher.swift                   command building, script writing, Terminal
  TerminalThemes.swift             reads Terminal profiles, writes .terminal
  ProjectScanner.swift             candidate discovery
  Prefs.swift                      config / library / prefs models
  Models.swift                     models, flags, Project, sections
```
