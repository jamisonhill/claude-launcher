import Foundation

// MARK: - On-disk state
//
// Two JSON files live in ~/Library/Application Support/ClaudeLauncher/ :
//
//   config.json  – which folders to scan (edit this by hand to add roots)
//   prefs.json   – remembered per-project choices and recency
//
// Both are plain Codable structs so they're easy to read and hand-edit.

/// Where the app keeps its files. Created on first launch if missing.
enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ClaudeLauncher", isDirectory: true)
        // Creating a directory that already exists is a no-op with
        // withIntermediateDirectories: true, so this is safe to call every time.
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir
    }

    static var configFile: URL { supportDirectory.appendingPathComponent("config.json") }
    static var prefsFile: URL { supportDirectory.appendingPathComponent("prefs.json") }

    /// Temporary shell scripts we hand to Terminal.app live here.
    static var sessionsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir
    }
}

/// Which directories get scanned for projects, and what to ignore.
struct Config: Codable {
    /// Top-level folders to scan. `~` is expanded at scan time.
    var roots: [String] = [
        "~/Ai/MHIT",
        "~/Ai/Personal",
        "~/Ai/Playground"
    ]

    /// Folder names that are never treated as projects (build output, caches…).
    var excludes: [String] = [
        "node_modules", "_archive", "Archive", "archive", ".git", ".build",
        "build", "dist", "out", "venv", ".venv", "__pycache__", "DerivedData",
        "Pods", ".next", ".cache", "vendor", "target"
    ]

    /// Loads config.json, falling back to the defaults (and writing them out)
    /// if the file is missing or corrupt.
    static func load() -> Config {
        guard let data = try? Data(contentsOf: AppPaths.configFile),
              let decoded = try? JSONDecoder().decode(Config.self, from: data) else {
            let fresh = Config()
            fresh.save()
            return fresh
        }
        return decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // A failed write just means preferences don't persist — not worth
        // interrupting the user over, so we swallow the error.
        try? encoder.encode(self).write(to: AppPaths.configFile)
    }
}

/// Per-project choices the launcher remembers between runs.
struct Prefs: Codable {
    /// project path -> last model used there
    var lastModel: [String: ClaudeModel] = [:]
    /// project path -> whether --dangerously-skip-permissions was on
    var skipPermissions: [String: Bool] = [:]
    /// project path -> when it was last launched (drives the Recent section)
    var lastUsed: [String: Date] = [:]

    /// You chose "on by default", so an unseen project starts with the flag set.
    static let defaultSkipPermissions = true

    static func load() -> Prefs {
        let decoder = JSONDecoder()
        // Must match the encoder below, or every stored date fails to parse
        // and the Recent list silently comes back empty.
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: AppPaths.prefsFile),
              let decoded = try? decoder.decode(Prefs.self, from: data) else {
            return Prefs()
        }
        return decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(self).write(to: AppPaths.prefsFile)
    }
}
