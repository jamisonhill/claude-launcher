import AppKit
import Foundation
import SwiftUI

// MARK: - App state
//
// One observable object holds the curated library, the sidebar arrangement, the
// current selection, and the remembered launch choices.

@MainActor
final class LauncherStore: ObservableObject {

    // Library and arrangement
    @Published private(set) var projects: [Project] = []
    @Published private(set) var sections: [LibrarySection] = []
    @Published private(set) var favorites: [String] = []

    // Selection and search
    @Published var selectedPath: String?
    @Published var searchText: String = ""

    // Launch choices for the current selection
    @Published var selectedModel: ClaudeModel = .opus
    @Published var permissionMode: PermissionMode = .defaultMode
    @Published var effort: EffortLevel?
    @Published var terminalTheme: String?

    // Transient UI state
    @Published var errorMessage: String?
    @Published var lastLaunchNote: String?
    @Published var isShowingSetup = false
    @Published private(set) var candidates: [ProjectCandidate] = []
    @Published private(set) var isScanning = false

    @Published private(set) var claudePath: String?
    @Published private(set) var availableThemes: [String] = []
    @Published private(set) var sectionExpanded: [String: Bool] = [:]
    @Published private(set) var roots: [String] = []

    private var config: Config
    private var library: Library
    private var prefs: Prefs

    static let favoritesSection = "FAVORITES"
    static let recentSection = "RECENT"
    static let unsortedSection = "UNSORTED"

    init() {
        self.config = Config.load()
        self.library = Library.load()
        self.prefs = Prefs.load()
        self.claudePath = Launcher.findClaudeExecutable()
        self.availableThemes = TerminalThemes.availableProfileNames()

        self.projects = library.projects
        self.sections = library.sections
        self.favorites = prefs.favorites
        self.sectionExpanded = prefs.sectionExpanded
        self.roots = config.roots

        restoreDefaultSelection()
    }

    // MARK: - Derived values

