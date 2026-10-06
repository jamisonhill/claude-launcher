import Foundation

// MARK: - AI CLI tools
//
// The app started as a Claude-only launcher, with Claude's flags hard-coded into
// the launch panel. Supporting other CLIs means describing a tool rather than
// assuming one: what it's called, where its binary lives, and which option
// groups it understands.
//
// Every option group here is either verified against the tool installed on the
// author's machine or absent. No flag in this file is guessed from
// documentation — a wrong flag produces a Terminal window that dies on launch,
// which is precisely the failure this app exists to prevent. Tools that can't
// be verified are reachable as custom tools instead, where the flags come from
// the person who can actually run them.

/// One choice within an option group, e.g. the "Opus" model or "Plan Mode".
struct ToolOption: Identifiable, Codable, Hashable {
    /// Stable key stored in prefs. Claude's ids match the values written by
    /// earlier versions ("opus", "bypassPermissions", "high"), so an existing
    /// prefs.json keeps every per-project choice it already had.
    let id: String
    let displayName: String
    let subtitle: String
    /// The value handed to the group's flag.
    let flagValue: String
    /// Marks the one option worth warning about, drawn in red.
    var isDangerous: Bool = false
}

/// A set of mutually exclusive choices that map to a single flag.
struct OptionGroup: Codable, Hashable {
    /// Heading shown above the control, e.g. "MODEL".
    let label: String
    /// The flag these values are passed with, e.g. "--model" or "-m".
    let flag: String
    let options: [ToolOption]
    /// When true the group offers a "Default" entry that passes no flag at all,
    /// letting the tool apply its own default.
    var allowsUnset: Bool = false
    /// Selected when a project has no stored choice. Nil means start unset,
    /// which is only meaningful alongside `allowsUnset`.
    var defaultOptionID: String?
    /// Optional explanatory line under the control.
    var footnote: String?

    func option(id: String?) -> ToolOption? {
        guard let id else { return nil }
        return options.first { $0.id == id }
    }
}

/// A command-line AI tool this launcher can start a session with.
struct AITool: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    /// Executable name, looked up on PATH when the known locations miss.
    var binary: String
    /// Places to look before falling back to a login-shell lookup.
    var candidatePaths: [String] = []

    var modelGroup: OptionGroup?
    var permissionGroup: OptionGroup?
    var effortGroup: OptionGroup?

    /// Whether the tool accepts a positional opening prompt after its flags.
    /// Only true where the tool's own slash commands are known to exist —
    /// Claude's "/resume-work" would arrive at another tool as literal text.
    var supportsFirstCommand: Bool = false

    /// Flags appended verbatim, after the group flags and before any prompt.
    /// This is how a tool gets an option the app doesn't model — Gemini's
    /// `-m <model>`, for instance, whose flag is verified but whose accepted
    /// model names are not, so they aren't offered as a picker.
    var extraArguments: [String] = []

    /// Built-ins ship with the app and can be disabled but not deleted.
    var isBuiltIn: Bool = false

    var groups: [OptionGroup] {
        [modelGroup, permissionGroup, effortGroup].compactMap { $0 }
    }
}

// MARK: - Built-in definitions

extension AITool {

