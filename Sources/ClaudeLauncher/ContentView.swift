import SwiftUI

// MARK: - Main window
//
// Two panes: a searchable project list on the left, launch controls on the
// right. Icons are SF Symbols throughout.

struct ContentView: View {
    @EnvironmentObject private var store: LauncherStore

    var body: some View {
        NavigationSplitView {
            ProjectSidebar()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            if store.selectedProject != nil {
                LaunchPanel()
            } else {
                EmptyStatePanel()
            }
        }
        // Launch failures surface here rather than in a silent log.
        .alert("Couldn't launch",
               isPresented: Binding(
                   get: { store.errorMessage != nil },
                   set: { if !$0 { store.errorMessage = nil } }
               ),
               actions: {
                   Button("OK", role: .cancel) { store.errorMessage = nil }
               },
               message: {
                   Text(store.errorMessage ?? "")
               })
    }
}

// MARK: - Sidebar

private struct ProjectSidebar: View {
    @EnvironmentObject private var store: LauncherStore

    var body: some View {
        Group {
            if store.hasNoRoots {
                NoRootsSidebar()
            } else {
                projectList
            }
        }
        // The system search field replaces a hand-rolled icon + TextField +
        // clear button, and brings focus handling and ⌘F along with it.
        .searchable(text: $store.searchText,
                    placement: .sidebar,
                    prompt: "Search projects")
        // Refresh and collapse-all live in the window toolbar rather than a
        // sidebar footer, which is the native placement and gives the list
        // back its vertical space.
        .toolbar {
            ToolbarItem {
                Button {
                    store.setAllSectionsExpanded(store.allSectionsCollapsed)
                } label: {
                    Image(systemName: store.allSectionsCollapsed
                          ? "rectangle.expand.vertical"
                          : "rectangle.compress.vertical")
                }
                .help(store.allSectionsCollapsed
                      ? "Expand all sections"
                      : "Collapse all sections")
                .disabled(store.isSearching || store.hasNoRoots)
            }

            ToolbarItem {
                Menu {
                    Toggle("Show Folders Without Projects",
                           isOn: Binding(get: { store.showAllFolders },
                                         set: { store.setShowAllFolders($0) }))
                    Divider()
                    Button("Add Folder…") { store.presentAddRootPanel() }
                    Button("Refresh") { store.refresh() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Project list options")
            }
        }
    }

    private var projectList: some View {
        List(selection: Binding(
            get: { store.selectedPath },
            set: { newValue in
                // Selecting through the List binding must go through select()
                // so the model / permission state gets restored too.
                if let newValue,
                   let project = store.projects.first(where: { $0.path == newValue }) {
                    store.select(project)
                }
            }
        )) {
            // While searching we show one flat list of matches — sections and
            // their collapse state would just get in the way of finding things.
            if store.isSearching {
                ForEach(store.filteredProjects) { project in
                    ProjectRow(project: project, showsPath: true)
                        .tag(project.path)
                }
            } else {
                if !store.favoriteProjects.isEmpty {
                    Section(isExpanded: store.expansionBinding(for: LauncherStore.favoritesSection)) {
                        ForEach(store.favoriteProjects) { project in
                            ProjectRow(project: project, showsPath: false)
                                .tag(project.path)
                        }
                        .onMove { offsets, destination in
                            store.moveFavorites(fromOffsets: offsets, toOffset: destination)
                        }
                    } header: {
                        SidebarSectionHeader(title: LauncherStore.favoritesSection,
                                             icon: "star.fill",
                                             count: store.favoriteProjects.count)
                    }
                }

                if !store.recentProjects.isEmpty {
                    Section(isExpanded: store.expansionBinding(for: LauncherStore.recentSection)) {
                        ForEach(store.recentProjects) { project in
                            ProjectRow(project: project, showsPath: false)
                                .tag(project.path)
                        }
                    } header: {
                        SidebarSectionHeader(title: LauncherStore.recentSection,
                                             icon: "clock",
                                             count: store.recentProjects.count)
                    }
                }

                ForEach(store.groupedProjects, id: \.group) { section in
                    Section(isExpanded: store.expansionBinding(for: section.group)) {
                        ForEach(section.projects) { project in
                            ProjectRow(project: project, showsPath: false)
                                .tag(project.path)
                        }
                    } header: {
                        SidebarSectionHeader(title: section.group,
                                             icon: nil,
                                             count: section.projects.count)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            // A search that matches nothing used to leave a blank sidebar with
            // no explanation of why.
            if store.isSearching && store.filteredProjects.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            }
        }
    }
}

/// Sidebar section heading: optional icon, name, and item count.
private struct SidebarSectionHeader: View {
    let title: String
    let icon: String?
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            // Only Favorites and Recent carry an icon. Folder groups repeat a
            // dozen times over, and an icon on each is pure visual frequency.
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .frame(width: 11)
            }
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("\(count)")
                .foregroundStyle(.tertiary)
                .padding(.leading, 1)
        }
        // Long group names truncate in a 240pt sidebar, so the full name has to
        // be recoverable somewhere.
        .help(title)
    }
}

/// Shown in place of the list on a fresh install, before any folder is chosen.
private struct NoRootsSidebar: View {
    @EnvironmentObject private var store: LauncherStore

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("No folders yet")
                    .font(.system(size: 13, weight: .medium))
                Text("Choose a folder that holds your projects.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Add Folder…") {
                store.presentAddRootPanel()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One row in the sidebar, with a star for pinning.
///
/// The star only appears on hover or when the project is already favorited, so
/// a hundred-row sidebar isn't a wall of empty outlines.
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
            // Showing/hiding the view itself reflowed the row's text every time
            // the pointer crossed it.
            Button {
                store.toggleFavorite(project)
            } label: {
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
        .contextMenu {
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                store.toggleFavorite(project)
            }
            Divider()
            Button("Reveal in Finder") {
                store.revealProject(project)
            }
        }
    }
}

// MARK: - Detail: launch controls

private struct LaunchPanel: View {
    @EnvironmentObject private var store: LauncherStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                modelPicker
                permissionsToggle
                launchButton
                commandPreview
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Header — which project is selected

