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
    @Published private(set) var selectedTool: AITool = .claude
    @Published var modelID: String?
    @Published var permissionID: String?
    @Published var effortID: String?
    @Published var terminalTheme: String?
    @Published var firstCommand: FirstCommand?

    /// Tools that are installed and switched on, in registry order.
    @Published private(set) var availableTools: [ResolvedTool] = []
    /// Every known tool including the missing and the disabled — Settings needs
    /// to show what wasn't found so the absence is explicable.
    @Published private(set) var allTools: [ResolvedTool] = []

    // Transient UI state
    @Published var errorMessage: String?
    @Published var lastLaunchNote: String?
    @Published var isShowingSetup = false
    @Published private(set) var candidates: [ProjectCandidate] = []
    @Published private(set) var isScanning = false

    /// Where the selected project left off, read from its `.planning/RESUME.md`.
    /// Nil when the project has no note or the note has nothing to say.
    @Published private(set) var resumeNote: ResumeNote?

    @Published private(set) var availableThemes: [String] = []
    @Published private(set) var sectionExpanded: [String: Bool] = [:]
    @Published private(set) var roots: [String] = []

    private var config: Config
    private var library: Library
    private var prefs: Prefs
    private(set) var toolSettings: ToolSettings

    /// Where the selected tool's binary lives, or nil if it isn't installed.
    var selectedToolPath: String? {
        availableTools.first { $0.id == selectedTool.id }?.path
    }

    static let favoritesSection = "FAVORITES"
    static let recentSection = "RECENT"
    static let unsortedSection = "UNSORTED"

    init() {
        self.config = Config.load()
        self.library = Library.load()
        self.prefs = Prefs.load()
        self.toolSettings = ToolSettings.load()
        self.availableThemes = TerminalThemes.availableProfileNames()
        refreshTools()

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
        LaunchOptions(tool: selectedTool,
                      modelID: modelID,
                      permissionID: permissionID,
                      effortID: effortID,
                      terminalTheme: terminalTheme,
                      firstCommand: firstCommand)
    }

    var commandPreview: String {
        guard let project = selectedProject else { return "" }
        return Launcher.commandPreview(project: project,
                                       options: launchOptions,
                                       toolPath: selectedToolPath)
    }

    // MARK: - Tools

    /// Re-scans for installed tools and reconciles the current selection.
    ///
    /// Called at launch and whenever tool settings change, so enabling a tool
    /// or installing one takes effect without restarting the app.
    func refreshTools() {
        allTools = ToolRegistry.resolveAll(settings: toolSettings)
        availableTools = ToolRegistry.selectable(settings: toolSettings)

        // Keep the selection valid: if the chosen tool was disabled, removed,
        // or uninstalled, fall back rather than leaving a dangling definition
        // that would launch nothing.
        if let current = availableTools.first(where: { $0.id == selectedTool.id }) {
            selectedTool = current.tool
        } else if let project = selectedProject {
            selectTool(defaultToolID(for: project), for: project, persist: false)
        } else if let first = availableTools.first {
            selectedTool = first.tool
        }
    }

    /// The tool a project should open with: whatever it last used, if that is
    /// still available, else the first one that is.
    private func defaultToolID(for project: Project) -> String {
        let stored = prefs.tool[project.path] ?? AITool.claude.id
        if availableTools.contains(where: { $0.id == stored }) { return stored }
        return availableTools.first?.id ?? AITool.claude.id
    }

    /// Switches the selected tool and restores that tool's own options for the
    /// project, so moving between tools doesn't overwrite either one's setup.
    func selectTool(_ toolID: String, for project: Project, persist: Bool = true) {
        guard let resolved = availableTools.first(where: { $0.id == toolID })
                ?? allTools.first(where: { $0.id == toolID }) else { return }
        selectedTool = resolved.tool
        restoreOptions(for: project, tool: resolved.tool)

        if persist {
            prefs.tool[project.path] = toolID
            prefs.save()
        }
    }

    /// Loads the stored option ids for a project/tool pair, falling back to the
    /// group defaults. A stored id that isn't valid for this tool is discarded
    /// rather than passed through, which is what keeps an old Claude value from
    /// becoming a bogus flag on another CLI.
    private func restoreOptions(for project: Project, tool: AITool) {
        let key = Prefs.optionKey(project: project.path, tool: tool.id)

        func restore(_ group: OptionGroup?, _ stored: String?) -> String? {
            guard let group else { return nil }
            if let stored, group.options.contains(where: { $0.id == stored }) { return stored }
            return group.allowsUnset ? nil : group.defaultOptionID
        }

        modelID = restore(tool.modelGroup, prefs.lastModel[key])
        permissionID = restore(tool.permissionGroup, prefs.permissionMode[key])
        effortID = restore(tool.effortGroup, prefs.effort[key])
        firstCommand = tool.supportsFirstCommand ? prefs.firstCommand[project.path] : nil
    }

    func setToolEnabled(_ toolID: String, _ enabled: Bool) {
        var disabled = Set(toolSettings.disabledToolIDs)
        if enabled { disabled.remove(toolID) } else { disabled.insert(toolID) }
        toolSettings.disabledToolIDs = disabled.sorted()
        toolSettings.save()
        refreshTools()
    }

    func setExtraArguments(_ raw: String, for toolID: String) {
        // Split on whitespace: enough for the flag pairs this field is for, and
        // predictable. Anything needing embedded spaces belongs in a wrapper
        // script rather than a settings field pretending to be a shell.
        let parts = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.isEmpty {
            toolSettings.extraArguments.removeValue(forKey: toolID)
        } else {
            toolSettings.extraArguments[toolID] = parts
        }
        toolSettings.save()
        refreshTools()
        if let project = selectedProject { selectTool(selectedTool.id, for: project, persist: false) }
    }

    func extraArgumentsText(for toolID: String) -> String {
        (toolSettings.extraArguments[toolID] ?? []).joined(separator: " ")
    }

    func addCustomTool(name: String, binary: String, arguments: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedBinary = binary.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedBinary.isEmpty else { return }

        // Derive a stable id from the name, keeping it distinct from built-ins
        // and from any custom tool already defined.
        let base = trimmedName.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        var id = base.isEmpty ? "custom" : base
        let taken = Set(allTools.map(\.id))
        var suffix = 2
        while taken.contains(id) { id = "\(base)-\(suffix)"; suffix += 1 }

        let tool = AITool(id: id, name: trimmedName, binary: trimmedBinary, isBuiltIn: false)
        toolSettings.customTools.append(tool)
        setExtraArguments(arguments, for: id)   // saves and refreshes
    }

    func removeCustomTool(_ toolID: String) {
        toolSettings.customTools.removeAll { $0.id == toolID }
        toolSettings.extraArguments.removeValue(forKey: toolID)
        toolSettings.save()
        refreshTools()
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
        // Restores the tool this project last used along with that tool's own
        // options; persist:false because selecting isn't a change worth writing.
        selectTool(defaultToolID(for: project), for: project, persist: false)
        // A theme saved before the picker narrowed to five dark ones may no
        // longer be on offer. Dropping it keeps the window's colours and the
        // selected swatch in agreement; otherwise the project would go on
        // launching in a theme with nothing in the picker showing as picked.
        terminalTheme = prefs.terminalTheme[project.path]
            .flatMap { availableThemes.contains($0) ? $0 : nil }
        lastLaunchNote = nil
        // Read on selection rather than caching at load: the note changes
        // outside the app, whenever a session ends, and these files are small
        // enough that re-reading one is cheaper than tracking staleness.
        resumeNote = ResumeNote.load(forProjectAt: project.path)
    }

    // MARK: - Launching

    func launch() {
        guard let project = selectedProject else { return }

        do {
            try Launcher.launch(project: project, options: launchOptions)

            // Only record the launch once it actually succeeded, so a failed
            // attempt doesn't pollute the Recent list.
            let key = Prefs.optionKey(project: project.path, tool: selectedTool.id)
            prefs.tool[project.path] = selectedTool.id
            prefs.lastModel[key] = modelID
            prefs.permissionMode[key] = permissionID
            prefs.effort[key] = effortID
            prefs.terminalTheme[project.path] = terminalTheme
            prefs.firstCommand[project.path] = firstCommand
            prefs.lastUsed[project.path] = Date()
            prefs.save()

            // Name the model when the tool has one, else just the tool — the
            // old note assumed every launch had a model to report.
            let model = selectedTool.modelGroup?.option(id: modelID)?.displayName
            lastLaunchNote = model.map { "Launched \(project.name) with \(selectedTool.name) · \($0)" }
                ?? "Launched \(project.name) with \(selectedTool.name)"
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
