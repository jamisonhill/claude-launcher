import Foundation

// Launch options for a specific tool (models, permission modes, effort)
// are no longer enum cases here — they are data on AITool, in AITools.swift,
// because which options exist depends on which CLI is being launched.

// MARK: - First command

/// A slash command to run as the session's opening prompt.
///
/// Claude takes a positional prompt after its flags, and a prompt beginning
/// with "/" runs as a slash command rather than arriving as literal text — so
/// resuming can start the moment the window opens instead of after typing the
/// same thing every time.
enum FirstCommand: String, CaseIterable, Identifiable, Codable {
    case start
    case resumeWork

    var id: String { rawValue }

    /// The prompt handed to Claude.
    var prompt: String {
        switch self {
        case .start:      return "/start"
        case .resumeWork: return "/resume-work"
        }
    }

    /// Shown on the picker; the leading slash makes it obvious these run as
    /// commands rather than being typed into the session.
    var displayName: String { prompt }

    /// Nil means start the session with no opening prompt, which is the default.
    static let unsetLabel = "None"
}

// MARK: - Projects

/// A curated project the user has explicitly chosen to keep in their library.
struct Project: Identifiable, Hashable, Codable {
    /// Absolute path on disk. Doubles as the stable identifier used everywhere.
    let path: String
    /// Folder name, e.g. "exec-dashboard".
    let name: String
    /// Home-relative path for display, e.g. "~/Ai/MHIT/DATA-ANALYTICS/…".
    let displayPath: String
    /// Whether the folder contains a .git directory (shown as a badge).
    let isGitRepo: Bool

    var id: String { path }
}

/// A folder offered in the setup sheet for the user to accept or reject.
///
/// Nothing here decides *visibility* — every folder found becomes a candidate.
/// The marker hints only drive which boxes start ticked, because guessing what
/// counts as a project is exactly what hid `exec-dashboard` in the first place.
struct ProjectCandidate: Identifiable, Hashable {
    let path: String
    let name: String
    let displayPath: String
    /// How deep below its root this folder sits, used for indenting the list.
    let depth: Int
    /// Marker that made this look like a project ("package.json", ".git"), or
    /// nil when nothing was found.
    let marker: String?
    /// Number of visible items inside, shown when there's no marker to report.
    let itemCount: Int
    let isGitRepo: Bool
    /// Whether this candidate starts ticked in the setup sheet.
    ///
    /// Decided by the scanner rather than derived from `marker`, because the
    /// call depends on a folder's siblings and children, not just itself.
    let preselect: Bool

    var id: String { path }

    var isLikelyProject: Bool { preselect }

    /// Right-hand hint text in the picker.
    var hint: String {
        if let marker { return marker }
        return itemCount == 1 ? "1 item" : "\(itemCount) items"
    }
}

// MARK: - Sidebar organisation

/// A user-created, user-named sidebar section.
///
/// Sections are manual on purpose. Deriving them from the folder tree produced
/// headings that made sense on one machine and nonsense on another, and it
/// couldn't express groupings that cut across directories.
struct LibrarySection: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    /// Paths of the projects filed here, in the user's chosen order.
    var projectPaths: [String]

    init(id: UUID = UUID(), name: String, projectPaths: [String] = []) {
        self.id = id
        self.name = name
        self.projectPaths = projectPaths
    }
}
