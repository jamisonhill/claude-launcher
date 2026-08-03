import AppKit
import Foundation

// MARK: - Launching a Claude Code session
//
// We write a small executable script and ask Terminal.app to open it, either
// directly (`.command`) or via a generated colour profile (`.terminal`). macOS
// opens both in a fresh Terminal window and runs them, which gives us the new
// window, the right directory, and Claude running.
//
// Avoiding AppleScript is deliberate: sending Apple Events to Terminal requires
// an Automation permission grant tied to the app's code signature. An ad-hoc
// signed app that gets rebuilt would re-prompt for that permission constantly.
// Opening a file has no such requirement.

/// Everything the user chose in the launch panel.
struct LaunchOptions {
    var model: ClaudeModel = .opus
    var permissionMode: PermissionMode = .defaultMode
    /// Nil means don't pass `--effort` at all.
    var effort: EffortLevel?
    /// Terminal profile name to colour the window with, or nil for the default.
    var terminalTheme: String?
    /// Slash command to run as the opening prompt, or nil to start empty.
    var firstCommand: FirstCommand?
}

enum Launcher {

    enum LaunchError: LocalizedError {
        case missingDirectory(String)
        case claudeNotFound
        case scriptWriteFailed(String)
        case terminalLaunchFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingDirectory(let path):
                return "That folder no longer exists:\n\(path)"
            case .claudeNotFound:
                return "Couldn't find the `claude` executable in any of the usual locations."
            case .scriptWriteFailed(let reason):
                return "Couldn't write the launch script: \(reason)"
            case .terminalLaunchFailed(let reason):
                return "Terminal wouldn't open the launch script: \(reason)"
            }
        }
    }

    // MARK: - Locating the CLI

    private static let candidateClaudePaths = [
        "~/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "~/.bun/bin/claude",
        "~/.npm-global/bin/claude"
    ]

    /// Resolves an absolute path to the `claude` binary.
    ///
    /// Resolved up front rather than relying on the script's PATH, so a missing
    /// CLI produces a clear dialog instead of a Terminal window that flashes
    /// "command not found" and vanishes.
    static func findClaudeExecutable() -> String? {
        for candidate in candidateClaudePaths {
            let expanded = (candidate as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }

        // Last resort: ask a login shell, which picks up PATH changes made in
        // .zprofile / .zshrc that this GUI app doesn't otherwise inherit.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let path = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            // Shell lookup failed; fall through to nil so the caller reports it.
        }
        return nil
    }

    // MARK: - Building the command

    /// The flags implied by a set of options, in a stable order.
    static func arguments(for options: LaunchOptions) -> [String] {
        var args = ["--model", options.model.modelID,
                    "--permission-mode", options.permissionMode.flagValue]
        if let effort = options.effort {
            args += ["--effort", effort.flagValue]
        }
        // The prompt is positional and must come after every flag, so it stays
        // last. Claude runs a prompt starting with "/" as a slash command.
        if let firstCommand = options.firstCommand {
            args.append(firstCommand.prompt)
        }
        return args
    }

    /// The exact command that will run, used both for the preview line in the
    /// UI and for the generated script. One source of truth means the preview
    /// can't drift from what actually executes.
    static func commandPreview(project: Project,
                               options: LaunchOptions,
                               claudePath: String?) -> String {
        let claude = claudePath.map { shellQuote($0) } ?? "claude"
        let flags = arguments(for: options).joined(separator: " ")
        return "cd \(shellQuote(project.path)) && \(claude) \(flags)"
    }

    /// Wraps a string in single quotes, safely, for use in a shell command.
    /// Embedded single quotes are closed, escaped, and reopened: it's → 'it'\''s'
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Launching

    /// Writes the launch script and opens it in a new Terminal window.
    static func launch(project: Project, options: LaunchOptions) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw LaunchError.missingDirectory(project.path)
        }

        guard let claudePath = findClaudeExecutable() else {
            throw LaunchError.claudeNotFound
        }

        let safeName = project.name.replacingOccurrences(
            of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        let scriptURL = AppPaths.sessionsDirectory
            .appendingPathComponent("\(safeName).command")

        let flags = arguments(for: options).map(shellQuote).joined(separator: " ")

        // `-l` runs a login shell so the session gets the normal environment.
        // `exec` replaces the shell with Claude, so quitting Claude closes the
        // session cleanly instead of dropping you into a leftover subshell.
        let script = """
        #!/bin/zsh -l
        cd \(shellQuote(project.path)) || exit 1
        clear
        exec \(shellQuote(claudePath)) \(flags)
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: scriptURL.path)
        } catch {
            throw LaunchError.scriptWriteFailed(error.localizedDescription)
        }

        // With a theme, open a generated profile that carries both the colours
        // and the script. Without one — or if the profile can't be built — open
        // the script directly and let Terminal use its default profile.
        if let theme = options.terminalTheme,
           let profileURL = TerminalThemes.makeProfile(basedOn: theme,
                                                       runningScriptAt: scriptURL.path,
                                                       windowTitle: project.name) {
            try openInTerminal(profileURL)
        } else {
            try openInTerminal(scriptURL)
        }
    }

    /// Hands a file to Terminal.app specifically, rather than whatever app
    /// happens to be the default handler for its extension.
    private static func openInTerminal(_ fileURL: URL) throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true   // bring the new window to the front

        var launchError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        NSWorkspace.shared.open([fileURL],
                                withApplicationAt: terminalApplicationURL(),
                                configuration: configuration) { _, error in
            launchError = error
            semaphore.signal()
        }

        // Wait briefly so a failure can surface in the UI. If Terminal is slow
        // to launch we stop waiting and assume success rather than freezing.
        _ = semaphore.wait(timeout: .now() + 5)

        if let launchError {
            throw LaunchError.terminalLaunchFailed(launchError.localizedDescription)
        }
    }

    /// Terminal.app moved into /System/Applications in newer macOS versions;
    /// check both locations before falling back to a bundle-ID lookup.
    private static func terminalApplicationURL() -> URL {
        let knownPaths = [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app"
        ]
        for path in knownPaths where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal") {
            return url
        }
        return URL(fileURLWithPath: knownPaths[0])
    }
}
