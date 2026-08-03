import AppKit
import Foundation

// MARK: - Terminal colour themes
//
// Goal: each project's window opens in its own colour scheme, so several
// concurrent sessions are tellable apart at a glance.
//
// How: Terminal reads `.terminal` files, which are plists describing a window
// profile. A profile may carry a `CommandString`, so opening one gets us a new
// window with chosen colours *and* our launch script, with no Apple Events
// involved — the same reason the plain `.command` path avoids AppleScript.
//
// Colours come from the profiles already installed in Terminal. That means the
// palette matches what the user already knows, and it stays correct on a
// machine with a completely different set.
//
// Only dark profiles are offered, and only the five most visually distinct of
// them — see `availableProfileNames`.
//
// One wrinkle worth knowing: opening a `.terminal` file *installs* it as a
// profile. We therefore emit a small fixed set named "Claude — <theme>" and
// rewrite those in place, rather than one throwaway profile per launch. The
// user's own profiles are read but never modified.

enum TerminalThemes {

    /// Prefix for every profile this app installs, so ours are obvious in
    /// Terminal → Settings → Profiles and never collide with the originals.
    static let installedPrefix = "Claude — "

    /// Whether a profile is one this app installed, and so must never be
    /// offered as a theme to base a new one on.
    ///
    /// Matching on `installedPrefix` alone is not enough. Earlier versions
    /// separated with a hyphen rather than an em dash, so profiles named
    /// "Claude - Ocean" survive on machines that ran them — and being unmatched
    /// is what let them be re-picked and re-wrapped into "Claude - Claude -
    /// Ocean". Any dash the name has ever used has to count.
    static func isInstalledByApp(_ name: String) -> Bool {
        let separators = ["—", "–", "-"]
        return separators.contains { name.hasPrefix("Claude \($0) ") }
    }

    /// How many themes the picker offers. A row of swatches is a glance-level
    /// control; past a handful, picking one stops being a glance.
    static let maximumThemeCount = 5

    /// Backgrounds at or above this relative luminance are treated as light.
    ///
    /// Sits above Ocean (0.38) and Grass (0.37), which are vivid but still
    /// light-on-dark profiles, and below Silver Aerogel (0.57), which is not.
    private static let lightBackgroundThreshold = 0.45

