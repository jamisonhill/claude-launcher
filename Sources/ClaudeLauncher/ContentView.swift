import SwiftUI

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject private var store: LauncherStore

    var body: some View {
        NavigationSplitView {
            ProjectSidebar()
                .navigationSplitViewColumnWidth(min: 230, ideal: 265, max: 360)
        } detail: {
            if store.selectedProject != nil {
                LaunchPanel()
            } else {
                EmptyStatePanel()
            }
        }
        .sheet(isPresented: $store.isShowingSetup) {
            SetupSheet().environmentObject(store)
        }
        .alert("Couldn't launch",
               isPresented: Binding(get: { store.errorMessage != nil },
                                    set: { if !$0 { store.errorMessage = nil } }),
               actions: { Button("OK", role: .cancel) { store.errorMessage = nil } },
               message: { Text(store.errorMessage ?? "") })
    }
}

// MARK: - Sidebar

private struct ProjectSidebar: View {
    @EnvironmentObject private var store: LauncherStore
    @State private var newSectionName = ""
    @State private var isAddingSection = false
    @State private var renamingSection: LibrarySection?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            if store.needsSetup {
                WelcomeSidebar()
            } else {
                projectList
                Divider()
                addSectionBar
            }
        }
        .searchable(text: $store.searchText,
                    placement: .sidebar,
                    prompt: "Search projects")
        .toolbar {
            ToolbarItem {
                Button {
                    store.setAllSectionsExpanded(store.allSectionsCollapsed)
                } label: {
                    Image(systemName: store.allSectionsCollapsed
                          ? "rectangle.expand.vertical"
                          : "rectangle.compress.vertical")
                }
                .help(store.allSectionsCollapsed ? "Expand all sections" : "Collapse all sections")
                .disabled(store.isSearching || store.needsSetup)
            }
            ToolbarItem {
                Menu {
                    Button("Choose Projects…") { store.beginCuration() }
                        .disabled(store.roots.isEmpty)
                    Button("Add Main Folder…") { store.chooseMainFolder() }
                    Divider()
                    Button("New Section…") { isAddingSection = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Library options")
            }
        }
        .alert("New Section", isPresented: $isAddingSection) {
            TextField("Name", text: $newSectionName)
            Button("Cancel", role: .cancel) { newSectionName = "" }
            Button("Add") {
                store.addSection(named: newSectionName)
                newSectionName = ""
            }
        } message: {
            Text("Sections let you group projects however you like.")
        }
        .alert("Rename Section", isPresented: Binding(
            get: { renamingSection != nil },
            set: { if !$0 { renamingSection = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingSection = nil }
            Button("Rename") {
                if let section = renamingSection {
                    store.renameSection(section, to: renameText)
                }
                renamingSection = nil
            }
        }
    }

    // MARK: List

    private var projectList: some View {
        List(selection: Binding(
            get: { store.selectedPath },
            set: { newValue in
                // Selection must route through select() so the launch settings
                // for that project get restored too.
                if let newValue,
                   let project = store.projects.first(where: { $0.path == newValue }) {
                    store.select(project)
                }
            }
        )) {
            if store.isSearching {
                // A flat list of matches: sections only get in the way once you
                // know what you're after, and a match inside a collapsed
                // section reads as "no such project".
                ForEach(store.filteredProjects) { project in
                    ProjectRow(project: project, showsPath: true).tag(project.path)
                }
            } else {
                specialSections
                userSections
                unsortedSection
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.isSearching && store.filteredProjects.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            }
        }
    }

    @ViewBuilder
    private var specialSections: some View {
        if !store.favoriteProjects.isEmpty {
            Section(isExpanded: store.expansionBinding(for: LauncherStore.favoritesSection)) {
                ForEach(store.favoriteProjects) { project in
                    ProjectRow(project: project, showsPath: false).tag(project.path)
                }
                .onMove { store.moveFavorites(fromOffsets: $0, toOffset: $1) }
            } header: {
                SidebarSectionHeader(title: "FAVORITES", icon: "star.fill",
                                     count: store.favoriteProjects.count)
            }
        }

        if !store.recentProjects.isEmpty {
            Section(isExpanded: store.expansionBinding(for: LauncherStore.recentSection)) {
                ForEach(store.recentProjects) { project in
                    ProjectRow(project: project, showsPath: false).tag(project.path)
                }
            } header: {
                SidebarSectionHeader(title: "RECENT", icon: "clock",
                                     count: store.recentProjects.count)
            }
        }
    }

    @ViewBuilder
    private var userSections: some View {
        ForEach(store.sections) { section in
            Section(isExpanded: store.expansionBinding(for: section.id.uuidString)) {
                ForEach(store.projects(in: section)) { project in
                    ProjectRow(project: project, showsPath: false).tag(project.path)
                }
                .onMove { store.moveProjects(in: section, fromOffsets: $0, toOffset: $1) }
            } header: {
                SidebarSectionHeader(title: section.name.uppercased(), icon: nil,
                                     count: section.projectPaths.count)
                    .contextMenu {
                        Button("Rename…") {
                            renameText = section.name
                            renamingSection = section
                        }
                        Button("Delete Section", role: .destructive) {
                            store.deleteSection(section)
                        }
                    }
            }
            // Dropping onto a section files the project there. The context menu
            // on each row does the same thing, since cross-section dragging in
            // a sidebar List is easy to miss and easy to fumble.
            .dropDestination(for: String.self) { paths, _ in
                for path in paths { store.move(projectPath: path, toSection: section.id) }
                return !paths.isEmpty
            }
        }
    }

    @ViewBuilder
    private var unsortedSection: some View {
        let unsorted = store.unsortedProjects
        if !unsorted.isEmpty {
            Section(isExpanded: store.expansionBinding(for: LauncherStore.unsortedSection)) {
                ForEach(unsorted) { project in
                    ProjectRow(project: project, showsPath: false).tag(project.path)
                }
            } header: {
                SidebarSectionHeader(title: "UNSORTED", icon: "tray",
                                     count: unsorted.count)
            }
            .dropDestination(for: String.self) { paths, _ in
                for path in paths { store.move(projectPath: path, toSection: nil) }
                return !paths.isEmpty
            }
        }
    }

    private var addSectionBar: some View {
        Button {
            isAddingSection = true
        } label: {
            Label("New Section", systemImage: "plus")
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sidebar pieces

private struct SidebarSectionHeader: View {
    let title: String
    let icon: String?
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 9)).frame(width: 11)
            }
            Text(title).lineLimit(1).truncationMode(.tail)
            Text("\(count)").foregroundStyle(.tertiary).padding(.leading, 1)
        }
        .help(title)
    }
}

