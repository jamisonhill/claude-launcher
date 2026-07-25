import Foundation

// MARK: - Models

/// The Claude models this launcher can start a session with.
///
/// `modelID` is the exact string handed to `claude --model <id>`. If Anthropic
/// ships a new model, updating the string here is the only change needed.
enum ClaudeModel: String, CaseIterable, Identifiable, Codable {
    case opus
    case fable
    case sonnet
    case haiku

    var id: String { rawValue }

    /// Label shown on the button in the UI.
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

    /// One-line hint under the button so you don't have to remember the tiers.
    var subtitle: String {
        switch self {
        case .opus:   return "Most capable"
        case .fable:  return "Creative writing"
        case .sonnet: return "Balanced"
        case .haiku:  return "Fastest"
        }
    }
}

/// A single launchable project directory found by the scanner.
struct Project: Identifiable, Hashable {
    /// Absolute path on disk. Doubles as the stable identifier used in prefs.
    let path: String
    /// Folder name, e.g. "claudeLauncher".
    let name: String
    /// Section heading in the sidebar, e.g. "PERSONAL / APPS".
    let group: String
    /// Home-relative path for display, e.g. "~/Ai/Personal/apps/claudeLauncher".
    let displayPath: String
    /// Whether the folder contains a .git directory (shown as a badge).
    let isGitRepo: Bool

    var id: String { path }
}