    /// The dark profiles offered in the picker: at most `maximumThemeCount`,
    /// alphabetically.
    ///
    /// Three filters, each earning its place:
    ///
    /// - Profiles this app installed are dropped, otherwise the picker would
    ///   slowly fill with "Claude — Claude — Ocean" style entries.
    /// - Light profiles are dropped outright.
    /// - The rest are thinned to the most visually distinct few. Terminal ships
    ///   several profiles with pure black backgrounds (Homebrew and Pro among
    ///   them); showing more than one spends a slot on a swatch the user cannot
    ///   tell from its neighbour, which is the one thing the picker exists to
    ///   let them do.
    static func availableProfileNames() -> [String] {
        guard let settings = terminalWindowSettings() else { return [] }

        let dark = settings.keys
            .filter { !isInstalledByApp($0) }
            .filter { isDark(profileNamed: $0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        return mostDistinct(among: dark, limit: maximumThemeCount)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Whether a profile's background is dark enough to read as a dark theme.
    ///
    /// A profile with no `BackgroundColor` inherits Terminal's default white,
    /// so an unreadable colour means light, not "unknown" — Basic is the case
    /// that matters here.
    private static func isDark(profileNamed name: String) -> Bool {
        guard let color = backgroundColor(forProfile: name),
              let srgb = color.usingColorSpace(.sRGB) else { return false }
        return relativeLuminance(of: srgb) < lightBackgroundThreshold
    }

    /// Perceived brightness, weighting green highest and blue lowest the way
    /// the eye does. Plain averaging would call Ocean's blue as bright as
    /// Grass's green.
    private static func relativeLuminance(of color: NSColor) -> Double {
        0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
    }

    /// Picks `limit` names whose background colours are as far apart as
    /// possible.
    ///
    /// Farthest-point selection: seed with the darkest, then repeatedly add
    /// whichever candidate is furthest from everything already chosen. Ties
    /// break on the incoming alphabetical order, so the result is stable across
    /// launches — a picker that reshuffled itself would be worse than one that
    /// showed too much.
    private static func mostDistinct(among names: [String], limit: Int) -> [String] {
        guard names.count > limit else { return names }

        // Profiles whose colour can't be read were already excluded by the
        // dark filter, so every name here resolves.
        let colors = names.reduce(into: [String: NSColor]()) { result, name in
            if let color = backgroundColor(forProfile: name)?.usingColorSpace(.sRGB) {
                result[name] = color
            }
        }

        var remaining = names.filter { colors[$0] != nil }
        guard let seed = remaining.min(by: {
            relativeLuminance(of: colors[$0]!) < relativeLuminance(of: colors[$1]!)
        }) else { return [] }

        var chosen = [seed]
        remaining.removeAll { $0 == seed }

        while chosen.count < limit, !remaining.isEmpty {
            let next = remaining.max { a, b in
                distanceToNearest(a, in: chosen, colors: colors)
                    < distanceToNearest(b, in: chosen, colors: colors)
            }!
            chosen.append(next)
            remaining.removeAll { $0 == next }
        }
        return chosen
    }

    /// Distance from one profile's background to the closest already-chosen
    /// one. Straight-line RGB distance is crude as a model of perception, but
    /// it separates black from navy from maroon, which is all this needs.
    private static func distanceToNearest(_ name: String,
                                          in chosen: [String],
                                          colors: [String: NSColor]) -> Double {
        guard let color = colors[name] else { return 0 }
        return chosen.compactMap { colors[$0] }.map { other in
            let dr = color.redComponent - other.redComponent
            let dg = color.greenComponent - other.greenComponent
            let db = color.blueComponent - other.blueComponent
            return (dr * dr + dg * dg + db * db).squareRoot()
        }.min() ?? 0
    }

    /// Terminal's default profile name, used when the user hasn't picked one.
    static func defaultProfileName() -> String? {
        UserDefaults(suiteName: "com.apple.Terminal")?
            .string(forKey: "Default Window Settings")
    }

    /// Background colour of a profile, for drawing swatches in the picker.
    static func backgroundColor(forProfile name: String) -> NSColor? {
        guard let profile = profileDictionary(named: name) else { return nil }
        return unarchivedColor(profile["BackgroundColor"])
    }

    /// Text colour of a profile, for drawing swatches in the picker.
    static func textColor(forProfile name: String) -> NSColor? {
        guard let profile = profileDictionary(named: name) else { return nil }
        return unarchivedColor(profile["TextColor"])
    }

    /// Builds a `.terminal` file that opens in `profileName`'s colours, titles
    /// the window `windowTitle`, and runs `scriptPath`.
    ///
    /// Returns nil when the profile can't be read, so the caller can fall back
    /// to the plain `.command` launch rather than failing outright.
    static func makeProfile(basedOn profileName: String,
                            runningScriptAt scriptPath: String,
                            windowTitle: String) -> URL? {
        guard var profile = profileDictionary(named: profileName) else { return nil }

        let installedName = installedPrefix + profileName
        profile["name"] = installedName
        profile["type"] = "Window Settings"
        // The path has to be shell-quoted even though `RunCommandAsShell` is
        // false: Terminal still hands the string to the login shell, which
        // word-splits it. Our scripts live under "Application Support", so an
        // unquoted path fails with "no such file or directory: …/Application".
        profile["CommandString"] = Launcher.shellQuote(scriptPath)
        // Keep the command out of an extra `-c` wrapper; the script already
        // starts its own login shell and `exec`s Claude.
        profile["RunCommandAsShell"] = false
        profile["ShouldRestoreContent"] = false
        profile["WindowTitle"] = windowTitle
        // Without this the window vanishes the instant Claude exits, taking any
        // final output with it.
        profile["shellExitAction"] = 1

        let fileURL = AppPaths.sessionsDirectory
            .appendingPathComponent("\(sanitize(installedName)).terminal")

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: profile,
                                                          format: .xml,
                                                          options: 0)
            try data.write(to: fileURL)
            return fileURL
        } catch {
            // Falling back to an unthemed window is better than not launching.
            return nil
        }
    }

    // MARK: - Reading Terminal's preferences

    /// The "Window Settings" dictionary from Terminal's preference domain.
    private static func terminalWindowSettings() -> [String: Any]? {
        UserDefaults(suiteName: "com.apple.Terminal")?
            .dictionary(forKey: "Window Settings")
    }

    private static func profileDictionary(named name: String) -> [String: Any]? {
        terminalWindowSettings()?[name] as? [String: Any]
    }

    /// Terminal stores colours as archived NSColor blobs rather than plain
    /// numbers, so they have to be unarchived to be drawn.
    private static func unarchivedColor(_ value: Any?) -> NSColor? {
        guard let data = value as? Data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
    }

    /// Strips characters that would be awkward in a filename.
    private static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "[^A-Za-z0-9._ -]",
                                  with: "-",
                                  options: .regularExpression)
    }
}