    /// Claude Code. Flags unchanged from the original single-tool version.
    static let claude = AITool(
        id: "claude",
        name: "Claude Code",
        binary: "claude",
        candidatePaths: [
            "~/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "~/.bun/bin/claude",
            "~/.npm-global/bin/claude"
        ],
        // Model values are family *aliases*, not pinned ids. `claude --help`
        // documents --model as taking "an alias for the latest model (e.g.
        // 'fable', 'opus', or 'sonnet') or a model's full name", and the CLI
        // resolves a bare family name to the newest release in that family.
        //
        // Pinning exact ids is what the first version did, and it rotted: the
        // app shipped "claude-opus-5" and kept launching it after Opus 5.5
        // came out. An alias means picking Opus always gets today's Opus, with
        // no release of this app required when Anthropic ships the next one.
        modelGroup: OptionGroup(
            label: "MODEL",
            flag: "--model",
            options: [
                ToolOption(id: "opus",   displayName: "Opus",   subtitle: "Most capable",     flagValue: "opus"),
                ToolOption(id: "fable",  displayName: "Fable",  subtitle: "Creative writing", flagValue: "fable"),
                ToolOption(id: "sonnet", displayName: "Sonnet", subtitle: "Balanced",         flagValue: "sonnet"),
                ToolOption(id: "haiku",  displayName: "Haiku",  subtitle: "Fastest",          flagValue: "haiku")
            ],
            defaultOptionID: "opus"
        ),
        permissionGroup: OptionGroup(
            label: "PERMISSIONS",
            flag: "--permission-mode",
            options: [
                ToolOption(id: "bypassPermissions", displayName: "Bypass All",    subtitle: "No prompts at all",        flagValue: "bypassPermissions", isDangerous: true),
                ToolOption(id: "acceptEdits",       displayName: "Accept Edits",  subtitle: "Edits auto, commands ask", flagValue: "acceptEdits"),
                ToolOption(id: "plan",              displayName: "Plan Mode",     subtitle: "Plan before acting",       flagValue: "plan"),
                ToolOption(id: "dontAsk",           displayName: "Don't Ask",     subtitle: "Skip prompts, keep checks", flagValue: "dontAsk"),
                ToolOption(id: "auto",              displayName: "Auto",          subtitle: "Decide per action",        flagValue: "auto"),
                ToolOption(id: "manual",            displayName: "Ask Each Time", subtitle: "Prompt for everything",    flagValue: "manual")
            ],
            defaultOptionID: "bypassPermissions"
        ),
        effortGroup: OptionGroup(
            label: "EFFORT",
            flag: "--effort",
            options: [
                ToolOption(id: "low",    displayName: "Low",    subtitle: "", flagValue: "low"),
                ToolOption(id: "medium", displayName: "Medium", subtitle: "", flagValue: "medium"),
                ToolOption(id: "high",   displayName: "High",   subtitle: "", flagValue: "high"),
                ToolOption(id: "xhigh",  displayName: "X-High", subtitle: "", flagValue: "xhigh"),
                ToolOption(id: "max",    displayName: "Max",    subtitle: "", flagValue: "max")
            ],
            allowsUnset: true
        ),
        supportsFirstCommand: true,
        isBuiltIn: true
    )

    /// Gemini CLI.
    ///
    /// Only `--approval-mode` is offered, because only its values are
    /// enumerated by `gemini --help` (default / auto_edit / yolo / plan). The
    /// `-m/--model` flag exists too, but the CLI publishes no list of accepted
    /// model names, so a picker here would be guesswork — set a model through
    /// this tool's extra arguments instead.
    static let gemini = AITool(
        id: "gemini",
        name: "Gemini CLI",
        binary: "gemini",
        candidatePaths: [
            "/opt/homebrew/bin/gemini",
            "/usr/local/bin/gemini",
            "~/.local/bin/gemini",
            "~/.npm-global/bin/gemini"
        ],
        permissionGroup: OptionGroup(
            label: "APPROVAL MODE",
            flag: "--approval-mode",
            options: [
                ToolOption(id: "yolo",      displayName: "YOLO",       subtitle: "Auto-approve everything", flagValue: "yolo", isDangerous: true),
                ToolOption(id: "auto_edit", displayName: "Auto Edit",  subtitle: "Auto-approve edits",      flagValue: "auto_edit"),
                ToolOption(id: "plan",      displayName: "Plan",       subtitle: "Read-only",               flagValue: "plan"),
                ToolOption(id: "default",   displayName: "Ask",        subtitle: "Prompt for approval",     flagValue: "default")
            ],
            defaultOptionID: "default",
            footnote: "Set a model with -m in this tool's extra arguments (Settings → AI Tools)."
        ),
        isBuiltIn: true
    )

    static let builtIns: [AITool] = [.claude, .gemini]
}
