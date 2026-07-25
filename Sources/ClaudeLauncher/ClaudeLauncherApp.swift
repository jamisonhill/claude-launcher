import SwiftUI

/// App entry point. A single window plus a settings pane.
@main
struct ClaudeLauncherApp: App {
    @StateObject private var store = LauncherStore()

    var body: some Scene {
        Window("Claude Launcher", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 540)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Replace the useless "New Window" item with the things this app
            // actually needs from the menu bar.
            CommandGroup(replacing: .newItem) {
                Button("Add Project Folder…") {
                    store.presentAddRootPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Refresh Projects") {
                    store.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandMenu("Projects") {
                Button(store.selectedProject.map { store.isFavorite($0) } == true
                       ? "Remove from Favorites"
                       : "Add to Favorites") {
                    store.toggleFavoriteForSelection()
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(store.selectedProject == nil)

                Button("Reveal in Finder") {
                    if let project = store.selectedProject {
                        store.revealProject(project)
                    }
                }
                .disabled(store.selectedProject == nil)

                Divider()

                Button("Collapse All Sections") {
                    store.setAllSectionsExpanded(false)
                }
                Button("Expand All Sections") {
                    store.setAllSectionsExpanded(true)
                }

                Divider()

                Toggle("Show Folders Without Projects",
                       isOn: Binding(get: { store.showAllFolders },
                                     set: { store.setShowAllFolders($0) }))
            }
        }

        // Gives us the standard ⌘, Settings item for free.
        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
