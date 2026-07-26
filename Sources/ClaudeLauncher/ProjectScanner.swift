import Foundation

// MARK: - Candidate discovery
//
// The scanner's only job is to offer folders for the setup sheet. It decides
// *nothing* about what counts as a project — the user does that with the
// checkboxes.
//
// That inversion is the whole point. The previous version listed only folders
// carrying a marker file, which meant `MHIT/DATA-ANALYTICS/exec-dashboard` —
// a real project full of docs and schemas but with no .git or package.json —
// was invisible with no way to discover it was missing. Markers now only decide
// which boxes start ticked.
//
// Traversal: walk the whole tree, but stop descending once a folder looks like
// a project, so a repo's own subfolders aren't offered as separate projects.

enum ProjectScanner {

    /// Exact filenames marking a directory as probably-a-project. Used only to
    /// pre-tick boxes and to know where to stop descending.
    private static let markerNames: [String] = [
        ".git", "CLAUDE.md", ".claude", "package.json", "Package.swift",
        "pyproject.toml", "requirements.txt", "Cargo.toml", "go.mod",
        "Gemfile", "Makefile", "docker-compose.yml", "index.html"
    ]

    /// Marker file extensions. Xcode projects are named after the app, so they
    /// can't be matched by exact name.
    private static let markerExtensions = ["xcodeproj", "xcworkspace"]

    /// Hard ceiling on recursion depth. A runaway symlink or a pathological
    /// tree shouldn't be able to hang the setup sheet.
    private static let maxDepth = 6

    /// Walks every configured root and returns candidates in tree order.
    static func candidates(config: Config) -> [ProjectCandidate] {
        var results: [ProjectCandidate] = []
        let excludes = Set(config.excludes)

        for rawRoot in config.roots {
            let rootPath = (rawRoot as NSString).expandingTildeInPath
            guard isDirectory(rootPath) else { continue }
            walk(path: rootPath, depth: 0, excludes: excludes, into: &results)
        }
        return results
    }

    /// Depth-first walk that appends a candidate for every directory it visits.
    ///
    /// `suppressPreselect` stops a folder's children from being pre-ticked when
    /// the parent was already judged to be the project — see the container
    /// heuristic below.
    private static func walk(path: String,
                             depth: Int,
                             excludes: Set<String>,
                             suppressPreselect: Bool = false,
                             into results: inout [ProjectCandidate]) {
        guard depth < maxDepth else { return }

        let children = subdirectories(of: path, excludes: excludes)

        for child in children.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            if let marker = projectMarker(child) {
                results.append(makeCandidate(path: child, depth: depth,
                                             marker: marker,
                                             preselect: !suppressPreselect))
                // Stop here: a project's subfolders are parts of it, not
                // siblings of it.
                continue
            }

            // No marker. Look one level in to tell a *container* of projects
            // apart from a project that simply carries no marker file.
            //
            //   ~/Ai/Personal/apps        -> 11 marker-bearing children -> container
            //   MHIT/…/exec-dashboard     ->  1 marker-bearing child    -> the project
            //   MHIT/governance           ->  0                         -> neither
            //
            // Without this, exec-dashboard stayed unticked while the lone
            // `dashboard` folder inside it got pre-ticked instead — exactly
            // backwards from what you'd want.
            let grandchildren = subdirectories(of: child, excludes: excludes)
            let markerBearing = grandchildren.filter { projectMarker($0) != nil }.count
            let isProjectItself = markerBearing == 1

            results.append(makeCandidate(path: child, depth: depth,
                                         marker: nil,
                                         preselect: isProjectItself && !suppressPreselect))

            walk(path: child, depth: depth + 1, excludes: excludes,
                 suppressPreselect: isProjectItself, into: &results)
        }
    }

    private static func makeCandidate(path: String,
                                      depth: Int,
                                      marker: String?,
                                      preselect: Bool) -> ProjectCandidate {
        let visibleChildren = (try? FileManager.default.contentsOfDirectory(atPath: path))?
            .filter { !$0.hasPrefix(".") }.count ?? 0

        return ProjectCandidate(
            path: path,
            name: (path as NSString).lastPathComponent,
            displayPath: abbreviate(path),
            depth: depth,
            marker: marker,
            itemCount: visibleChildren,
            isGitRepo: FileManager.default.fileExists(
                atPath: (path as NSString).appendingPathComponent(".git")),
            preselect: preselect)
    }

    /// Builds the `Project` record stored in the library once a candidate is
    /// accepted.
    static func project(at path: String) -> Project {
        Project(path: path,
                name: (path as NSString).lastPathComponent,
                displayPath: abbreviate(path),
                isGitRepo: FileManager.default.fileExists(
                    atPath: (path as NSString).appendingPathComponent(".git")))
    }

    // MARK: - Helpers

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// Immediate subdirectories, minus hidden and excluded names. Symlinks are
    /// skipped so a link pointing up the tree can't cause infinite recursion.
    private static func subdirectories(of path: String, excludes: Set<String>) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            // Unreadable directory (permissions, dangling symlink) — treat as empty.
            return []
        }
        return names.compactMap { name in
            guard !name.hasPrefix("."), !excludes.contains(name) else { return nil }
            let full = (path as NSString).appendingPathComponent(name)

            guard let attrs = try? FileManager.default.attributesOfItem(atPath: full),
                  (attrs[.type] as? FileAttributeType) != .typeSymbolicLink else { return nil }

            return isDirectory(full) ? full : nil
        }
    }

    /// The first marker found in a directory, or nil. Returned rather than a
    /// Bool so the setup sheet can show *why* a box is pre-ticked.
    private static func projectMarker(_ path: String) -> String? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return nil
        }
        let contents = Set(names)
        if let hit = markerNames.first(where: { contents.contains($0) }) { return hit }
        if let hit = names.first(where: {
            markerExtensions.contains(($0 as NSString).pathExtension)
        }) {
            return hit
        }
        return nil
    }

    /// Replaces the home directory prefix with "~" for display.
    private static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }
}
