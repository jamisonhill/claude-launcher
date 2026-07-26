import SwiftUI

/// App entry point. A single window plus a settings pane.
@main
struct ClaudeLauncherApp: App {
    @StateObject private var store = LauncherStore()

    var body: some Scene {
        Window("Claude Launcher", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 840, minHeight: 620)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Main Folder…") { store.chooseMainFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Choose Projects…") { store.beginCuration() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(store.roots.isEmpty)
            }

            CommandMenu("Projects") {
                Button(store.selectedProject.map { store.isFavorite($0) } == true
                       ? "Remove from Favorites" : "Add to Favorites") {
                    store.toggleFavoriteForSelection()
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(store.selectedProject == nil)

                Button("Reveal in Finder") {
                    if let project = store.selectedProject { store.revealProject(project) }
                }
                .disabled(store.selectedProject == nil)

                Divider()

                Button("Collapse All Sections") { store.setAllSectionsExpanded(false) }
                Button("Expand All Sections") { store.setAllSectionsExpanded(true) }
            }
        }

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}