private struct ProjectRow: View {
    @EnvironmentObject private var store: LauncherStore
    let project: Project
    let showsPath: Bool

    @State private var isHovering = false

    private var isFavorite: Bool { store.isFavorite(project) }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: project.isGitRepo ? "folder.badge.gearshape" : "folder")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showsPath {
                    Text(project.displayPath)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer(minLength: 4)

            // The star's space is always reserved and only its opacity changes.
            // Showing and hiding the view itself reflowed the row's text every
            // time the pointer crossed it.
            Button { store.toggleFavorite(project) } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 14)
            .opacity(isFavorite ? 1 : (isHovering ? 0.55 : 0))
            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .draggable(project.path)
        .contextMenu {
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                store.toggleFavorite(project)
            }

            Menu("Move to Section") {
                ForEach(store.sections) { section in
                    Button(section.name) {
                        store.move(projectPath: project.path, toSection: section.id)
                    }
                }
                if !store.sections.isEmpty { Divider() }
                Button("Unsorted") {
                    store.move(projectPath: project.path, toSection: nil)
                }
            }

            Divider()
            Button("Reveal in Finder") { store.revealProject(project) }
        }
    }
}

private struct WelcomeSidebar: View {
    @EnvironmentObject private var store: LauncherStore

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            VStack(spacing: 4) {
                Text("No projects yet")
                    .font(.system(size: 13, weight: .medium))
                Text("Point the app at the folder your projects live in.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(store.roots.isEmpty ? "Choose Folder…" : "Choose Projects…") {
                if store.roots.isEmpty { store.chooseMainFolder() } else { store.beginCuration() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Launch panel

private struct LaunchPanel: View {
    @EnvironmentObject private var store: LauncherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                modelPicker
                permissionPicker
                effortPicker
                themePicker
                launchButton
                commandPreview
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var contentWidth: CGFloat { 430 }

    @ViewBuilder
    private var header: some View {
        if let project = store.selectedProject {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Text(project.name)
                        .font(.system(size: 22, weight: .semibold))
                    Button { store.toggleFavorite(project) } label: {
                        Image(systemName: store.isFavorite(project) ? "star.fill" : "star")
                            .font(.system(size: 15))
                            .foregroundStyle(store.isFavorite(project) ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(store.isFavorite(project) ? "Remove from favorites (⌘D)" : "Add to favorites (⌘D)")
                }

                Text(project.displayPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 14) {
                    Label(project.isGitRepo ? "git repo" : "no git repo",
                          systemImage: "arrow.triangle.branch")
                    if let section = store.section(containing: project.path) {
                        Label(section.name, systemImage: "square.stack")
                    }
                    if let lastUsed = store.lastUsedDescription(for: project) {
                        Label(lastUsed, systemImage: "clock")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
        }
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("MODEL")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(ClaudeModel.allCases) { model in
                    OptionCard(title: model.displayName,
                               subtitle: model.subtitle,
                               isSelected: store.selectedModel == model,
                               isDangerous: false) {
                        store.selectedModel = model
                    }
                }
            }
            .frame(maxWidth: contentWidth)
        }
    }

    private var permissionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("PERMISSIONS")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(PermissionMode.allCases) { mode in
                    OptionCard(title: mode.displayName,
                               subtitle: mode.subtitle,
                               isSelected: store.permissionMode == mode,
                               isDangerous: mode.isDangerous) {
                        store.permissionMode = mode
                    }
                }
            }
            .frame(maxWidth: contentWidth)
        }
    }

    private var effortPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("EFFORT")
            Picker("", selection: Binding(
                get: { store.effort },
                set: { store.effort = $0 })) {
                Text(EffortLevel.unsetLabel).tag(EffortLevel?.none)
                ForEach(EffortLevel.allCases) { level in
                    Text(level.displayName).tag(EffortLevel?.some(level))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: contentWidth)
        }
    }

    @ViewBuilder
    private var themePicker: some View {
        if !store.availableThemes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("TERMINAL THEME")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                          spacing: 8) {
                    ThemeSwatch(name: nil,
                                isSelected: store.terminalTheme == nil) {
                        store.terminalTheme = nil
                    }
                    ForEach(store.availableThemes, id: \.self) { theme in
                        ThemeSwatch(name: theme,
                                    isSelected: store.terminalTheme == theme) {
                            store.terminalTheme = theme
                        }
                    }
                }
                .frame(maxWidth: contentWidth)

                Text("Colours the Terminal window so concurrent sessions are tellable apart. The window is titled after the project.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: contentWidth, alignment: .leading)
            }
        }
    }

    private var launchButton: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                store.launch()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                    Text("Launch").fontWeight(.semibold)
                }
                .frame(maxWidth: contentWidth)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(store.claudePath == nil)

            if store.claudePath == nil {
                Label("The `claude` command wasn't found on this machine.",
                      systemImage: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            } else if let note = store.lastLaunchNote {
                Label(note, systemImage: "checkmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var commandPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("WILL RUN")
            Text(store.commandPreview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: contentWidth, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.08)))
        }
    }
}

