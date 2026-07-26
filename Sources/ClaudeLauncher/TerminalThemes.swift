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
// Colours come from the profiles already installed in Terminal (Basic, Grass,
// Homebrew, Novel, Ocean, Pro, plus anything custom). That means the palette
// matches what the user already knows, and it stays correct on a machine with a
// completely different set.
//
// One wrinkle worth knowing: opening a `.terminal` file *installs* it as a
// profile. We therefore emit a small fixed set named "Claude — <theme>" and
// rewrite those in place, rather than one throwaway profile per launch. The
// user's own profiles are read but never modified.

enum TerminalThemes {

    /// Prefix for every profile this app installs, so ours are obvious in
    /// Terminal → Settings → Profiles and never collide with the originals.
    static let installedPrefix = "Claude — "

    /// Names of the profiles installed in Terminal, alphabetically.
    ///
    /// Profiles this app previously installed are filtered out, otherwise the
    /// picker would slowly fill with "Claude — Claude — Ocean" style entries.
    static func availableProfileNames() -> [String] {
        guard let settings = terminalWindowSettings() else { return [] }
        return settings.keys
            .filter { !$0.hasPrefix(installedPrefix) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
        profile["CommandString"] = scriptPath
        // Run the script directly rather than as a shell string: inline shell
        // syntax has to survive both XML escaping and Terminal's own parsing,
        // and quoted paths get mangled in the process.
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
