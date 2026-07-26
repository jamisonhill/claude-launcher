import Foundation

// MARK: - Launch options

/// The Claude models this launcher can start a session with.
///
/// `modelID` is the exact string handed to `claude --model <id>`. If Anthropic
/// ships a new model, updating the string here is the only change needed.
enum ClaudeModel: String, CaseIterable, Identifiable, Codable {
    case opus, fable, sonnet, haiku

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus:   return "Opus"
        case .fable:  return "Fable"
        case .sonnet: return "Sonnet"
        case .haiku:  return "Haiku"
        }
    }

    /// The value passed to the `--model` flag.
    var modelID: String {
        switch self {
        case .opus:   return "claude-opus-5"
        case .fable:  return "claude-fable-5"
        case .sonnet: return "claude-sonnet-5"
        case .haiku:  return "claude-haiku-4-5-20251001"
        }
    }

    var subtitle: String {
        switch self {
        case .opus:   return "Most capable"
        case .fable:  return "Creative writing"
        case .sonnet: return "Balanced"
        case .haiku:  return "Fastest"
        }
    }
}

/// Values accepted by `claude --permission-mode`.
///
/// This replaces the old on/off "skip permissions" toggle. The toggle was only
/// ever `bypassPermissions` under a friendlier name, so nothing is lost by
/// exposing the real choices — and `plan` and `acceptEdits` become reachable.
enum PermissionMode: String, CaseIterable, Identifiable, Codable {
    case bypassPermissions
    case acceptEdits
    case plan
    case dontAsk
    case auto
    case manual

    var id: String { rawValue }

    /// The value passed to `--permission-mode`.
    var flagValue: String { rawValue }

    var displayName: String {
        switch self {
        case .bypassPermissions: return "Bypass All"
        case .acceptEdits:       return "Accept Edits"
        case .plan:              return "Plan Mode"
        case .dontAsk:           return "Don't Ask"
        case .auto:              return "Auto"
        case .manual:            return "Ask Each Time"
        }
    }

    var subtitle: String {
        switch self {
        case .bypassPermissions: return "No prompts at all"
        case .acceptEdits:       return "Edits auto, commands ask"
        case .plan:              return "Plan before acting"
        case .dontAsk:           return "Skip prompts, keep checks"
        case .auto:              return "Decide per action"
        case .manual:            return "Prompt for everything"
        }
    }

    /// The one mode worth warning about in the UI.
    var isDangerous: Bool { self == .bypassPermissions }

    /// You chose skip-permissions-on-by-default, which is exactly this mode.
    static let defaultMode: PermissionMode = .bypassPermissions
}

/// Values accepted by `claude --effort`.
enum EffortLevel: String, CaseIterable, Identifiable, Codable {
    case low, medium, high, xhigh, max

    var id: String { rawValue }
    var flagValue: String { rawValue }

    var displayName: String {
        switch self {
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        case .xhigh:  return "X-High"
        case .max:    return "Max"
        }
    }

    /// Nil means "don't pass --effort at all", letting Claude use its default.
    static let unsetLabel = "Default"
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
