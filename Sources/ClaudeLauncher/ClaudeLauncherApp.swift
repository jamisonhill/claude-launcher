import SwiftUI

/// App entry point. A single window, no document model.
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
            // Replace the useless "New Window" item with the two things this
            // app actually needs from the menu bar.
            CommandGroup(replacing: .newItem) {
                Button("Refresh Projects") {
                    store.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Show Config File in Finder") {
                    store.revealConfigFile()
                }
            }
        }
    }
}
