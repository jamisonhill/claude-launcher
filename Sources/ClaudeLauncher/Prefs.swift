import Foundation

// MARK: - On-disk state
//
// Three JSON files in ~/Library/Application Support/ClaudeLauncher/ :
//
//   config.json   – which folders to scan for candidates
//   library.json  – the curated projects and the user's sidebar sections
//   prefs.json    – per-project launch choices, favorites, recency
//
// All three decode field-by-field with `decodeIfPresent`, so adding a setting
// in a later version can't make an older file fail to load and silently reset
// somebody's configuration.

enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ClaudeLauncher", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir
    }

    static var configFile: URL { supportDirectory.appendingPathComponent("config.json") }
    static var libraryFile: URL { supportDirectory.appendingPathComponent("library.json") }
    static var prefsFile: URL { supportDirectory.appendingPathComponent("prefs.json") }

    /// Generated launch scripts and Terminal profiles live here.
    static var sessionsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir,
                                                 withIntermediateDirectories: true)
        return dir
    }
}

/// Which directories get searched when looking for candidate projects.
struct Config: Codable {

    /// Main folders to search. `~` is expanded at scan time.
    ///
    /// Empty by default: the app has no way to know where a given person keeps
    /// their code, so a fresh install asks rather than guessing at paths that
    /// exist on only one machine.
    var roots: [String] = []

    /// Folder names never offered as candidates (build output, caches…).
    var excludes: [String] = [
        "node_modules", "_archive", "Archive", "archive", ".git", ".build",
        "build", "dist", "out", "venv", ".venv", "__pycache__", "DerivedData",
        "Pods", ".next", ".cache", "vendor", "target", "Library", "Applications"
    ]

    private enum CodingKeys: String, CodingKey { case roots, excludes }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        roots = try c.decodeIfPresent([String].self, forKey: .roots) ?? d.roots
        excludes = try c.decodeIfPresent([String].self, forKey: .excludes) ?? d.excludes
    }

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
        try? encoder.encode(self).write(to: AppPaths.configFile)
    }
}

/// The curated project set and how the user has arranged it.
struct Library: Codable {

    /// Every project the user ticked in the setup sheet.
    var projects: [Project] = []

    /// User-created sidebar sections, in display order.
    var sections: [LibrarySection] = []

    private enum CodingKeys: String, CodingKey { case projects, sections }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        sections = try c.decodeIfPresent([LibrarySection].self, forKey: .sections) ?? []
    }

    static func load() -> Library {
        guard let data = try? Data(contentsOf: AppPaths.libraryFile),
              let decoded = try? JSONDecoder().decode(Library.self, from: data) else {
            return Library()
        }
        return decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(self).write(to: AppPaths.libraryFile)
    }

    /// Projects not filed into any section. They surface under "Unsorted" so a
    /// newly added project can never be invisible.
    var unsortedProjects: [Project] {
        let filed = Set(sections.flatMap(\.projectPaths))
        return projects.filter { !filed.contains($0.path) }
    }
}

/// Per-project launch choices and sidebar state.
struct Prefs: Codable {

    var lastModel: [String: ClaudeModel] = [:]
    var permissionMode: [String: PermissionMode] = [:]
    /// Absent means "don't pass --effort", letting Claude use its own default.
    var effort: [String: EffortLevel] = [:]
    /// Terminal profile name chosen per project, e.g. "Ocean".
    var terminalTheme: [String: String] = [:]
    /// Absent means the session opens with no prompt, which is the default.
    var firstCommand: [String: FirstCommand] = [:]
    var lastUsed: [String: Date] = [:]
    var favorites: [String] = []

    /// Sidebar sections the user has explicitly opened or closed. Only explicit
    /// choices are stored, so a section added later gets the sensible default
    /// rather than inheriting a stale entry.
    var sectionExpanded: [String: Bool] = [:]

    private enum CodingKeys: String, CodingKey {
        case lastModel, permissionMode, effort, terminalTheme, firstCommand
        case lastUsed, favorites, sectionExpanded
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastModel = try c.decodeIfPresent([String: ClaudeModel].self, forKey: .lastModel) ?? [:]
        permissionMode = try c.decodeIfPresent([String: PermissionMode].self, forKey: .permissionMode) ?? [:]
        effort = try c.decodeIfPresent([String: EffortLevel].self, forKey: .effort) ?? [:]
        terminalTheme = try c.decodeIfPresent([String: String].self, forKey: .terminalTheme) ?? [:]
        firstCommand = try c.decodeIfPresent([String: FirstCommand].self, forKey: .firstCommand) ?? [:]
        lastUsed = try c.decodeIfPresent([String: Date].self, forKey: .lastUsed) ?? [:]
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
        sectionExpanded = try c.decodeIfPresent([String: Bool].self, forKey: .sectionExpanded) ?? [:]
    }

    static func load() -> Prefs {
        let decoder = JSONDecoder()
        // Must match the encoder below, or every stored date fails to parse and
        // the Recent list silently comes back empty.
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