// MARK: - Small components

/// A selectable card used for models and permission modes.
private struct OptionCard: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let isDangerous: Bool
    let action: () -> Void

    private var accent: Color { isDangerous ? .red : .accentColor }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if isDangerous {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.red)
                        }
                        Text(title).font(.system(size: 13, weight: .medium))
                    }
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? accent.opacity(0.12) : Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? accent.opacity(0.6) : Color.secondary.opacity(0.18)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A Terminal profile swatch showing the profile's real colours.
private struct ThemeSwatch: View {
    let name: String?
    let isSelected: Bool
    let action: () -> Void

    private var background: Color {
        guard let name, let color = TerminalThemes.backgroundColor(forProfile: name) else {
            return Color.secondary.opacity(0.15)
        }
        return Color(nsColor: color)
    }

    private var foreground: Color {
        guard let name, let color = TerminalThemes.textColor(forProfile: name) else {
            return Color.secondary
        }
        return Color(nsColor: color)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                // Draw the profile's own colours so the choice is visual rather
                // than a list of names you'd have to remember.
                Text(name ?? "Default")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(background)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                              lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name ?? "Terminal's default profile")
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.6)
    }
}

private struct EmptyStatePanel: View {
    @EnvironmentObject private var store: LauncherStore

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: store.needsSetup ? "folder.badge.plus" : "square.grid.2x2")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)

            Text(store.needsSetup ? "Welcome to Claude Launcher" : "Select a project")
                .font(.system(size: 15, weight: .medium))

            Text(store.needsSetup
                 ? "Choose the folder your projects live in. You'll get a list of everything inside it and pick which ones are real projects."
                 : "Pick a project on the left to start a Claude Code session there.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            if store.needsSetup {
                Button(store.roots.isEmpty ? "Choose Folder…" : "Choose Projects…") {
                    if store.roots.isEmpty { store.chooseMainFolder() } else { store.beginCuration() }
                }
                .controlSize(.large)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