    var selectedProject: Project? {
        guard let selectedPath else { return nil }
        return projects.first { $0.path == selectedPath }
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True before any folder has been chosen — drives the welcome state.
    var needsSetup: Bool { roots.isEmpty || projects.isEmpty }

    var filteredProjects: [Project] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return projects }
        return projects.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.displayPath.localizedCaseInsensitiveContains(query)
        }
    }

    var recentProjects: [Project] {
        guard !isSearching else { return [] }
        return prefs.lastUsed
            .sorted { $0.value > $1.value }
            .prefix(5)
            .compactMap { entry in projects.first { $0.path == entry.key } }
    }

    var favoriteProjects: [Project] {
        guard !isSearching else { return [] }
        return favorites.compactMap { path in projects.first { $0.path == path } }
    }

    /// Projects filed into a given section, in the user's order.
    func projects(in section: LibrarySection) -> [Project] {
        section.projectPaths.compactMap { path in projects.first { $0.path == path } }
    }

    /// Projects not filed anywhere. Surfaced under "Unsorted" so a newly added
    /// project can never be invisible.
    var unsortedProjects: [Project] {
        let filed = Set(sections.flatMap(\.projectPaths))
        return projects.filter { !filed.contains($0.path) }
    }

    var launchOptions: LaunchOptions {
        LaunchOptions(model: selectedModel,
                      permissionMode: permissionMode,
                      effort: effort,
                      terminalTheme: terminalTheme)
    }

    var commandPreview: String {
        guard let project = selectedProject else { return "" }
        return Launcher.commandPreview(project: project,
                                       options: launchOptions,
                                       claudePath: claudePath)
    }

    func lastUsedDescription(for project: Project) -> String? {
        guard let date = prefs.lastUsed[project.path] else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last opened " + formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Setup and curation

    /// Presents a folder chooser, records it as a root, then opens the picker.
    func chooseMainFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder your projects live in."

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        for url in panel.urls {
            let stored = abbreviatingHome(url.path)
            if !roots.contains(stored) { roots.append(stored) }
        }
        config.roots = roots
        config.save()
        beginCuration()
    }

    /// Scans the roots and opens the setup sheet.
    ///
    /// Scanning happens off the main actor: a deep walk of a large tree takes
    /// long enough to visibly stall the window otherwise.
    func beginCuration() {
        guard !roots.isEmpty else { return }
        isScanning = true
        isShowingSetup = true

        let snapshot = config
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                ProjectScanner.candidates(config: snapshot)
            }.value

            self.candidates = found
            self.isScanning = false
        }
    }

    /// Replaces the library with the chosen set, preserving existing sections.
    func applyCuration(selectedPaths: Set<String>) {
        let chosen = selectedPaths.sorted().map { ProjectScanner.project(at: $0) }
        projects = chosen
        library.projects = chosen

        // Drop references to projects that are no longer in the library, so a
        // section can't hold a path that resolves to nothing.
        let valid = Set(selectedPaths)
        for index in sections.indices {
            sections[index].projectPaths.removeAll { !valid.contains($0) }
        }
        library.sections = sections
        library.save()

        favorites.removeAll { !valid.contains($0) }
        prefs.favorites = favorites
        prefs.lastUsed = prefs.lastUsed.filter { valid.contains($0.key) }
        prefs.save()

        isShowingSetup = false
        restoreDefaultSelection()
    }

    func cancelCuration() {
        isShowingSetup = false
    }

    /// Paths already in the library, used to pre-tick the sheet on a re-run.
    var curatedPaths: Set<String> { Set(projects.map(\.path)) }

    private func restoreDefaultSelection() {
        if let selectedPath, projects.contains(where: { $0.path == selectedPath }) { return }
        if let first = recentProjects.first ?? favoriteProjects.first ?? projects.first {
            select(first)
        } else {
            selectedPath = nil
        }
    }

    private func abbreviatingHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }

    func removeRoot(_ path: String) {
        roots.removeAll { $0 == path }
        config.roots = roots
        config.save()
    }

    // MARK: - Sections

    func addSection(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        sections.append(LibrarySection(name: trimmed))
        persistSections()
    }

    func renameSection(_ section: LibrarySection, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let index = sections.firstIndex(where: { $0.id == section.id }) else { return }
        sections[index].name = trimmed
        persistSections()
    }

    /// Deletes a section. Its projects fall back to Unsorted rather than being
    /// removed from the library.
    func deleteSection(_ section: LibrarySection) {
        sections.removeAll { $0.id == section.id }
        persistSections()
    }

    func moveSections(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        sections.move(fromOffsets: offsets, toOffset: destination)
        persistSections()
    }

    /// Files a project into a section, removing it from wherever it was.
    /// Passing nil moves it back to Unsorted.
    func move(projectPath: String, toSection sectionID: UUID?) {
        for index in sections.indices {
            sections[index].projectPaths.removeAll { $0 == projectPath }
        }
        if let sectionID,
           let index = sections.firstIndex(where: { $0.id == sectionID }),
           !sections[index].projectPaths.contains(projectPath) {
            sections[index].projectPaths.append(projectPath)
        }
        persistSections()
    }

    /// Reorders projects within one section.
    func moveProjects(in section: LibrarySection,
                      fromOffsets offsets: IndexSet,
                      toOffset destination: Int) {
        guard let index = sections.firstIndex(where: { $0.id == section.id }) else { return }
        sections[index].projectPaths.move(fromOffsets: offsets, toOffset: destination)
        persistSections()
    }

    /// The section a project currently lives in, if any.
    func section(containing projectPath: String) -> LibrarySection? {
        sections.first { $0.projectPaths.contains(projectPath) }
    }

    private func persistSections() {
        library.sections = sections
        library.save()
    }

    // MARK: - Favorites

    func isFavorite(_ project: Project) -> Bool { favorites.contains(project.path) }

    func toggleFavorite(_ project: Project) {
        if let index = favorites.firstIndex(of: project.path) {
            favorites.remove(at: index)
        } else {
            favorites.append(project.path)
        }
        prefs.favorites = favorites
        prefs.save()
    }

    func moveFavorites(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        favorites.move(fromOffsets: offsets, toOffset: destination)
        prefs.favorites = favorites
        prefs.save()
    }

    func toggleFavoriteForSelection() {
        guard let project = selectedProject else { return }
        toggleFavorite(project)
    }

    // MARK: - Section collapsing

    /// Favorites and Recent open by default; everything else starts collapsed,
    /// which is what keeps a large library readable on launch.
    func defaultExpanded(_ key: String) -> Bool {
        key == Self.favoritesSection || key == Self.recentSection
    }

    func isExpanded(_ key: String) -> Bool {
        sectionExpanded[key] ?? defaultExpanded(key)
    }

    func expansionBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isExpanded(key) ?? true },
            set: { [weak self] isExpanded in
                guard let self else { return }
                self.sectionExpanded[key] = isExpanded
                self.prefs.sectionExpanded = self.sectionExpanded
                self.prefs.save()
            }
        )
    }

    private var visibleSectionKeys: [String] {
        var keys = sections.map(\.id.uuidString)
        if !favoriteProjects.isEmpty { keys.append(Self.favoritesSection) }
        if !recentProjects.isEmpty { keys.append(Self.recentSection) }
        if !unsortedProjects.isEmpty { keys.append(Self.unsortedSection) }
        return keys
    }

    var allSectionsCollapsed: Bool {
        let keys = visibleSectionKeys
        return !keys.isEmpty && keys.allSatisfy { !isExpanded($0) }
    }

    func setAllSectionsExpanded(_ expanded: Bool) {
        for key in visibleSectionKeys { sectionExpanded[key] = expanded }
        prefs.sectionExpanded = sectionExpanded
        prefs.save()
    }

    // MARK: - Selection

    /// Selects a project and restores whatever launch settings were used there.
    func select(_ project: Project) {
        selectedPath = project.path
        selectedModel = prefs.lastModel[project.path] ?? .opus
        permissionMode = prefs.permissionMode[project.path] ?? .defaultMode
        effort = prefs.effort[project.path]
        // A theme saved before the picker narrowed to five dark ones may no
        // longer be on offer. Dropping it keeps the window's colours and the
        // selected swatch in agreement; otherwise the project would go on
        // launching in a theme with nothing in the picker showing as picked.
        terminalTheme = prefs.terminalTheme[project.path]
            .flatMap { availableThemes.contains($0) ? $0 : nil }
        lastLaunchNote = nil
    }

    // MARK: - Launching

    func launch() {
        guard let project = selectedProject else { return }

        do {
            try Launcher.launch(project: project, options: launchOptions)

            // Only record the launch once it actually succeeded, so a failed
            // attempt doesn't pollute the Recent list.
            prefs.lastModel[project.path] = selectedModel
            prefs.permissionMode[project.path] = permissionMode
            prefs.effort[project.path] = effort
            prefs.terminalTheme[project.path] = terminalTheme
            prefs.lastUsed[project.path] = Date()
            prefs.save()

            lastLaunchNote = "Launched \(project.name) with \(selectedModel.displayName)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Finder

    func revealProject(_ project: Project) {
        NSWorkspace.shared.activateFileViewerSelecting(
            [URL(fileURLWithPath: project.path)])
    }

    func revealConfigFile() {
        config.save()
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.configFile])
    }
}
