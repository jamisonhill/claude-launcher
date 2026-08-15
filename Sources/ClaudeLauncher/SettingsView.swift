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

            AIToolsSection()

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

// MARK: - AI tools

/// Which CLIs the launcher offers.
///
/// The list is what was actually found on this machine, so a tool that isn't
/// installed says so rather than silently missing — "scan the computer" and
/// "ask the user" both being part of what makes the picker trustworthy.
private struct AIToolsSection: View {
    @EnvironmentObject private var store: LauncherStore

    @State private var isAddingTool = false
    @State private var newName = ""
    @State private var newBinary = ""
    @State private var newArguments = ""
    @State private var editingArgsFor: String?
    @State private var argsDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Tools")
                        .font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                Button("Add Tool…") { isAddingTool = true }
                    .controlSize(.small)
            }

            // Full width, below the button row: sharing a line with the button
            // squeezed this to "…appear in the launc…".
            Text("Tools found on this Mac. Only enabled ones appear in the launch panel.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(store.allTools) { resolved in
                    toolRow(resolved)
                    if resolved.id != store.allTools.last?.id { Divider() }
                }
            }
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06)))
        }
        .sheet(isPresented: $isAddingTool) { addToolSheet }
        .sheet(isPresented: Binding(get: { editingArgsFor != nil },
                                    set: { if !$0 { editingArgsFor = nil } })) {
            argumentsSheet
        }
    }

    private func toolRow(_ resolved: ResolvedTool) -> some View {
        let enabled = !store.toolSettings.disabledToolIDs.contains(resolved.id)
        let extras = store.extraArgumentsText(for: resolved.id)

        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { enabled },
                set: { store.setToolEnabled(resolved.id, $0) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
                // A tool that isn't installed can't be launched, so its switch
                // would promise something the app can't deliver.
                .disabled(!resolved.isInstalled)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(resolved.tool.name)
                        .font(.system(size: 12, weight: .medium))
                    if !resolved.tool.isBuiltIn {
                        Text("custom")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(resolved.path ?? "not installed — `\(resolved.tool.binary)` wasn't found")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(resolved.isInstalled ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.head)
                if !extras.isEmpty {
                    Text("extra: \(extras)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            Button {
                argsDraft = extras
                editingArgsFor = resolved.id
            } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .help("Extra arguments passed on every launch")

            if !resolved.tool.isBuiltIn {
                Button {
                    store.removeCustomTool(resolved.id)
                } label: {
                    Image(systemName: "trash").font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Remove this custom tool")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }

    private var addToolSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a Tool").font(.system(size: 14, weight: .semibold))
            Text("""
                 For any CLI this app doesn't ship a definition for. Give it the \
                 command name and the flags you want on every launch — they're \
                 passed through exactly as typed.
                 """)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                TextField("Name", text: $newName, prompt: Text("Codex"))
                TextField("Command", text: $newBinary, prompt: Text("codex"))
                TextField("Arguments", text: $newArguments, prompt: Text("--full-auto"))
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { resetAddSheet() }
                Button("Add") {
                    store.addCustomTool(name: newName, binary: newBinary, arguments: newArguments)
                    resetAddSheet()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                          || newBinary.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var argumentsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extra Arguments").font(.system(size: 14, weight: .semibold))
            Text("Added to every launch of this tool, after the options above and before any opening prompt.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("", text: $argsDraft, prompt: Text("-m gemini-2.5-pro"))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            HStack {
                Spacer()
                Button("Cancel") { editingArgsFor = nil }
                Button("Save") {
                    if let id = editingArgsFor { store.setExtraArguments(argsDraft, for: id) }
                    editingArgsFor = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func resetAddSheet() {
        isAddingTool = false
        newName = ""; newBinary = ""; newArguments = ""
    }
}
