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

    /// Favorited project paths, in pin order. Mirrors `prefs.favorites`, but
    /// published so the sidebar redraws the moment a star is clicked.
    @Published private(set) var favorites: [String] = []

    /// Sidebar sections currently collapsed. Also a published mirror of prefs.
    @Published private(set) var collapsedGroups: Set<String> = []

    private var config: Config
    private var prefs: Prefs

    init() {
        self.config = Config.load()
        self.prefs = Prefs.load()
        self.claudePath = Launcher.findClaudeExecutable()
        self.favorites = prefs.favorites
        self.collapsedGroups = Set(prefs.collapsedGroups)
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
        guard isSearching == false else { return [] }
        return prefs.lastUsed
            .sorted { $0.value > $1.value }
            .prefix(5)
            .compactMap { entry in projects.first { $0.path == entry.key } }
    }

    /// Pinned projects, in the order they were favorited. Like Recent, hidden
    /// during a search so results aren't listed twice.
    var favoriteProjects: [Project] {
        guard isSearching == false else { return [] }
        return favorites.compactMap { path in
            projects.first { $0.path == path }
        }
    }

    /// True when the search box has content, which collapses the sidebar down
    /// to a single flat list of matches.
    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
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
        // Auto-select something sensible so the app is usable the instant it
        // opens, without a click. Recency beats a pin here — the last thing you
        // worked on is more often the next thing you want.
        if selectedPath == nil,
           let first = recentProjects.first ?? favoriteProjects.first ?? projects.first {
            select(first)
        }
    }

    // MARK: Favorites

    func isFavorite(_ project: Project) -> Bool {
        favorites.contains(project.path)
    }

    /// Pins or unpins a project. New favorites append to the end so the list
    /// stays in the order you added them rather than reshuffling.
    func toggleFavorite(_ project: Project) {
        if let index = favorites.firstIndex(of: project.path) {
            favorites.remove(at: index)
        } else {
            favorites.append(project.path)
        }
        prefs.favorites = favorites
        prefs.save()
    }

    /// Drag-to-reorder support for the Favorites section.
    func moveFavorites(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        favorites.move(fromOffsets: offsets, toOffset: destination)
        prefs.favorites = favorites
        prefs.save()
    }

    // MARK: Section collapsing

    /// A binding for `Section(isExpanded:)`. We store the *collapsed* set, so a
    /// group nobody has touched reads as expanded.
    func expansionBinding(for group: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard let self else { return true }
                return !self.collapsedGroups.contains(group)
            },
            set: { [weak self] isExpanded in
                guard let self else { return }
                if isExpanded {
                    self.collapsedGroups.remove(group)
                } else {
                    self.collapsedGroups.insert(group)
                }
                self.prefs.collapsedGroups = Array(self.collapsedGroups)
                self.prefs.save()
            }
        )
    }

    /// True when every visible section is collapsed — drives the footer button's
    /// icon and whether it expands or collapses on the next click.
    var allSectionsCollapsed: Bool {
        var visible = Set(groupedProjects.map(\.group))
        if !favoriteProjects.isEmpty { visible.insert(Self.favoritesSection) }
        if !recentProjects.isEmpty { visible.insert(Self.recentSection) }
        return !visible.isEmpty && visible.isSubset(of: collapsedGroups)
    }

    /// Collapses or expands everything at once, from the sidebar footer.
    func setAllSectionsExpanded(_ expanded: Bool) {
        if expanded {
            collapsedGroups = []
        } else {
            var all = Set(groupedProjects.map(\.group))
            all.insert(Self.favoritesSection)
            all.insert(Self.recentSection)
            collapsedGroups = all
        }
        prefs.collapsedGroups = Array(collapsedGroups)
        prefs.save()
    }

    /// Section headings for the two special sections, kept as constants so the
    /// collapse state persists under a stable key.
    static let favoritesSection = "FAVORITES"
    static let recentSection = "RECENT"

    // MARK: Selection

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

    /// Shows a project folder in Finder.
    func revealProject(_ project: Project) {
        NSWorkspace.shared.activateFileViewerSelecting(
            [URL(fileURLWithPath: project.path)])
    }

    /// Pins or unpins whatever is currently selected (⌘D from the menu bar).
    func toggleFavoriteForSelection() {
        guard let project = selectedProject else { return }
        toggleFavorite(project)
    }
}