    @ViewBuilder
    private var header: some View {
        if let project = store.selectedProject {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    Text(project.name)
                        .font(.system(size: 22, weight: .semibold))

                    Button {
                        store.toggleFavorite(project)
                    } label: {
                        Image(systemName: store.isFavorite(project) ? "star.fill" : "star")
                            .font(.system(size: 15))
                            .foregroundStyle(store.isFavorite(project)
                                             ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(store.isFavorite(project)
                          ? "Remove from favorites (⌘D)"
                          : "Add to favorites (⌘D)")
                }

                Text(project.displayPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 14) {
                    Label(project.isGitRepo ? "git repo" : "no git repo",
                          systemImage: "arrow.triangle.branch")
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

    // MARK: Model buttons

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("MODEL")

            // Two-by-two grid of large, clickable model cards.
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10),
                          GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(ClaudeModel.allCases) { model in
                    ModelCard(model: model,
                              isSelected: store.selectedModel == model) {
                        store.selectedModel = model
                    }
                }
            }
            .frame(maxWidth: 420)
        }
    }

    // MARK: The dangerous flag

    private var permissionsToggle: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("PERMISSIONS")

            Toggle(isOn: $store.skipPermissions) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: store.skipPermissions
                          ? "exclamationmark.triangle.fill"
                          : "lock.shield")
                        .font(.system(size: 14))
                        .foregroundStyle(store.skipPermissions ? .red : .secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip permission prompts")
                            .font(.system(size: 13, weight: .medium))
                        Text(store.skipPermissions
                             ? "Claude runs commands without asking. Trusted folders only."
                             : "Claude asks before running commands or editing files.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(.red)
            .padding(12)
            .frame(maxWidth: 420, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(store.skipPermissions
                          ? Color.red.opacity(0.07)
                          : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(store.skipPermissions
                                  ? Color.red.opacity(0.35)
                                  : Color.secondary.opacity(0.2))
            )
        }
    }

    // MARK: Launch

    private var launchButton: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                store.launch()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                    Text("Launch")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: 420)
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

    // MARK: Command preview

    private var commandPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("WILL RUN")

            Text(store.commandPreview)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: 420, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                )
        }
    }
}

/// A single selectable model card.
private struct ModelCard: View {
    let model: ClaudeModel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(size: 14, weight: .medium))
                    Text(model.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.12)
                          : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected
                                  ? Color.accentColor.opacity(0.6)
                                  : Color.secondary.opacity(0.18))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Small uppercase heading used above each control group.
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

// MARK: - Empty state

private struct EmptyStatePanel: View {
    @EnvironmentObject private var store: LauncherStore

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.system(size: 15, weight: .medium))

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            // A fresh install has no projects and no obvious next step, so the
            // way forward is a button rather than a line of documentation.
            if store.hasNoRoots {
                Button("Add Folder…") { store.presentAddRootPanel() }
                    .controlSize(.large)
                    .padding(.top, 2)
            } else if store.projects.isEmpty {
                HStack(spacing: 8) {
                    Button("Add Another Folder…") { store.presentAddRootPanel() }
                    Button("Show All Folders") { store.setShowAllFolders(true) }
                }
                .controlSize(.large)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: String {
        store.hasNoRoots ? "folder.badge.plus"
            : store.projects.isEmpty ? "magnifyingglass" : "square.grid.2x2"
    }

    private var title: String {
        store.hasNoRoots ? "Welcome to Claude Launcher"
            : store.projects.isEmpty ? "No projects found" : "Select a project"
    }

    private var message: String {
        if store.hasNoRoots {
            return "Choose the folder your projects live in, and they'll show up in the sidebar."
        }
        if store.projects.isEmpty {
            return "Nothing in your folders looks like a project. Claude Launcher looks for markers like .git, CLAUDE.md, or package.json — you can list every folder instead."
        }
        return "Pick a folder on the left to start a Claude Code session there."
    }
}
