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
        VStack(spacing: 0) {
            searchField
            Divider()
            projectList
            Divider()
            footer
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("Search projects…", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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
                            ProjectRow(project: project, showsPath: true)
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
                            ProjectRow(project: project, showsPath: true)
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
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                store.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Re-scan project folders (⌘R)")

            // Collapsing everything makes a 100-project sidebar navigable again.
            Button {
                store.setAllSectionsExpanded(store.allSectionsCollapsed)
            } label: {
                Image(systemName: store.allSectionsCollapsed
                      ? "chevron.down.square"
                      : "chevron.right.square")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(store.allSectionsCollapsed ? "Expand all sections" : "Collapse all sections")
            .disabled(store.isSearching)

            Spacer()

            Text("\(store.filteredProjects.count) projects")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

/// Sidebar section heading: name, item count, and a hover-revealed count badge.
private struct SidebarSectionHeader: View {
    let title: String
    let icon: String?
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
            }
            Text(title)
            Text("\(count)")
                .foregroundStyle(.tertiary)
                .padding(.leading, 1)
        }
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

            if isFavorite || isHovering {
                Button {
                    store.toggleFavorite(project)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
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
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("Select a project")
                .font(.system(size: 15, weight: .medium))
            Text("Pick a folder on the left to start a Claude Code session there.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
