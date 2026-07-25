import AppKit
import Foundation
import SwiftUI

// MARK: - App state
//
// One observable object holds everything the UI reads: the scanned projects,
// the current selection, and the remembered preferences. SwiftUI redraws
// automatically whenever a @Published value changes.

@MainActor
final class LauncherStore: ObservableObject {

    @Published private(set) var projects: [Project] = []
    @Published var selectedPath: String?
    @Published var searchText: String = ""

    /// Model + permission choice for the currently selected project.
    @Published var selectedModel: ClaudeModel = .opus
    @Published var skipPermissions: Bool = Prefs.defaultSkipPermissions

    /// Error text shown in an alert when a launch fails.
    @Published var errorMessage: String?
    /// Brief "Launched…" confirmation shown under the button.
    @Published var lastLaunchNote: String?

    /// Resolved path to the `claude` binary, or nil if it couldn't be found.
    /// Looked up once at startup so the command preview is accurate.
    @Published private(set) var claudePath: String?

    private var config: Config
    private var prefs: Prefs

    init() {
        self.config = Config.load()
        self.prefs = Prefs.load()
        self.claudePath = Launcher.findClaudeExecutable()
        refresh()
    }

    // MARK: Derived values

    /// The project object matching `selectedPath`, if any.
    var selectedProject: Project? {
        guard let selectedPath else { return nil }
        return projects.first { $0.path == selectedPath }
    }

    /// Projects matching the search box. An empty search returns everything.
    var filteredProjects: [Project] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return projects }
        return projects.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.displayPath.localizedCaseInsensitiveContains(query)
        }
    }

    /// Sidebar sections, in display order, built from the filtered list.
    var groupedProjects: [(group: String, projects: [Project])] {
        let grouped = Dictionary(grouping: filteredProjects, by: \.group)
        return grouped
            .map { (group: $0.key, projects: $0.value) }
            .sorted { $0.group.localizedCaseInsensitiveCompare($1.group) == .orderedAscending }
    }

    /// Up to five most recently launched projects, newest first. Hidden while
    /// searching so the search results aren't duplicated at the top.
    var recentProjects: [Project] {
        guard searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return prefs.lastUsed
            .sorted { $0.value > $1.value }
            .prefix(5)
            .compactMap { entry in projects.first { $0.path == entry.key } }
    }

    /// The command line that Launch will run, shown live in the UI.
    var commandPreview: String {
        guard let project = selectedProject else { return "" }
        return Launcher.commandPreview(project: project,
                                       model: selectedModel,
                                       skipPermissions: skipPermissions,
                                       claudePath: claudePath)
    }

    /// Human-readable "2h ago" style stamp for the detail pane.
    func lastUsedDescription(for project: Project) -> String? {
        guard let date = prefs.lastUsed[project.path] else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last opened " + formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: Actions

    /// Re-scans the configured roots. Keeps the current selection if it survived.
    func refresh() {
        projects = ProjectScanner.scan(config: config)
        if let selectedPath, !projects.contains(where: { $0.path == selectedPath }) {
            self.selectedPath = nil
        }
        // Auto-select the most recent project so the app is usable the instant
        // it opens, without a click.
        if selectedPath == nil, let first = recentProjects.first ?? projects.first {
            select(first)
        }
    }

    /// Selects a project and restores whatever settings were used there last.
    func select(_ project: Project) {
        selectedPath = project.path
        selectedModel = prefs.lastModel[project.path] ?? .opus
        skipPermissions = prefs.skipPermissions[project.path] ?? Prefs.defaultSkipPermissions
        lastLaunchNote = nil
    }

    /// Opens Terminal with Claude Code running, then remembers the choices.
    func launch() {
        guard let project = selectedProject else { return }

        do {
            try Launcher.launch(project: project,
                                model: selectedModel,
                                skipPermissions: skipPermissions)

            // Only record the launch once it actually succeeded, so a failed
            // attempt doesn't pollute the Recent list.
            prefs.lastModel[project.path] = selectedModel
            prefs.skipPermissions[project.path] = skipPermissions
            prefs.lastUsed[project.path] = Date()
            prefs.save()

            lastLaunchNote = "Launched \(project.name) with \(selectedModel.displayName)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Opens the config file so roots and exclusions can be edited by hand.
    func revealConfigFile() {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.configFile])
    }
}
