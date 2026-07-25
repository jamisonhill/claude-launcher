import Foundation

// MARK: - On-disk state
//
// Two JSON files live in ~/Library/Application Support/ClaudeLauncher/ :
//
//   config.json  – which folders to scan (managed from the Settings window)
//   prefs.json   – remembered per-project choices and sidebar state
//
// Both decode field-by-field with `decodeIfPresent` so that adding a setting in
// a later version doesn't make older files fail to load and silently reset
// somebody's configuration.

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
    ///
    /// Deliberately empty by default: this app has no way to know where a given
    /// person keeps their code, so a fresh install asks rather than guessing at
    /// paths that only exist on one machine.
    var roots: [String] = []

    /// Folder names that are never treated as projects (build output, caches…).
    var excludes: [String] = [
        "node_modules", "_archive", "Archive", "archive", ".git", ".build",
        "build", "dist", "out", "venv", ".venv", "__pycache__", "DerivedData",
        "Pods", ".next", ".cache", "vendor", "target"
    ]

    /// When false (the default), only folders carrying a project marker are
    /// listed. When true, every folder inside a root shows up — the escape
    /// hatch for launching somewhere that has no marker file yet.
    var showAllFolders: Bool = false

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case roots, excludes, showAllFolders
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Config()
        roots = try container.decodeIfPresent([String].self, forKey: .roots) ?? defaults.roots
        excludes = try container.decodeIfPresent([String].self, forKey: .excludes) ?? defaults.excludes
        showAllFolders = try container.decodeIfPresent(Bool.self, forKey: .showAllFolders) ?? defaults.showAllFolders
    }

    // MARK: Persistence

    /// Loads config.json, falling back to defaults if it's missing or corrupt.
    static func load() -> Config {
        guard let data = try? Data(contentsOf: AppPaths.configFile),
              let decoded = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        return decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // A failed write just means settings don't persist — not worth
        // interrupting the user over, so we swallow the error.
        try? encoder.encode(self).write(to: AppPaths.configFile)
    }
}

/// Per-project choices and sidebar state the launcher remembers between runs.
struct Prefs: Codable {

    /// project path -> last model used there
    var lastModel: [String: ClaudeModel] = [:]
    /// project path -> whether --dangerously-skip-permissions was on
    var skipPermissions: [String: Bool] = [:]
    /// project path -> when it was last launched (drives the Recent section)
    var lastUsed: [String: Date] = [:]
    /// Paths pinned to the Favorites section, in the order they were added.
    var favorites: [String] = []

    /// Sidebar sections the user has explicitly opened or closed.
    ///
    /// Only *explicit* choices are stored. A section that isn't in here falls
    /// back to `defaultExpanded`, which is what lets folder groups start
    /// collapsed while Favorites and Recent start open — and means a group
    /// discovered by a future rescan gets the sensible default rather than
    /// inheriting some stale entry.
    var sectionExpanded: [String: Bool] = [:]

    /// You chose "on by default", so an unseen project starts with the flag set.
    static let defaultSkipPermissions = true

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case lastModel, skipPermissions, lastUsed, favorites, sectionExpanded
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastModel = try container.decodeIfPresent([String: ClaudeModel].self, forKey: .lastModel) ?? [:]
        skipPermissions = try container.decodeIfPresent([String: Bool].self, forKey: .skipPermissions) ?? [:]
        lastUsed = try container.decodeIfPresent([String: Date].self, forKey: .lastUsed) ?? [:]
        favorites = try container.decodeIfPresent([String].self, forKey: .favorites) ?? []
        sectionExpanded = try container.decodeIfPresent([String: Bool].self, forKey: .sectionExpanded) ?? [:]
    }

    // MARK: Persistence

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
