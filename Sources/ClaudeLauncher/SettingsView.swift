import SwiftUI

// MARK: - Settings (⌘,)

struct SettingsView: View {
    @EnvironmentObject private var store: LauncherStore
    @State private var selectedRoot: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Main Folders")
                    .font(.system(size: 13, weight: .semibold))
                Text("Claude Launcher searches these folders when you choose projects.")
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
            .frame(height: 120)
            .overlay {
                if store.roots.isEmpty {
                    Text("No folders added yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                Button { store.chooseMainFolder() } label: { Image(systemName: "plus") }
                    .help("Add a main folder")
                Button {
                    if let selectedRoot {
                        store.removeRoot(selectedRoot)
                        self.selectedRoot = nil
                    }
                } label: { Image(systemName: "minus") }
                    .help("Remove the selected folder")
                    .disabled(selectedRoot == nil)

                Spacer()

                Button("Choose Projects…") { store.beginCuration() }
                    .controlSize(.small)
                    .disabled(store.roots.isEmpty)
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("Terminal Themes")
                    .font(.system(size: 13, weight: .semibold))
                Text("""
                     Themes come from the profiles installed in Terminal — the five \
                     most distinct dark ones. Picking one installs a copy named \
                     "Claude — <name>" so your own profiles are never modified. \
                     Manage them in Terminal → Settings → Profiles.
                     """)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(store.availableThemes.isEmpty
                     ? "No Terminal profiles found."
                     : "Available: " + store.availableThemes.joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("\(store.projects.count) projects in your library")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show Config Files…") { store.revealConfigFile() }
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 470)
    }
}
