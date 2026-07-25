import Foundation

// MARK: - Project discovery
//
// A folder is listed only when it looks like something you'd actually launch
// Claude in — that is, when it carries a project marker such as .git or
// CLAUDE.md. Listing every directory under a root is what made the sidebar
// unusable: document folders, asset folders, and scratch directories all
// showed up as "projects" and buried the real ones.
//
// The traversal:
//
//   1. Each configured root is always launchable, marker or not — you chose it
//      explicitly, so we don't second-guess it.
//   2. One level under a root, a folder is listed if it has a marker.
//   3. A folder *without* a marker is treated as a container and we look one
//      level inside it. That's what surfaces ~/Code/apps/my-app while ignoring
//      the "apps" folder itself.
//
// Setting `showAllFolders` relaxes rules 2 and 3 to list everything.
//
// Nothing here assumes any particular directory layout: group names are derived
// relative to whichever root a project was found under, so the sidebar reads
// correctly no matter where someone keeps their code.

enum ProjectScanner {

    /// Exact filenames that mark a directory as "a project in its own right".
    ///
    /// Deliberately excludes README.md — nearly every documentation folder has
    /// one, so it lets through exactly the noise this list exists to filter.
    private static let markerNames: Set<String> = [
        ".git", "CLAUDE.md", ".claude", "package.json", "Package.swift",
        "pyproject.toml", "requirements.txt", "Cargo.toml", "go.mod",
        "Gemfile", "Makefile", "docker-compose.yml", "index.html"
    ]

    /// Marker file *extensions*, matched against any entry in the directory.
    /// Xcode projects are named after the app, so they can't be matched exactly.
    private static let markerExtensions = ["xcodeproj", "xcworkspace"]

    /// Section heading used for the configured roots themselves.
    static let rootsGroup = "ROOTS"

    /// Walks the configured roots and returns every launchable directory,
    /// sorted by group then name.
    static func scan(config: Config) -> [Project] {
        var found: [String: Project] = [:]   // keyed by path, so duplicates collapse

        for rawRoot in config.roots {
            let rootPath = (rawRoot as NSString).expandingTildeInPath
            // A root may have been moved or deleted since it was added; skip it
            // rather than failing the whole scan.
            guard isDirectory(rootPath) else { continue }

            // Rule 1: the root itself is always launchable.
            found[rootPath] = makeProject(path: rootPath, group: rootsGroup)

            for child in subdirectories(of: rootPath, excludes: config.excludes) {
                let childIsProject = hasProjectMarker(child)

                // Rule 2
                if childIsProject || config.showAllFolders {
                    found[child] = makeProject(
                        path: child,
                        group: groupLabel(root: rootPath, parent: rootPath))
                }

                // Rule 3: only descend into things that aren't projects
                // themselves, so we never list a repo's own subfolders.
                if !childIsProject {
                    for grandchild in subdirectories(of: child, excludes: config.excludes) {
                        if hasProjectMarker(grandchild) || config.showAllFolders {
                            found[grandchild] = makeProject(
                                path: grandchild,
                                group: groupLabel(root: rootPath, parent: child))
                        }
                    }
                }
            }
        }

        return rollUpSmallGroups(Array(found.values)).sorted {
            $0.group == $1.group
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : $0.group.localizedCaseInsensitiveCompare($1.group) == .orderedAscending
        }
    }

    /// Folds nested groups holding a single project back into their top-level
    /// group, so "MHIT / FARGO" with one item becomes part of "MHIT".
    ///
    /// A section header costs about as much vertical space as a row does. A
    /// header introducing one project is therefore pure overhead — and a deep
    /// directory tree generates a lot of them.
    private static func rollUpSmallGroups(_ projects: [Project]) -> [Project] {
        var counts: [String: Int] = [:]
        for project in projects {
            counts[project.group, default: 0] += 1
        }

        return projects.map { project in
            guard counts[project.group] == 1,
                  let topLevel = project.group.components(separatedBy: " / ").first,
                  topLevel != project.group
            else { return project }

            return Project(path: project.path,
                           name: project.name,
                           group: topLevel,
                           displayPath: project.displayPath,
                           isGitRepo: project.isGitRepo)
        }
    }

    // MARK: - Helpers

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// Immediate subdirectories of `path`, minus hidden and excluded names.
    private static func subdirectories(of path: String, excludes: [String]) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            // Unreadable directory (permissions, dangling symlink) — treat as empty.
            return []
        }
        return names.compactMap { name in
            guard !name.hasPrefix("."), !excludes.contains(name) else { return nil }
            let full = (path as NSString).appendingPathComponent(name)
            return isDirectory(full) ? full : nil
        }
    }

    /// True when the directory contains any marker file.
    ///
    /// We list the directory once and check both marker forms against it, which
    /// is a single filesystem call instead of one `fileExists` per marker.
    private static func hasProjectMarker(_ path: String) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return false
        }
        if !markerNames.isDisjoint(with: Set(names)) { return true }
        return names.contains { name in
            markerExtensions.contains((name as NSString).pathExtension)
        }
    }

    private static func makeProject(path: String, group: String) -> Project {
        Project(
            path: path,
            name: (path as NSString).lastPathComponent,
            group: group,
            displayPath: abbreviate(path),
            isGitRepo: FileManager.default.fileExists(
                atPath: (path as NSString).appendingPathComponent(".git"))
        )
    }

    /// Builds a section heading from a project's position *relative to its root*.
    ///
    ///   root ~/Ai/Personal, parent ~/Ai/Personal       -> "PERSONAL"
    ///   root ~/Ai/Personal, parent ~/Ai/Personal/apps  -> "PERSONAL / APPS"
    ///   root ~/Code,        parent ~/Code              -> "CODE"
    ///
    /// Relative derivation is what makes this portable: an earlier version
    /// stripped a hardcoded "~/Ai" prefix, which produced nonsense headings on
    /// any machine that didn't have that exact directory.
    private static func groupLabel(root: String, parent: String) -> String {
        let rootName = (root as NSString).lastPathComponent

        guard parent != root else { return rootName.uppercased() }

        let relative = String(parent.dropFirst(root.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = relative.split(separator: "/").map(String.init)

        return ([rootName] + components)
            .joined(separator: " / ")
            .uppercased()
    }

    /// Replaces the home directory prefix with "~" for display.
    private static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home)
            ? "~" + String(path.dropFirst(home.count))
            : path
    }
}
