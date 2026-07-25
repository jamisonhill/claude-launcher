// swift-tools-version:5.9
// Swift Package Manager manifest.
// We build a plain executable here; build.sh wraps the binary in a real
// macOS .app bundle (with an Info.plist) so it behaves like a normal app.

import PackageDescription

let package = Package(
    name: "ClaudeLauncher",
    platforms: [
        // macOS 14 is the minimum for `Section(isExpanded:)`, which is what
        // gives the sidebar its collapsible disclosure triangles.
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeLauncher",
            path: "Sources/ClaudeLauncher"
        )
    ]
)
