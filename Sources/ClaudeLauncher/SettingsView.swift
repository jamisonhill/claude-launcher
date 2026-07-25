import SwiftUI

// MARK: - Settings (⌘,)
//
// Scan roots used to be editable only by hand-editing config.json. That's fine
// for the person who wrote the app and a dead end for anyone they hand it to,
// so root management lives here instead.

struct SettingsView: View {
    @EnvironmentObject private var store: LauncherStore
    @State private var selectedRoot: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Project Folders")
                    .font(.system(size: 13, weight: .semibold))
                Text("Claude Launcher looks inside these folders for projects.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            List(selection: $selectedRoot) {
                ForEach(store.roots, id: \.self) { root in
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(root)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    .tag(root)
                }
            }
            .frame(height: 150)
            .overlay {
                if store.roots.isEmpty {
                    Text("No folders added yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                Button {
                    store.presentAddRootPanel()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add a project folder")

                Button {
                    if let selectedRoot {
                        store.removeRoot(selectedRoot)
                        self.selectedRoot = nil
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .help("Remove the selected folder")
                .disabled(selectedRoot == nil)

                Spacer()

                Button("Rescan Now") { store.refresh() }
                    .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Toggle("Show folders without projects",
                       isOn: Binding(get: { store.showAllFolders },
                                     set: { store.setShowAllFolders($0) }))

                Text("""
                     By default only folders containing a project marker \
                     (.git, CLAUDE.md, package.json, and similar) are listed. \
                     Turn this on to see every folder inside your project \
                     folders instead.
                     """)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("\(store.projects.count) projects found")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show Config File…") { store.revealConfigFile() }
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
