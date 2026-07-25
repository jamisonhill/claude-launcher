import AppKit
import Foundation
import SwiftUI

// MARK: - App state
//
// One observable object holds everything the UI reads: the scanned projects,
// the current selection, sidebar state, and the remembered preferences.
// SwiftUI redraws automatically whenever a @Published value changes.

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

    /// Explicit open/closed choices per section. Sections absent from this map
    /// use `defaultExpanded(_:)`.
    @Published private(set) var sectionExpanded: [String: Bool] = [:]

    /// Folders configured as scan roots, as stored (may contain "~").
    @Published private(set) var roots: [String] = []

    /// When true, folders without project markers are listed too.
    @Published private(set) var showAllFolders: Bool = false

    private var config: Config
    private var prefs: Prefs

    /// Section headings for the two special sections, kept as constants so
    /// their expansion state persists under a stable key.
    static let favoritesSection = "FAVORITES"
    static let recentSection = "RECENT"

    init() {
        self.config = Config.load()
        self.prefs = Prefs.load()
        self.claudePath = Launcher.findClaudeExecutable()
        self.favorites = prefs.favorites
        self.sectionExpanded = prefs.sectionExpanded
        self.roots = config.roots
        self.showAllFolders = config.showAllFolders
        refresh()
    }

    // MARK: - Derived values

    /// The project object matching `selectedPath`, if any.
    var selectedProject: Project? {
        guard let selectedPath else { return nil }
        return projects.first { $0.path == selectedPath }
    }

    /// True when the search box has content, which collapses the sidebar down
    /// to a single flat list of matches.
    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True on a fresh install, before any scan root has been chosen.
    var hasNoRoots: Bool { roots.isEmpty }

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
        guard !isSearching else { return [] }
        return prefs.lastUsed
            .sorted { $0.value > $1.value }
            .prefix(5)
            .compactMap { entry in projects.first { $0.path == entry.key } }
    }

    /// Pinned projects, in the order they were favorited. Like Recent, hidden
    /// during a search so results aren't listed twice.
    var favoriteProjects: [Project] {
        guard !isSearching else { return [] }
        return favorites.compactMap { path in
            projects.first { $0.path == path }
        }
    }

    /// The command line that Launch will run, shown live in the UI.
    var commandPreview: String {
        guard let project = selectedProject else { return "" }
        return Launcher.commandPreview(project: project,
                                       model: selectedModel,
                                       skipPermissions: skipPermissions,
                                       claudePath: claudePath)
    }

    /// Human-readable "2 hours ago" style stamp for the detail pane.
    func lastUsedDescription(for project: Project) -> String? {
        guard let date = prefs.lastUsed[project.path] else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last opened " + formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Scanning

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

    // MARK: - Scan roots

    /// Adds a folder to scan, ignoring duplicates, and rescans.
    func addRoot(_ url: URL) {
        let path = abbreviatingHome(url.path)
        guard !roots.contains(path) else { return }
        roots.append(path)
        config.roots = roots
        config.save()
        refresh()
    }

    func removeRoot(_ path: String) {
        roots.removeAll { $0 == path }
        config.roots = roots
        config.save()
        refresh()
    }

    /// Toggles the "list folders without project markers" escape hatch.
    func setShowAllFolders(_ enabled: Bool) {
        showAllFolders = enabled
        config.showAllFolders = enabled
        config.save()
        refresh()
    }

    /// Stores roots with a leading "~" so a config file stays portable between
    /// machines and user accounts.
    private func abbreviatingHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }

    // MARK: - Favorites

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

    /// Pins or unpins whatever is currently selected (⌘D from the menu bar).
    func toggleFavoriteForSelection() {
        guard let project = selectedProject else { return }
        toggleFavorite(project)
    }

    // MARK: - Section collapsing

    /// Favorites and Recent open by default; folder groups start closed.
    ///
    /// Folder groups are the bulk of the sidebar, and starting them collapsed
    /// is what keeps a hundred-project install readable on launch.
    func defaultExpanded(_ section: String) -> Bool {
        section == Self.favoritesSection || section == Self.recentSection
    }

    func isExpanded(_ section: String) -> Bool {
        sectionExpanded[section] ?? defaultExpanded(section)
    }

    /// A binding for `Section(isExpanded:)`.
    func expansionBinding(for section: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isExpanded(section) ?? true },
            set: { [weak self] isExpanded in
                guard let self else { return }
                self.sectionExpanded[section] = isExpanded
                self.prefs.sectionExpanded = self.sectionExpanded
                self.prefs.save()
            }
        )
    }

    /// Every section currently visible in the sidebar.
    private var visibleSections: [String] {
        var sections = groupedProjects.map(\.group)
        if !favoriteProjects.isEmpty { sections.append(Self.favoritesSection) }
        if !recentProjects.isEmpty { sections.append(Self.recentSection) }
        return sections
    }

    /// True when every visible section is closed — drives the toolbar button's
    /// icon and whether the next click expands or collapses.
    var allSectionsCollapsed: Bool {
        let sections = visibleSections
        return !sections.isEmpty && sections.allSatisfy { !isExpanded($0) }
    }

    /// Collapses or expands everything at once.
    func setAllSectionsExpanded(_ expanded: Bool) {
        for section in visibleSections {
            sectionExpanded[section] = expanded
        }
        prefs.sectionExpanded = sectionExpanded
        prefs.save()
    }

    // MARK: - Selection

    /// Selects a project and restores whatever settings were used there last.
    func select(_ project: Project) {
        selectedPath = project.path
        selectedModel = prefs.lastModel[project.path] ?? .opus
        skipPermissions = prefs.skipPermissions[project.path] ?? Prefs.defaultSkipPermissions
        lastLaunchNote = nil
    }

    // MARK: - Launching

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

    // MARK: - Finder

    /// Opens the config file for anyone who'd rather edit JSON than use ⌘,.
    func revealConfigFile() {
        config.save()   // make sure the file exists before pointing Finder at it
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.configFile])
    }

    /// Shows a project folder in Finder.
    func revealProject(_ project: Project) {
        NSWorkspace.shared.activateFileViewerSelecting(
            [URL(fileURLWithPath: project.path)])
    }

    /// Presents a folder chooser and adds the result as a scan root.
    func presentAddRootPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Folder"
        panel.message = "Choose a folder that contains your projects."

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            addRoot(url)
        }
    }
}
