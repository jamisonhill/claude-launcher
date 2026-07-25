import Foundation

// MARK: - Project discovery
//
// Scanning rule (kept deliberately simple so results are predictable):
//
//   1. Each configured root is itself launchable.
//   2. Every directory one level under a root is launchable.
//   3. A directory two levels down is included only when its parent looks like
//      a *container* rather than a project — i.e. the parent has no project
//      markers of its own. That's what pulls ~/Ai/Personal/apps/prayer into the
//      list without also dragging in every subfolder of a real repo.
//
// Anything in Config.excludes, and anything starting with ".", is skipped.

enum ProjectScanner {

    /// Files/folders that mark a directory as "a project in its own right".
    private static let projectMarkers = [
        ".git", "CLAUDE.md", "package.json", ".claude", "Package.swift",
        "pyproject.toml", "requirements.txt", "Cargo.toml", "go.mod",
        "Gemfile", "index.html", "README.md"
    ]

    /// Walks the configured roots and returns every launchable directory,
    /// sorted by group then name.
    static func scan(config: Config) -> [Project] {
        var found: [String: Project] = [:]   // keyed by path, so duplicates collapse

        for rawRoot in config.roots {
            let rootPath = (rawRoot as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            // A root listed in config.json may have been moved or deleted;
            // skip it rather than failing the whole scan.
            guard FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            // Rule 1: the root itself.
            let root = makeProject(path: rootPath)
            found[root.path] = root

            // Rule 2: everything one level down.
            for child in subdirectories(of: rootPath, excludes: config.excludes) {
                found[child] = makeProject(path: child)

                // Rule 3: descend one more level only into container folders.
                if !hasProjectMarker(child) {
                    for grandchild in subdirectories(of: child, excludes: config.excludes) {
                        found[grandchild] = makeProject(path: grandchild)
                    }
                }
            }
        }

        return found.values.sorted {
            $0.group == $1.group
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.group.localizedCaseInsensitiveCompare($1.group) == .orderedAscending
        }
    }

    // MARK: - Helpers

    /// Immediate subdirectories of `path`, minus hidden and excluded names.
    private static func subdirectories(of path: String, excludes: [String]) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            // Unreadable directory (permissions, dangling symlink) — treat as empty.
            return []
        }
        return names.compactMap { name in
            guard !name.hasPrefix("."), !excludes.contains(name) else { return nil }
            let full = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir),
                  isDir.boolValue else { return nil }
            return full
        }
    }

    /// True when the directory contains any of the marker files above.
    private static func hasProjectMarker(_ path: String) -> Bool {
        projectMarkers.contains { marker in
            FileManager.default.fileExists(
                atPath: (path as NSString).appendingPathComponent(marker))
        }
    }

    private static func makeProject(path: String) -> Project {
        let name = (path as NSString).lastPathComponent
        let parent = (path as NSString).deletingLastPathComponent

        return Project(
            path: path,
            name: name,
            group: groupLabel(forParent: parent),
            displayPath: abbreviate(path),
            isGitRepo: FileManager.default.fileExists(
                atPath: (path as NSString).appendingPathComponent(".git"))
        )
    }

    /// Turns "/Users/me/Ai/Personal/apps" into "PERSONAL / APPS" for the
    /// sidebar section header. Anything above ~/Ai keeps its own path.
    private static func groupLabel(forParent parent: String) -> String {
        let abbreviated = abbreviate(parent)
        var components = abbreviated
            .split(separator: "/")
            .map(String.init)

        // Drop the leading "~" and the "Ai" bucket — every project shares them,
        // so showing them in every header is just noise.
        if components.first == "~" { components.removeFirst() }
        if components.first == "Ai" { components.removeFirst() }

        guard !components.isEmpty else { return "ROOTS" }
        return components.joined(separator: " / ").uppercased()
    }

    /// Replaces the home directory prefix with "~" for display.
    private static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home)
            ? "~" + String(path.dropFirst(home.count))
            : path
    }
}
