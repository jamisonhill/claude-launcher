// swift-tools-version:5.9
// Swift Package Manager manifest.
// We build a plain executable here; build.sh wraps the binary in a real
// macOS .app bundle (with an Info.plist) so it behaves like a normal app.

import PackageDescription

let package = Package(
    name: "ClaudeLauncher",
    platforms: [
        // macOS 13 is the minimum for the SwiftUI `Window` scene type we use.
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeLauncher",
            path: "Sources/ClaudeLauncher"
        )
    ]
)
